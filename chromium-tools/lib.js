import { homedir } from "node:os";
import { join } from "node:path";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import net from "node:net";
import puppeteer from "puppeteer";

export const CACHE_DIR = join(homedir(), ".cache", "browser-tools");
export const REGISTRY = join(CACHE_DIR, "sessions.json");

export const HEARTBEAT_MS = 5000;
export const HEARTBEAT_STALE_MS = 15000;

// ----- per-session paths -------------------------------------------------
// Each session keeps its profile and monitor logs in its own directory so
// sessions never clobber one another.
export function sessionDir(name) {
	return join(CACHE_DIR, "sessions", name);
}
export function profileDir(name) {
	return join(sessionDir(name), "profile");
}
export function monitorJson(name) {
	return join(sessionDir(name), "monitor.json");
}
export function monitorErr(name) {
	return join(sessionDir(name), "monitor.err");
}
export function consoleLog(name) {
	return join(sessionDir(name), "console.jsonl");
}
export function networkLog(name) {
	return join(sessionDir(name), "network.jsonl");
}

// ----- argument parsing --------------------------------------------------
// Pull `--session NAME` out of an argv array, returning { session, rest }
// where `rest` is argv with the flag removed so each script's own flag
// parsing keeps working unchanged. Precedence: --session > BROWSER_SESSION
// env var > "default".
export function extractSession(argv) {
	const rest = [];
	let session = null;
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === "--session") {
			session = argv[i + 1];
			i++;
			continue;
		}
		rest.push(argv[i]);
	}
	session = session || process.env.BROWSER_SESSION || "default";
	return { session, rest };
}

// ----- session registry --------------------------------------------------
export function readRegistry() {
	if (!existsSync(REGISTRY)) return {};
	try {
		return JSON.parse(readFileSync(REGISTRY, "utf8"));
	} catch {
		return {};
	}
}
export function writeRegistry(reg) {
	mkdirSync(CACHE_DIR, { recursive: true });
	writeFileSync(REGISTRY, JSON.stringify(reg, null, 2));
}
export function pidAlive(pid) {
	if (!pid) return false;
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

// Find a free TCP port at or above `start` (default 9222).
export function findFreePort(start = 9222) {
	return new Promise((resolve) => {
		const tryPort = (port) => {
			const srv = net.createServer();
			srv.once("error", () => tryPort(port + 1));
			srv.once("listening", () => srv.close(() => resolve(port)));
			srv.listen(port, "127.0.0.1");
		};
		tryPort(start);
	});
}

// Resolve a session name to its debugging port. Cleans a dead entry from
// the registry and exits(1) with guidance if the session is not running.
export function resolvePort(session) {
	const reg = readRegistry();
	const entry = reg[session];
	if (entry && !pidAlive(entry.pid)) {
		delete reg[session];
		writeRegistry(reg);
	}
	if (!entry || !pidAlive(entry.pid)) {
		console.error(`✗ Session "${session}" is not running`);
		const flag = session === "default" ? "" : ` --session ${session}`;
		console.error(`  Run: browser-start.js${flag}`);
		process.exit(1);
	}
	return entry.port;
}

// ----- connection --------------------------------------------------------
// Connect to a browser on the given port with a 5s timeout. Returns the
// browser or null — never throws, never exits.
export async function tryConnect(port) {
	return Promise.race([
		puppeteer.connect({ browserURL: `http://localhost:${port}`, defaultViewport: null }),
		new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000)),
	]).catch(() => null);
}

// Resolve a session to its port, connect, or exit(1) with guidance.
export async function connect(session) {
	const port = resolvePort(session);
	const browser = await tryConnect(port);
	if (!browser) {
		console.error(`✗ Could not connect to session "${session}" on :${port}`);
		console.error("  The browser may have crashed. Run: browser-start.js");
		process.exit(1);
	}
	return browser;
}

// Return the foreground (visible) tab, falling back to the most recently
// opened. Scripts act on this so `browser-tabs.js select` genuinely
// changes which tab subsequent commands target.
export async function getPage(browser) {
	const pages = await browser.pages();
	if (pages.length === 0) return null;
	for (const p of pages) {
		try {
			if (await p.evaluate(() => document.visibilityState === "visible")) return p;
		} catch {}
	}
	return pages.at(-1);
}

// ----- element targeting -------------------------------------------------
// An "@eN" token (produced by browser-snapshot.js) resolves to the data
// attribute selector; anything else is treated as a CSS selector unchanged.
export function resolveTarget(arg) {
	if (/^@e\d+$/.test(arg)) return `[data-ct-ref="${arg.slice(1)}"]`;
	return arg;
}

// Wait until `target` (CSS selector or @eN ref) is present, visible,
// enabled, and geometrically stable. Returns the ElementHandle. Throws a
// clear, actionable error on timeout.
export async function waitActionable(page, target, timeout = 5000) {
	const selector = resolveTarget(target);
	const deadline = Date.now() + timeout;
	let handle;
	try {
		handle = await page.waitForSelector(selector, { visible: true, timeout });
	} catch {
		const isRef = target.startsWith("@");
		throw new Error(
			isRef
				? `ref ${target} not found or not visible — re-run browser-snapshot.js`
				: `selector not found or not visible: ${target}`,
		);
	}
	const enabled = await handle.evaluate(
		(el) => !el.disabled && el.getAttribute("aria-disabled") !== "true",
	);
	if (!enabled) throw new Error(`element is disabled: ${target}`);
	// Stability: bounding box unchanged across two animation frames.
	while (Date.now() < deadline) {
		const a = await handle.boundingBox();
		await page.evaluate(
			() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
		);
		const b = await handle.boundingBox();
		if (a && b && a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height) {
			return handle;
		}
	}
	throw new Error(`element did not become stable (still animating): ${target}`);
}

// ----- monitor liveness --------------------------------------------------
export function readMonitor(session) {
	const path = monitorJson(session);
	if (!existsSync(path)) return null;
	try {
		return JSON.parse(readFileSync(path, "utf8"));
	} catch {
		return null;
	}
}

// Liveness: monitor.json exists, its pid is alive, and the heartbeat is
// fresh. A stale heartbeat covers crashed/hung daemons and PID reuse.
export function isMonitorAlive(session, info = readMonitor(session)) {
	if (!info || !info.pid || !info.lastHeartbeat) return false;
	if (!pidAlive(info.pid)) return false;
	return Date.now() - info.lastHeartbeat < HEARTBEAT_STALE_MS;
}
