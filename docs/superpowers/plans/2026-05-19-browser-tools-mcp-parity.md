# browser-tools MCP-parity Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the `browser-tools` skill into a practical, MCP-free alternative to Puppeteer MCP / Chrome DevTools MCP — named multi-sessions, an accessibility snapshot with stable element refs, actionability waits, and a set of parity tools (tabs, dialog, upload, wait, hover, select, drag, scroll, key).

**Architecture:** Plain CLI scripts kept stateless — each connects fresh, acts, disconnects. A passive registry file (`~/.cache/browser-tools/sessions.json`) maps named sessions to debugging ports. `browser-snapshot.js` annotates the live DOM with `data-ct-ref` attributes so interaction tools can target `@eN` refs that survive across separate process invocations.

**Tech Stack:** Node.js (ESM, top-level await), puppeteer (bundled Chromium), Node's built-in `node:test` runner. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-19-browser-tools-mcp-parity-design.md`

---

## File Structure

All paths under `browser-tools/` unless noted.

**Created:**
- `browser-snapshot.js` — accessibility tree + `@eN` ref assignment
- `browser-tabs.js` — list/new/select/close tabs
- `browser-dialog.js` — pre-arm alert/confirm/prompt handling
- `browser-upload.js` — set files on a file input
- `browser-wait.js` — wait for selector/text/navigation/idle/delay
- `browser-hover.js` — hover an element
- `browser-select.js` — choose `<select>` option(s)
- `browser-drag.js` — drag between two elements
- `browser-scroll.js` — scroll page or element into view
- `browser-key.js` — press keys/chords
- `browser-sessions.js` — list/kill named sessions
- `test/lib.test.js` — unit tests for pure helpers
- `test/fixtures/*.html` — deterministic test pages
- `test/smoke.sh` — end-to-end smoke test of every tool

**Modified:**
- `lib.js` — registry helpers, port allocation, session resolution, `getPage`, `resolveTarget`, `waitActionable`, per-session paths
- `browser-start.js` — port allocation, registry entry, `--session`
- `browser-monitor.js` — per-session daemon and log paths
- `browser-click.js`, `browser-type.js` — `@eN` refs + `waitActionable`
- `browser-nav.js`, `browser-eval.js`, `browser-screenshot.js`, `browser-content.js`, `browser-cookies.js`, `browser-console.js`, `browser-network.js`, `browser-trace.js` — `--session` support, `getPage`
- `browser-trace.js` — also: clearer subresource-count label
- `SKILL.md` — document sessions, snapshot/ref workflow, all new tools

---

## Task 1: Session foundation in `lib.js`

Adds the registry, port allocation, session resolution, and arg parsing. `connect()`/`tryConnect()` gain parameters — callers are updated in later tasks; `browser-monitor.js` is the only existing caller and is updated in Task 5, so the codebase will not run cleanly until Task 5. That is expected.

**Files:**
- Modify: `browser-tools/lib.js`
- Test: `browser-tools/test/lib.test.js`

- [ ] **Step 1: Write the failing test**

Create `browser-tools/test/lib.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { extractSession } from "../lib.js";

test("extractSession: defaults to 'default' with no flag or env", () => {
	delete process.env.BROWSER_SESSION;
	const { session, rest } = extractSession(["nav", "https://x.com"]);
	assert.equal(session, "default");
	assert.deepEqual(rest, ["nav", "https://x.com"]);
});

test("extractSession: --session flag wins and is stripped from rest", () => {
	process.env.BROWSER_SESSION = "fromenv";
	const { session, rest } = extractSession(["--session", "work", "https://x.com"]);
	assert.equal(session, "work");
	assert.deepEqual(rest, ["https://x.com"]);
	delete process.env.BROWSER_SESSION;
});

test("extractSession: BROWSER_SESSION env used when no flag", () => {
	process.env.BROWSER_SESSION = "envsess";
	const { session, rest } = extractSession(["--errors"]);
	assert.equal(session, "envsess");
	assert.deepEqual(rest, ["--errors"]);
	delete process.env.BROWSER_SESSION;
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd browser-tools && node --test test/*.test.js`
Expected: FAIL — `extractSession` is not exported from `lib.js`.

- [ ] **Step 3: Rewrite `lib.js`**

Replace the entire contents of `browser-tools/lib.js` with:

```js
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
```

- [ ] **Step 4: Add a unit test for `resolveTarget`**

Append to `browser-tools/test/lib.test.js`:

```js
import { resolveTarget } from "../lib.js";

test("resolveTarget: @eN token becomes a data-ct-ref selector", () => {
	assert.equal(resolveTarget("@e5"), '[data-ct-ref="e5"]');
});

test("resolveTarget: ordinary selectors pass through unchanged", () => {
	assert.equal(resolveTarget("#submit"), "#submit");
	assert.equal(resolveTarget("button.primary"), "button.primary");
});
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd browser-tools && node --test test/*.test.js`
Expected: PASS — 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add browser-tools/lib.js browser-tools/test/lib.test.js
git commit -m "feat(browser-tools): session registry and targeting helpers in lib.js"
```

---

## Task 2: `browser-start.js` — per-session launch

Allocate a free port, launch the browser, and record the session in the registry.

**Files:**
- Modify: `browser-tools/browser-start.js`

- [ ] **Step 1: Rewrite `browser-start.js`**

Replace the entire contents of `browser-tools/browser-start.js` with:

```js
#!/usr/bin/env node

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, cpSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { homedir, platform } from "node:os";
import { fileURLToPath } from "node:url";

// Preflight: dependencies must be installed before puppeteer/lib.js can be
// imported. A static import of a missing package fails at module
// resolution, so this check and the imports it guards are dynamic.
const SKILL_DIR = dirname(fileURLToPath(import.meta.url));
if (!existsSync(join(SKILL_DIR, "node_modules", "puppeteer"))) {
	console.error("✗ browser-tools dependencies not installed");
	console.error(`  Run: cd "${SKILL_DIR}" && npm install`);
	process.exit(1);
}

const puppeteer = (await import("puppeteer")).default;
const lib = await import("./lib.js");
const { extractSession, profileDir, sessionDir, findFreePort, readRegistry, writeRegistry, pidAlive } = lib;

// Parse: browser-start.js [--profile] [--session NAME]
const { session, rest } = extractSession(process.argv.slice(2));
const useProfile = rest.includes("--profile");
const unknown = rest.filter((a) => a !== "--profile");
if (unknown.length) {
	console.log("Usage: browser-start.js [--profile] [--session NAME]");
	console.log("\nOptions:");
	console.log("  --profile       Copy your default Chrome/Chromium profile (cookies, logins)");
	console.log("  --session NAME  Name this browser session (default: \"default\")");
	process.exit(1);
}

// Locate the user's real browser profile directory, for --profile.
function findUserProfile() {
	const home = homedir();
	let candidates;
	if (platform() === "darwin") {
		candidates = [
			`${home}/Library/Application Support/Google/Chrome`,
			`${home}/Library/Application Support/Chromium`,
		];
	} else if (platform() === "win32") {
		const local = process.env.LOCALAPPDATA || "";
		candidates = [`${local}\\Google\\Chrome\\User Data`, `${local}\\Chromium\\User Data`];
	} else {
		candidates = [`${home}/.config/google-chrome`, `${home}/.config/chromium`];
	}
	return candidates.find((c) => existsSync(c)) || null;
}

const EXCLUDE_NAMES = new Set([
	"SingletonLock",
	"SingletonSocket",
	"SingletonCookie",
	"Current Session",
	"Current Tabs",
	"Last Session",
	"Last Tabs",
]);
function profileFilter(src) {
	if (EXCLUDE_NAMES.has(basename(src))) return false;
	if (src.split(/[\\/]/).includes("Sessions")) return false;
	return true;
}

// If this session is already registered and alive, nothing to do.
const reg = readRegistry();
if (reg[session] && pidAlive(reg[session].pid)) {
	try {
		const b = await puppeteer.connect({
			browserURL: `http://localhost:${reg[session].port}`,
			defaultViewport: null,
		});
		await b.disconnect();
		console.log(`✓ Session "${session}" already running on :${reg[session].port}`);
		process.exit(0);
	} catch {
		// Registered pid alive but not reachable — fall through and relaunch.
	}
}

const binary = puppeteer.executablePath();
if (!existsSync(binary)) {
	console.error("✗ Bundled Chromium not found");
	console.error("  Run: npm install");
	process.exit(1);
}

const profile = profileDir(session);

if (useProfile) {
	const userProfile = findUserProfile();
	if (!userProfile) {
		console.error("✗ No Chrome/Chromium profile found to copy");
		process.exit(1);
	}
	console.log("Syncing profile...");
	rmSync(profile, { recursive: true, force: true });
	mkdirSync(profile, { recursive: true });
	cpSync(userProfile, profile, { recursive: true, filter: profileFilter });
} else {
	mkdirSync(profile, { recursive: true });
	for (const f of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
		try {
			rmSync(join(profile, f), { force: true });
		} catch {}
	}
}

const port = await findFreePort(9222);

const child = spawn(
	binary,
	[
		`--remote-debugging-port=${port}`,
		`--user-data-dir=${profile}`,
		"--no-first-run",
		"--no-default-browser-check",
	],
	{ detached: true, stdio: "ignore" },
);
child.unref();

// Wait for the browser to accept connections.
let connected = false;
for (let i = 0; i < 30; i++) {
	try {
		const b = await puppeteer.connect({
			browserURL: `http://localhost:${port}`,
			defaultViewport: null,
		});
		await b.disconnect();
		connected = true;
		break;
	} catch {
		await new Promise((r) => setTimeout(r, 500));
	}
}
if (!connected) {
	console.error("✗ Failed to connect to browser");
	process.exit(1);
}

// Record the session. child.pid is the launcher; Chromium may fork, but
// the launcher process staying alive is a sufficient liveness signal and
// killing it terminates the browser.
mkdirSync(sessionDir(session), { recursive: true });
const reg2 = readRegistry();
reg2[session] = { port, pid: child.pid, userDataDir: profile, startedAt: Date.now() };
writeRegistry(reg2);

console.log(
	`✓ Session "${session}" started on :${port} (bundled Chromium)${useProfile ? " with your profile" : ""}`,
);
```

- [ ] **Step 2: Verify a default session starts and registers**

Run:
```bash
cd browser-tools && ./browser-start.js && cat ~/.cache/browser-tools/sessions.json
```
Expected: `✓ Session "default" started on :9222 ...` and the JSON shows a `default` entry with `port`, `pid`, `userDataDir`, `startedAt`.

- [ ] **Step 3: Verify a second named session gets a different port**

Run:
```bash
cd browser-tools && ./browser-start.js --session work && cat ~/.cache/browser-tools/sessions.json
```
Expected: `✓ Session "work" started on :9223 ...`; registry now has both `default` and `work`.

- [ ] **Step 4: Verify idempotent restart**

Run: `cd browser-tools && ./browser-start.js --session work`
Expected: `✓ Session "work" already running on :9223`.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-start.js
git commit -m "feat(browser-tools): per-session browser launch with port allocation"
```

---

## Task 3: `browser-sessions.js` — list and kill sessions

**Files:**
- Create: `browser-tools/browser-sessions.js`

- [ ] **Step 1: Create `browser-sessions.js`**

```js
#!/usr/bin/env node

import { readRegistry, writeRegistry, pidAlive } from "./lib.js";

const cmd = process.argv[2] || "list";

if (cmd === "list") {
	const reg = readRegistry();
	const names = Object.keys(reg);
	if (names.length === 0) {
		console.log("No sessions registered. Run: browser-start.js");
		process.exit(0);
	}
	for (const name of names) {
		const e = reg[name];
		const alive = pidAlive(e.pid);
		console.log(
			`${alive ? "✓" : "✗"} ${name}  :${e.port}  pid ${e.pid}  ${alive ? "running" : "dead"}`,
		);
	}
} else if (cmd === "kill") {
	const target = process.argv[3];
	const all = target === "--all";
	if (!target) {
		console.error("Usage: browser-sessions.js kill <name|--all>");
		process.exit(1);
	}
	const reg = readRegistry();
	const names = all ? Object.keys(reg) : [target];
	let killed = 0;
	for (const name of names) {
		const e = reg[name];
		if (!e) {
			if (!all) console.error(`✗ No session named "${name}"`);
			continue;
		}
		if (pidAlive(e.pid)) {
			try {
				process.kill(e.pid);
				killed++;
			} catch {}
		}
		delete reg[name];
	}
	writeRegistry(reg);
	console.log(`✓ Killed ${killed} session(s)`);
} else {
	console.log("Usage: browser-sessions.js <list|kill <name|--all>>");
	process.exit(cmd ? 1 : 0);
}
```

- [ ] **Step 2: Make it executable**

Run: `cd browser-tools && chmod +x browser-sessions.js`

- [ ] **Step 3: Verify listing**

Run: `cd browser-tools && ./browser-sessions.js list`
Expected: lines for `default` and `work`, both `✓ ... running` (from Task 2).

- [ ] **Step 4: Verify kill**

Run:
```bash
cd browser-tools && ./browser-sessions.js kill work && ./browser-sessions.js list
```
Expected: `✓ Killed 1 session(s)`; the follow-up list shows only `default`.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-sessions.js
git commit -m "feat(browser-tools): browser-sessions.js to list and kill sessions"
```

---

## Task 4: Thread `--session` through navigation/inspection scripts

Updates `browser-nav.js`, `browser-eval.js`, `browser-screenshot.js`, `browser-content.js`, `browser-cookies.js` to resolve a session and use `getPage`. The pattern for each: import `extractSession`/`getPage`, derive `{ session, rest }`, read positional args from `rest`, call `connect(session)`, and replace `(await b.pages()).at(-1)` with `await getPage(b)`.

**Files:**
- Modify: `browser-tools/browser-nav.js`, `browser-eval.js`, `browser-screenshot.js`, `browser-content.js`, `browser-cookies.js`

- [ ] **Step 1: Update `browser-nav.js`**

In `browser-nav.js`, the current head reads the URL from `process.argv[2]` and the `--new` flag from `process.argv`. Change the argument handling and connect call. Replace the import line and the argument/connect block so the top of the file becomes:

```js
#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const url = rest[0];
const newTab = rest.includes("--new");

if (!url) {
	console.log("Usage: browser-nav.js <url> [--new] [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
```

Then, where the script currently picks the page, use `await getPage(b)` for the reuse-current-tab path (the `--new` path already calls `b.newPage()`). After a `newPage()`, add `await page.bringToFront();` so the new tab becomes the active one that `getPage` will return.

- [ ] **Step 2: Verify `browser-nav.js`**

Run:
```bash
cd browser-tools && ./browser-nav.js https://example.com && ./browser-eval.js 2>/dev/null; echo ok
```
Then verify the connect path explicitly in the next step's tools. For now run:
`cd browser-tools && ./browser-nav.js https://example.com`
Expected: `✓ Navigated to: https://example.com`.

- [ ] **Step 3: Update `browser-eval.js`**

Replace its import + argument + connect head with:

```js
#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const code = rest[0];

if (!code) {
	console.log("Usage: browser-eval.js <javascript> [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
```

Keep the rest of the script (the `p.evaluate` call and output) unchanged, but ensure it references `p` from `getPage`.

- [ ] **Step 4: Update `browser-screenshot.js`, `browser-content.js`, `browser-cookies.js`**

For each of these three scripts apply the same transformation:
1. Add `extractSession`, `getPage` to the `./lib.js` import.
2. Add `const { session, rest } = extractSession(process.argv.slice(2));` near the top.
3. Read any positional arguments from `rest` instead of `process.argv`.
4. Change `connect()` to `connect(session)`.
5. Replace `(await b.pages()).at(-1)` with `await getPage(b)`.
6. Add ` [--session NAME]` to each script's printed usage string.

`browser-content.js` takes a positional argument (URL) — read it from `rest[0]`. `browser-screenshot.js` and `browser-cookies.js` take no positional args.

- [ ] **Step 5: Verify the three scripts against the default session**

Run:
```bash
cd browser-tools
./browser-nav.js https://example.com
./browser-eval.js 'document.title'
./browser-screenshot.js
./browser-cookies.js
./browser-content.js https://example.com | head -3
```
Expected: `Example Domain` from eval; a `/tmp/screenshot-*.png` path; cookies output (possibly empty); markdown content from `browser-content.js`. No `✗` errors.

- [ ] **Step 6: Verify session isolation**

Run:
```bash
cd browser-tools
./browser-start.js --session t1
./browser-nav.js https://example.com --session t1
./browser-eval.js 'location.host' --session t1
./browser-sessions.js kill t1
```
Expected: `example.com` printed for the `t1` session.

- [ ] **Step 7: Commit**

```bash
git add browser-tools/browser-nav.js browser-tools/browser-eval.js browser-tools/browser-screenshot.js browser-tools/browser-content.js browser-tools/browser-cookies.js
git commit -m "feat(browser-tools): --session support for navigation and inspection tools"
```

---

## Task 5: Per-session monitor

`browser-monitor.js` becomes session-aware: the daemon connects to a named session and writes logs to that session's directory; `browser-console.js` and `browser-network.js` read the session's logs.

**Files:**
- Modify: `browser-tools/browser-monitor.js`, `browser-console.js`, `browser-network.js`

- [ ] **Step 1: Update `browser-monitor.js` imports and daemon**

Change the `./lib.js` import to:

```js
import {
	extractSession, sessionDir, monitorJson, monitorErr, consoleLog, networkLog,
	HEARTBEAT_MS, tryConnect, connect, resolvePort, readMonitor, isMonitorAlive,
} from "./lib.js";
```

The daemon currently runs as `browser-monitor.js __daemon`. Make it `browser-monitor.js __daemon <session>`. In `runDaemon()`, read the session from `process.argv[3]`, and replace every reference to the old global constants (`CACHE_DIR`, `MONITOR_JSON`, `CONSOLE_LOG`, `NETWORK_LOG`) with per-session paths:

```js
async function runDaemon() {
	const session = process.argv[3];
	mkdirSync(sessionDir(session), { recursive: true });
	const browser = await connect(session);
	const MON = monitorJson(session);
	const CONSOLE = consoleLog(session);
	const NETWORK = networkLog(session);

	const identity = {
		pid: process.pid,
		startedAt: Date.now(),
		wsEndpoint: browser.wsEndpoint(),
		lastHeartbeat: Date.now(),
	};
	const persist = () => writeFileSync(MON, JSON.stringify(identity));
	persist();
	const hb = setInterval(() => {
		identity.lastHeartbeat = Date.now();
		persist();
	}, HEARTBEAT_MS);

	const logConsole = (e) => appendFileSync(CONSOLE, JSON.stringify(e) + "\n");
	const logNetwork = (e) => appendFileSync(NETWORK, JSON.stringify(e) + "\n");
	// ... attach(page) body unchanged ...
	browser.on("disconnected", () => {
		clearInterval(hb);
		try { rmSync(MON, { force: true }); } catch {}
		process.exit(0);
	});
}
```

Keep the `attach` function body exactly as it is today (it closes over `logConsole`/`logNetwork`).

- [ ] **Step 2: Update `browser-monitor.js` start/stop/status**

These functions currently take no session. Give each a `session` parameter and use per-session paths and the new `isMonitorAlive(session)` / `readMonitor(session)` signatures. The start function's pre-check and daemon spawn change as follows:

```js
async function startDaemon(session) {
	mkdirSync(sessionDir(session), { recursive: true });

	if (isMonitorAlive(session)) {
		console.log(`✓ Monitor already running for "${session}" (pid ${readMonitor(session).pid})`);
		process.exit(0);
	}

	const port = resolvePort(session); // exits(1) if session not running
	const pre = await tryConnect(port);
	if (!pre) {
		console.error(`✗ Session "${session}" browser is not reachable`);
		console.error("  Run: browser-start.js");
		process.exit(1);
	}
	await pre.disconnect();

	const MON = monitorJson(session);
	if (existsSync(MON)) rmSync(MON, { force: true });

	let fd;
	try {
		fd = openSync(MON, "wx");
	} catch {
		console.error("✗ Another monitor start is in progress");
		process.exit(1);
	}
	writeSync(fd, JSON.stringify({ pid: 0, startedAt: Date.now(), lastHeartbeat: 0 }));
	closeSync(fd);

	writeFileSync(consoleLog(session), "");
	writeFileSync(networkLog(session), "");

	const errFd = openSync(monitorErr(session), "w");
	const child = spawn(process.execPath, [SELF, "__daemon", session], {
		detached: true,
		stdio: ["ignore", "ignore", errFd],
	});
	child.unref();
	closeSync(errFd);

	const deadline = Date.now() + 3000;
	const tick = () => {
		if (isMonitorAlive(session)) {
			console.log(`✓ Monitor started for "${session}" (pid ${readMonitor(session).pid})`);
			process.exit(0);
		}
		if (Date.now() > deadline) {
			console.error("✗ Monitor failed to start");
			try {
				const tail = readFileSync(monitorErr(session), "utf8").trim().split("\n").slice(-10);
				if (tail.length && tail[0]) console.error("  monitor.err:\n  " + tail.join("\n  "));
			} catch {}
			rmSync(MON, { force: true });
			process.exit(1);
		}
		setTimeout(tick, 200);
	};
	tick();
}

function stopDaemon(session) {
	const info = readMonitor(session);
	if (isMonitorAlive(session, info)) {
		try { process.kill(info.pid); } catch {}
		rmSync(monitorJson(session), { force: true });
		console.log(`✓ Monitor stopped for "${session}" (pid ${info.pid})`);
	} else {
		if (info) rmSync(monitorJson(session), { force: true });
		console.log(`Monitor not running for "${session}"`);
	}
}

function statusDaemon(session) {
	const info = readMonitor(session);
	if (isMonitorAlive(session, info)) {
		const c = countAndSize(consoleLog(session));
		const n = countAndSize(networkLog(session));
		console.log(`✓ Monitor running for "${session}" (pid ${info.pid})`);
		console.log(`  started: ${new Date(info.startedAt).toISOString()}`);
		console.log(`  console.jsonl: ${c.lines} events (${(c.bytes / 1024).toFixed(1)} KB)`);
		console.log(`  network.jsonl: ${n.lines} events (${(n.bytes / 1024).toFixed(1)} KB)`);
	} else {
		console.log(`✗ Monitor not running for "${session}"`);
		if (info) console.log("  (stale monitor.json present — a previous daemon ended)");
	}
}
```

Keep `countAndSize` unchanged.

- [ ] **Step 3: Update `browser-monitor.js` dispatch**

Replace the dispatch block at the bottom with one that extracts the session:

```js
const { session, rest } = extractSession(process.argv.slice(2));
const cmd = process.argv[2] === "__daemon" ? "__daemon" : rest[0];

if (cmd === "__daemon") {
	await runDaemon();
} else if (cmd === "start") {
	await startDaemon(session);
} else if (cmd === "stop") {
	stopDaemon(session);
} else if (cmd === "status") {
	statusDaemon(session);
} else {
	console.log("Usage: browser-monitor.js <start|stop|status> [--session NAME]");
	console.log("\nStart a background daemon that records console and network");
	console.log("events from a session's browser to per-session log files.");
	process.exit(cmd ? 1 : 0);
}
```

(`__daemon` is detected directly from `process.argv[2]` because it is an internal entrypoint that takes the session as a bare positional, not a `--session` flag.)

- [ ] **Step 4: Update `browser-console.js` and `browser-network.js`**

Each reads a global log constant today. Change each to resolve a session and read that session's log. For `browser-console.js`, the head becomes:

```js
#!/usr/bin/env node

import { extractSession, consoleLog, isMonitorAlive } from "./lib.js";
import { existsSync, readFileSync } from "node:fs";

const { session, rest } = extractSession(process.argv.slice(2));
const LOG = consoleLog(session);

if (!isMonitorAlive(session) && !existsSync(LOG)) {
	console.error(`✗ No monitor data for session "${session}"`);
	console.error("  Run: browser-monitor.js start");
	process.exit(1);
}
```

Then keep the existing flag parsing (`--errors`, `--limit`) but source flags from `rest`, and read entries from `LOG`. Apply the equivalent change to `browser-network.js` using `networkLog(session)` and its `--failed`/`--limit` flags. Add ` [--session NAME]` to both usage strings.

- [ ] **Step 5: Verify the monitor end to end**

Run:
```bash
cd browser-tools
./browser-monitor.js start
./browser-nav.js https://example.com
./browser-network.js --limit 5
./browser-monitor.js status
./browser-monitor.js stop
```
Expected: `✓ Monitor started for "default"`; at least one network row from `browser-network.js`; `✓ Monitor running` from status; `✓ Monitor stopped` from stop.

- [ ] **Step 6: Commit**

```bash
git add browser-tools/browser-monitor.js browser-tools/browser-console.js browser-tools/browser-network.js
git commit -m "feat(browser-tools): per-session monitor daemon and logs"
```

---

## Task 6: `browser-snapshot.js` — accessibility tree with refs

**Files:**
- Create: `browser-tools/browser-snapshot.js`
- Create: `browser-tools/test/fixtures/form.html`

- [ ] **Step 1: Create the test fixture**

Create `browser-tools/test/fixtures/form.html`:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Form Fixture</title></head>
<body>
  <h1>Account</h1>
  <form id="f">
    <label for="email">Email</label>
    <input type="email" id="email" name="email">
    <label for="plan">Plan</label>
    <select id="plan">
      <option value="free">Free</option>
      <option value="pro">Pro</option>
    </select>
    <button type="button" id="save">Save</button>
    <button type="button" id="locked" disabled>Locked</button>
  </form>
  <a href="https://example.com" id="link">Help</a>
</body>
</html>
```

- [ ] **Step 2: Create `browser-snapshot.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const includeAll = rest.includes("--all");

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

const tree = await p.evaluate((includeAll) => {
	let counter = 0;
	const INTERACTIVE = new Set(["A", "BUTTON", "INPUT", "SELECT", "TEXTAREA"]);
	const LANDMARK = new Set([
		"FORM", "NAV", "MAIN", "HEADER", "FOOTER", "ASIDE", "SECTION",
		"H1", "H2", "H3", "H4", "H5", "H6", "UL", "OL",
	]);

	function visible(el) {
		const s = getComputedStyle(el);
		if (s.display === "none" || s.visibility === "hidden" || s.opacity === "0") return false;
		const r = el.getBoundingClientRect();
		return r.width > 0 && r.height > 0;
	}
	function role(el) {
		const explicit = el.getAttribute("role");
		if (explicit) return explicit;
		const tag = el.tagName;
		if (tag === "A" && el.hasAttribute("href")) return "link";
		if (tag === "BUTTON") return "button";
		if (tag === "INPUT") {
			const t = (el.getAttribute("type") || "text").toLowerCase();
			if (t === "checkbox") return "checkbox";
			if (t === "radio") return "radio";
			if (t === "submit" || t === "button") return "button";
			return "textbox";
		}
		if (tag === "SELECT") return "combobox";
		if (tag === "TEXTAREA") return "textbox";
		if (/^H[1-6]$/.test(tag)) return "heading";
		return tag.toLowerCase();
	}
	function name(el) {
		const aria = el.getAttribute("aria-label");
		if (aria) return aria.trim();
		if (el.id) {
			const lbl = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
			if (lbl) return lbl.textContent.trim();
		}
		const closestLabel = el.closest("label");
		if (closestLabel) return closestLabel.textContent.trim().replace(/\s+/g, " ");
		if (el.tagName === "INPUT" && el.getAttribute("placeholder")) {
			return el.getAttribute("placeholder").trim();
		}
		if (el.tagName === "IMG") return (el.getAttribute("alt") || "").trim();
		const text = el.textContent.trim().replace(/\s+/g, " ");
		return text.length > 80 ? text.slice(0, 80) + "…" : text;
	}
	function interesting(el) {
		if (INTERACTIVE.has(el.tagName)) return true;
		if (el.hasAttribute("role")) return true;
		if (el.hasAttribute("tabindex")) return true;
		if (el.isContentEditable) return true;
		if (includeAll && LANDMARK.has(el.tagName)) return true;
		return false;
	}

	const lines = [];
	function walk(el, depth) {
		let nextDepth = depth;
		if (interesting(el) && visible(el)) {
			const ref = "e" + ++counter;
			el.setAttribute("data-ct-ref", ref);
			const r = role(el);
			const n = name(el);
			let state = "";
			if (el.disabled) state += " disabled";
			if (el.checked) state += " checked";
			lines.push("  ".repeat(depth) + `${r}${n ? ` "${n}"` : ""}${state} [ref=${ref}]`);
			nextDepth = depth + 1;
		}
		for (const child of el.children) walk(child, nextDepth);
	}

	// Clear refs from any previous snapshot so ids do not accumulate.
	document.querySelectorAll("[data-ct-ref]").forEach((e) => e.removeAttribute("data-ct-ref"));
	walk(document.body, 0);
	return lines.join("\n");
}, includeAll);

console.log(`URL: ${p.url()}`);
console.log(tree || "(no interactive elements found)");

await b.disconnect();
```

- [ ] **Step 3: Make it executable**

Run: `cd browser-tools && chmod +x browser-snapshot.js`

- [ ] **Step 4: Verify against the fixture**

Run:
```bash
cd browser-tools
./browser-start.js
./browser-nav.js "file://$(pwd)/test/fixtures/form.html"
./browser-snapshot.js
```
Expected output includes lines like:
```
textbox "Email" [ref=e1]
combobox "Plan" [ref=e2]
button "Save" [ref=e3]
button "Locked" disabled [ref=e4]
link "Help" [ref=e5]
```
(Ref numbers must be present and sequential; the disabled button must show ` disabled`.)

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-snapshot.js browser-tools/test/fixtures/form.html
git commit -m "feat(browser-tools): browser-snapshot.js accessibility tree with @ref ids"
```

---

## Task 7: Refs and actionability waits in `browser-click.js` and `browser-type.js`

**Files:**
- Modify: `browser-tools/browser-click.js`, `browser-type.js`

- [ ] **Step 1: Rewrite `browser-click.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];

if (!target) {
	console.log("Usage: browser-click.js <selector|@ref> [--session NAME]");
	console.log("\nExamples:");
	console.log('  browser-click.js "#submit"');
	console.log("  browser-click.js @e5        (ref from browser-snapshot.js)");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	const handle = await waitActionable(p, target);
	await handle.click();
} catch (err) {
	console.error(`✗ Click failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Clicked: ${target}`);
await b.disconnect();
```

- [ ] **Step 2: Rewrite `browser-type.js`**

Preserve the existing `--clear` and `--enter` behavior; add ref + actionability support.

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const text = rest[1];
const clear = rest.includes("--clear");
const enter = rest.includes("--enter");

if (!target || text === undefined) {
	console.log("Usage: browser-type.js <selector|@ref> <text> [--clear] [--enter] [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	const handle = await waitActionable(p, target);
	await handle.click();
	if (clear) {
		await handle.evaluate((el) => {
			if ("value" in el) el.value = "";
		});
	}
	await handle.type(text);
	if (enter) await p.keyboard.press("Enter");
} catch (err) {
	console.error(`✗ Type failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Typed into ${target}`);
await b.disconnect();
```

- [ ] **Step 3: Verify ref-based interaction against the fixture**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/form.html"
./browser-snapshot.js
./browser-type.js @e1 "user@test.com"
./browser-eval.js 'document.getElementById("email").value'
./browser-click.js @e3
```
Expected: `user@test.com` echoed from eval; `✓ Typed into @e1`; `✓ Clicked: @e3`.

- [ ] **Step 4: Verify the disabled-element guard**

Run: `cd browser-tools && ./browser-click.js @e4`
Expected: `✗ Click failed: element is disabled: @e4` and a non-zero exit.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-click.js browser-tools/browser-type.js
git commit -m "feat(browser-tools): @ref targeting and actionability waits for click/type"
```

---

## Task 8: `browser-wait.js`

**Files:**
- Create: `browser-tools/browser-wait.js`

- [ ] **Step 1: Create `browser-wait.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const mode = rest[0];
const arg = rest[1];
const tIdx = rest.indexOf("--timeout");
const timeout = tIdx >= 0 ? Number(rest[tIdx + 1]) : 10000;

const USAGE =
	"Usage: browser-wait.js <visible|gone|text|text-gone|navigation|idle|delay> [arg] [--timeout MS] [--session NAME]";

if (!mode) {
	console.log(USAGE);
	process.exit(0);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	if (mode === "visible") {
		await p.waitForSelector(resolveTarget(arg), { visible: true, timeout });
		console.log(`✓ Visible: ${arg}`);
	} else if (mode === "gone") {
		await p.waitForSelector(resolveTarget(arg), { hidden: true, timeout });
		console.log(`✓ Gone: ${arg}`);
	} else if (mode === "text") {
		await p.waitForFunction((t) => document.body.innerText.includes(t), { timeout }, arg);
		console.log(`✓ Text appeared: "${arg}"`);
	} else if (mode === "text-gone") {
		await p.waitForFunction((t) => !document.body.innerText.includes(t), { timeout }, arg);
		console.log(`✓ Text gone: "${arg}"`);
	} else if (mode === "navigation") {
		await p.waitForNavigation({ waitUntil: "load", timeout });
		console.log(`✓ Navigated: ${p.url()}`);
	} else if (mode === "idle") {
		await p.waitForNetworkIdle({ timeout });
		console.log("✓ Network idle");
	} else if (mode === "delay") {
		await new Promise((r) => setTimeout(r, Number(arg)));
		console.log(`✓ Waited ${arg}ms`);
	} else {
		console.log(USAGE);
		await b.disconnect();
		process.exit(1);
	}
} catch (err) {
	console.error(`✗ Wait failed (${mode}): ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `cd browser-tools && chmod +x browser-wait.js`

- [ ] **Step 3: Verify the delay and text modes**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/form.html"
./browser-wait.js delay 200
./browser-wait.js text "Account"
./browser-wait.js visible "#save"
```
Expected: `✓ Waited 200ms`; `✓ Text appeared: "Account"`; `✓ Visible: #save`.

- [ ] **Step 4: Commit**

```bash
git add browser-tools/browser-wait.js
git commit -m "feat(browser-tools): browser-wait.js for explicit wait conditions"
```

---

## Task 9: `browser-hover.js`, `browser-key.js`, `browser-scroll.js`

Three small interaction tools grouped because each is a few lines.

**Files:**
- Create: `browser-tools/browser-hover.js`, `browser-key.js`, `browser-scroll.js`

- [ ] **Step 1: Create `browser-hover.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];

if (!target) {
	console.log("Usage: browser-hover.js <selector|@ref> [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	const handle = await waitActionable(p, target);
	await handle.hover();
} catch (err) {
	console.error(`✗ Hover failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Hovered: ${target}`);
await b.disconnect();
```

- [ ] **Step 2: Create `browser-key.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const combo = rest[0];

if (!combo) {
	console.log("Usage: browser-key.js <key|chord> [--session NAME]");
	console.log("\nExamples:");
	console.log("  browser-key.js Escape");
	console.log("  browser-key.js Tab");
	console.log('  browser-key.js "Control+A"');
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

const parts = combo.split("+");
const key = parts.pop();
try {
	for (const mod of parts) await p.keyboard.down(mod);
	await p.keyboard.press(key);
	for (const mod of parts.reverse()) await p.keyboard.up(mod);
} catch (err) {
	console.error(`✗ Key press failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Pressed: ${combo}`);
await b.disconnect();
```

- [ ] **Step 3: Create `browser-scroll.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const byIdx = rest.indexOf("--by");

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	if (byIdx >= 0) {
		// Scroll the window by a pixel amount.
		const pixels = Number(rest[byIdx + 1]);
		await p.evaluate((y) => window.scrollBy(0, y), pixels);
		console.log(`✓ Scrolled window by ${pixels}px`);
	} else if (rest[0]) {
		// Scroll an element into view.
		const selector = resolveTarget(rest[0]);
		const handle = await p.waitForSelector(selector, { timeout: 5000 });
		await handle.evaluate((el) => el.scrollIntoView({ block: "center" }));
		console.log(`✓ Scrolled into view: ${rest[0]}`);
	} else {
		console.log("Usage: browser-scroll.js <selector|@ref> | --by <pixels> [--session NAME]");
		await b.disconnect();
		process.exit(0);
	}
} catch (err) {
	console.error(`✗ Scroll failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
```

- [ ] **Step 4: Make them executable**

Run: `cd browser-tools && chmod +x browser-hover.js browser-key.js browser-scroll.js`

- [ ] **Step 5: Verify**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/form.html"
./browser-hover.js "#save"
./browser-scroll.js "#link"
./browser-scroll.js --by 100
./browser-type.js "#email" ""
./browser-key.js Tab
```
Expected: `✓ Hovered: #save`; `✓ Scrolled into view: #link`; `✓ Scrolled window by 100px`; `✓ Pressed: Tab`.

- [ ] **Step 6: Commit**

```bash
git add browser-tools/browser-hover.js browser-tools/browser-key.js browser-tools/browser-scroll.js
git commit -m "feat(browser-tools): hover, key, and scroll tools"
```

---

## Task 10: `browser-select.js`

Choose `<select>` option(s) by value or visible label.

**Files:**
- Create: `browser-tools/browser-select.js`

- [ ] **Step 1: Create `browser-select.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const choices = rest.slice(1);

if (!target || choices.length === 0) {
	console.log("Usage: browser-select.js <selector|@ref> <value-or-label...> [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	const handle = await waitActionable(p, target);
	// Map each requested choice to an option value: accept either the
	// option's `value` or its visible label.
	const values = await handle.evaluate((el, wanted) => {
		const opts = Array.from(el.options || []);
		return wanted.map((w) => {
			const byValue = opts.find((o) => o.value === w);
			if (byValue) return byValue.value;
			const byLabel = opts.find((o) => o.textContent.trim() === w);
			if (byLabel) return byLabel.value;
			return null;
		});
	}, choices);
	const missing = choices.filter((_, i) => values[i] === null);
	if (missing.length) {
		throw new Error(`no option matching: ${missing.join(", ")}`);
	}
	await handle.select(...values);
} catch (err) {
	console.error(`✗ Select failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Selected ${choices.join(", ")} in ${target}`);
await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `cd browser-tools && chmod +x browser-select.js`

- [ ] **Step 3: Verify against the fixture**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/form.html"
./browser-select.js "#plan" "Pro"
./browser-eval.js 'document.getElementById("plan").value'
```
Expected: `✓ Selected Pro in #plan`; eval prints `pro`.

- [ ] **Step 4: Commit**

```bash
git add browser-tools/browser-select.js
git commit -m "feat(browser-tools): browser-select.js for dropdown options"
```

---

## Task 11: `browser-drag.js`

**Files:**
- Create: `browser-tools/browser-drag.js`
- Create: `browser-tools/test/fixtures/drag.html`

- [ ] **Step 1: Create the drag fixture**

Create `browser-tools/test/fixtures/drag.html`:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Drag Fixture</title>
<style>#src,#dst{width:120px;height:120px;display:inline-block;margin:20px}
#src{background:#cdf}#dst{background:#dfc}</style></head>
<body>
  <div id="src" draggable="true">SOURCE</div>
  <div id="dst">DROP HERE</div>
  <div id="status">idle</div>
  <script>
    const dst = document.getElementById('dst');
    dst.addEventListener('mouseup', () => {
      document.getElementById('status').textContent = 'dropped';
    });
  </script>
</body>
</html>
```

- [ ] **Step 2: Create `browser-drag.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const from = rest[0];
const to = rest[1];

if (!from || !to) {
	console.log("Usage: browser-drag.js <from selector|@ref> <to selector|@ref> [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	const src = await waitActionable(p, from);
	const dst = await waitActionable(p, to);
	const sb = await src.boundingBox();
	const db = await dst.boundingBox();
	if (!sb || !db) throw new Error("could not measure element positions");
	await p.mouse.move(sb.x + sb.width / 2, sb.y + sb.height / 2);
	await p.mouse.down();
	// Move in steps so drag-tracking handlers fire.
	await p.mouse.move(db.x + db.width / 2, db.y + db.height / 2, { steps: 10 });
	await p.mouse.up();
} catch (err) {
	console.error(`✗ Drag failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Dragged ${from} → ${to}`);
await b.disconnect();
```

- [ ] **Step 3: Make it executable**

Run: `cd browser-tools && chmod +x browser-drag.js`

- [ ] **Step 4: Verify against the fixture**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/drag.html"
./browser-drag.js "#src" "#dst"
./browser-eval.js 'document.getElementById("status").textContent'
```
Expected: `✓ Dragged #src → #dst`; eval prints `dropped`.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-drag.js browser-tools/test/fixtures/drag.html
git commit -m "feat(browser-tools): browser-drag.js for drag-and-drop"
```

---

## Task 12: `browser-dialog.js`

Pre-arms a handler for the next `alert`/`confirm`/`prompt`. Because the stateless scripts disconnect after each call, this tool stays connected and blocks until a dialog appears or it times out — the agent runs it in the background (`&`) before the action that triggers the dialog.

**Files:**
- Create: `browser-tools/browser-dialog.js`
- Create: `browser-tools/test/fixtures/dialog.html`

- [ ] **Step 1: Create the dialog fixture**

Create `browser-tools/test/fixtures/dialog.html`:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Dialog Fixture</title></head>
<body>
  <button type="button" id="go" onclick="document.getElementById('out').textContent = confirm('Proceed?') ? 'accepted' : 'dismissed'">Go</button>
  <div id="out">idle</div>
</body>
</html>
```

- [ ] **Step 2: Create `browser-dialog.js`**

```js
#!/usr/bin/env node

import { connect, extractSession } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const action = rest[0];
const textIdx = rest.indexOf("--text");
const promptText = textIdx >= 0 ? rest[textIdx + 1] : "";
const tIdx = rest.indexOf("--timeout");
const timeout = tIdx >= 0 ? Number(rest[tIdx + 1]) : 30000;

if (action !== "accept" && action !== "dismiss") {
	console.log("Usage: browser-dialog.js <accept|dismiss> [--text TEXT] [--timeout MS] [--session NAME]");
	console.log("\nArms a handler for the NEXT dialog. Run in the background before the");
	console.log("action that triggers the dialog, e.g.:");
	console.log("  browser-dialog.js accept & ; browser-click.js @e3");
	process.exit(action ? 1 : 0);
}

const b = await connect(session);
let handled = false;

function arm(page) {
	page.on("dialog", async (dialog) => {
		if (handled) return;
		handled = true;
		const msg = dialog.message();
		const type = dialog.type();
		try {
			if (action === "accept") await dialog.accept(promptText);
			else await dialog.dismiss();
			console.log(`✓ ${action === "accept" ? "Accepted" : "Dismissed"} ${type}: "${msg}"`);
		} catch (err) {
			console.error(`✗ Dialog handling failed: ${err.message}`);
		}
		await b.disconnect();
		process.exit(0);
	});
}

for (const page of await b.pages()) arm(page);
b.on("targetcreated", async (t) => {
	if (t.type() !== "page") return;
	const page = await t.page();
	if (page) arm(page);
});

setTimeout(async () => {
	if (!handled) {
		console.error(`✗ No dialog appeared within ${timeout}ms`);
		await b.disconnect();
		process.exit(1);
	}
}, timeout);
```

- [ ] **Step 3: Make it executable**

Run: `cd browser-tools && chmod +x browser-dialog.js`

- [ ] **Step 4: Verify the background-arm pattern**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/dialog.html"
./browser-snapshot.js
( ./browser-dialog.js accept & ) ; sleep 1 ; ./browser-click.js @e1
sleep 1
./browser-eval.js 'document.getElementById("out").textContent'
```
Expected: a `✓ Accepted confirm: "Proceed?"` line from the backgrounded dialog tool, and eval prints `accepted`.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-dialog.js browser-tools/test/fixtures/dialog.html
git commit -m "feat(browser-tools): browser-dialog.js to handle alert/confirm/prompt"
```

---

## Task 13: `browser-upload.js`

Sets files on a file input. File inputs are frequently hidden, so this tool waits only for *presence* (not visibility) — it deliberately does not use `waitActionable`.

**Files:**
- Create: `browser-tools/browser-upload.js`
- Create: `browser-tools/test/fixtures/upload.html`

- [ ] **Step 1: Create the upload fixture**

Create `browser-tools/test/fixtures/upload.html`:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Upload Fixture</title></head>
<body>
  <input type="file" id="file">
  <div id="out">none</div>
  <script>
    document.getElementById('file').addEventListener('change', (e) => {
      document.getElementById('out').textContent = e.target.files.length + ' file(s)';
    });
  </script>
</body>
</html>
```

- [ ] **Step 2: Create `browser-upload.js`**

```js
#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const files = rest.slice(1);

if (!target || files.length === 0) {
	console.log("Usage: browser-upload.js <selector|@ref> <file...> [--session NAME]");
	process.exit(1);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	// File inputs are often visually hidden — wait for presence only.
	const handle = await p.waitForSelector(resolveTarget(target), { timeout: 5000 });
	await handle.uploadFile(...files);
} catch (err) {
	console.error(`✗ Upload failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Set ${files.length} file(s) on ${target}`);
await b.disconnect();
```

- [ ] **Step 3: Make it executable**

Run: `cd browser-tools && chmod +x browser-upload.js`

- [ ] **Step 4: Verify against the fixture**

Run:
```bash
cd browser-tools
./browser-nav.js "file://$(pwd)/test/fixtures/upload.html"
./browser-upload.js "#file" "$(pwd)/test/fixtures/upload.html"
./browser-eval.js 'document.getElementById("out").textContent'
```
Expected: `✓ Set 1 file(s) on #file`; eval prints `1 file(s)`.

- [ ] **Step 5: Commit**

```bash
git add browser-tools/browser-upload.js browser-tools/test/fixtures/upload.html
git commit -m "feat(browser-tools): browser-upload.js for file inputs"
```

---

## Task 14: `browser-tabs.js`

**Files:**
- Create: `browser-tools/browser-tabs.js`

- [ ] **Step 1: Create `browser-tabs.js`**

```js
#!/usr/bin/env node

import { connect, extractSession } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const cmd = rest[0] || "list";

const b = await connect(session);
const pages = await b.pages();

try {
	if (cmd === "list") {
		for (let i = 0; i < pages.length; i++) {
			const title = await pages[i].title().catch(() => "");
			const visible = await pages[i]
				.evaluate(() => document.visibilityState === "visible")
				.catch(() => false);
			console.log(`[${i}]${visible ? " *" : "  "} ${pages[i].url()}  ${title}`);
		}
	} else if (cmd === "new") {
		const page = await b.newPage();
		if (rest[1]) await page.goto(rest[1], { waitUntil: "load" });
		await page.bringToFront();
		console.log(`✓ Opened tab [${(await b.pages()).length - 1}]${rest[1] ? ` → ${rest[1]}` : ""}`);
	} else if (cmd === "select") {
		const i = Number(rest[1]);
		if (!pages[i]) throw new Error(`no tab at index ${i}`);
		await pages[i].bringToFront();
		console.log(`✓ Selected tab [${i}] ${pages[i].url()}`);
	} else if (cmd === "close") {
		const i = Number(rest[1]);
		if (!pages[i]) throw new Error(`no tab at index ${i}`);
		const url = pages[i].url();
		await pages[i].close();
		console.log(`✓ Closed tab [${i}] ${url}`);
	} else {
		console.log("Usage: browser-tabs.js <list|new [url]|select <index>|close <index>> [--session NAME]");
		await b.disconnect();
		process.exit(1);
	}
} catch (err) {
	console.error(`✗ Tabs command failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `cd browser-tools && chmod +x browser-tabs.js`

- [ ] **Step 3: Verify tab lifecycle and that `select` retargets**

Run:
```bash
cd browser-tools
./browser-nav.js https://example.com
./browser-tabs.js new https://example.org
./browser-tabs.js list
./browser-eval.js 'location.host'
./browser-tabs.js select 0
./browser-eval.js 'location.host'
./browser-tabs.js close 1
```
Expected: `list` shows two tabs with `*` on the second; the first `eval` prints `example.org` (new tab is active); after `select 0`, `eval` prints `example.com`; `close 1` succeeds.

- [ ] **Step 4: Commit**

```bash
git add browser-tools/browser-tabs.js
git commit -m "feat(browser-tools): browser-tabs.js for multi-tab management"
```

---

## Task 15: `browser-trace.js` — session support + subresource label fix

Adds `--session` and renames the confusing `Requests:` line (a zero-subresource page currently reads as `Requests: 0`).

**Files:**
- Modify: `browser-tools/browser-trace.js`

- [ ] **Step 1: Add session support**

At the top of `browser-trace.js`, replace the import and the `const url = process.argv[2];` line with:

```js
import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const url = rest[0];
```

Change `const b = await connect();` to `const b = await connect(session);` and replace `const p = (await b.pages()).at(-1);` with `const p = await getPage(b);`.

- [ ] **Step 2: Fix the subresource-count label**

In the output block, the line currently reads:

```js
console.log(`Requests:                 ${m.count} (${m.totalKB} KB total)`);
```

Replace it with:

```js
console.log(`Subresources:             ${m.count} (${m.totalKB} KB total)`);
console.log("  (the main document is not counted — it is a navigation, not a resource)");
```

- [ ] **Step 3: Verify**

Run:
```bash
cd browser-tools
./browser-trace.js https://example.com
```
Expected: a metrics block whose request line now reads `Subresources: 0 (0 KB total)` followed by the clarifying note; TTFB/DOMContentLoaded/Load show numbers.

- [ ] **Step 4: Commit**

```bash
git add browser-tools/browser-trace.js
git commit -m "feat(browser-tools): --session for browser-trace.js and clearer subresource label"
```

---

## Task 16: End-to-end smoke test

A single script that exercises every tool against local fixtures, with no network dependency. This is the fast regression check.

**Files:**
- Create: `browser-tools/test/smoke.sh`

- [ ] **Step 1: Create `test/smoke.sh`**

```bash
#!/usr/bin/env bash
# End-to-end smoke test for browser-tools. Exercises every tool against
# local fixtures in an isolated session. Exits non-zero on the first
# failure. Run from the browser-tools directory: ./test/smoke.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SESSION="smoke-$$"
FIX="file://$(pwd)/test/fixtures"

cleanup() { ./browser-sessions.js kill "$SESSION" >/dev/null 2>&1 || true; }
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }
expect() { # expect <description> <haystack> <needle>
	case "$2" in
		*"$3"*) pass "$1" ;;
		*) echo "  expected to contain: $3"; echo "  got: $2"; fail "$1" ;;
	esac
}

export BROWSER_SESSION="$SESSION"

./browser-start.js >/dev/null
./browser-monitor.js start >/dev/null

# unit tests
node --test "test/*.test.js" >/dev/null && pass "lib unit tests" || fail "lib unit tests"

# snapshot + ref interaction
./browser-nav.js "$FIX/form.html" >/dev/null
SNAP=$(./browser-snapshot.js)
expect "snapshot lists the email textbox" "$SNAP" 'textbox "Email" [ref=e1]'
expect "snapshot marks the disabled button" "$SNAP" 'disabled [ref=e4]'

./browser-type.js @e1 "user@test.com" >/dev/null
VAL=$(./browser-eval.js 'document.getElementById("email").value')
expect "type via ref set the value" "$VAL" "user@test.com"

CLICK_DISABLED=$(./browser-click.js @e4 2>&1 || true)
expect "click on disabled element is rejected" "$CLICK_DISABLED" "disabled"

# select
./browser-select.js "#plan" "Pro" >/dev/null
PLAN=$(./browser-eval.js 'document.getElementById("plan").value')
expect "select chose the Pro option" "$PLAN" "pro"

# wait
W=$(./browser-wait.js text "Account")
expect "wait detected page text" "$W" "Text appeared"

# hover / key / scroll
expect "hover" "$(./browser-hover.js '#save')" "Hovered"
expect "scroll into view" "$(./browser-scroll.js '#link')" "Scrolled into view"
expect "key press" "$(./browser-key.js Tab)" "Pressed: Tab"

# drag
./browser-nav.js "$FIX/drag.html" >/dev/null
./browser-drag.js "#src" "#dst" >/dev/null
DRAG=$(./browser-eval.js 'document.getElementById("status").textContent')
expect "drag triggered drop" "$DRAG" "dropped"

# upload
./browser-nav.js "$FIX/upload.html" >/dev/null
./browser-upload.js "#file" "$(pwd)/test/fixtures/upload.html" >/dev/null
UP=$(./browser-eval.js 'document.getElementById("out").textContent')
expect "upload set a file" "$UP" "1 file(s)"

# dialog
./browser-nav.js "$FIX/dialog.html" >/dev/null
./browser-snapshot.js >/dev/null
( ./browser-dialog.js accept & ) ; sleep 1 ; ./browser-click.js @e1 >/dev/null
sleep 1
DLG=$(./browser-eval.js 'document.getElementById("out").textContent')
expect "dialog was accepted" "$DLG" "accepted"

# tabs
./browser-tabs.js new "$FIX/form.html" >/dev/null
TABS=$(./browser-tabs.js list)
expect "tabs list shows two tabs" "$TABS" "[1]"

# monitor read-back
expect "monitor status" "$(./browser-monitor.js status)" "Monitor running"

echo "ALL SMOKE TESTS PASSED"
```

- [ ] **Step 2: Make it executable**

Run: `cd browser-tools && chmod +x test/smoke.sh`

- [ ] **Step 3: Run the smoke test**

Run: `cd browser-tools && ./test/smoke.sh`
Expected: a series of `PASS:` lines and a final `ALL SMOKE TESTS PASSED`. Exit code 0.

- [ ] **Step 4: Commit**

```bash
git add browser-tools/test/smoke.sh
git commit -m "test(browser-tools): end-to-end smoke test for all tools"
```

---

## Task 17: Update `SKILL.md`

Document sessions, the snapshot/ref workflow, and every new tool.

**Files:**
- Modify: `browser-tools/SKILL.md`

- [ ] **Step 1: Update the frontmatter description**

Keep the `name`, broaden the `description` so triggering still fires and mentions the new breadth:

```
description: Interactive Chromium browser automation and debugging via Chrome DevTools Protocol — an MCP-free alternative to Puppeteer/Chrome MCP. Use when you need to interact with web pages, fill forms, test frontends, capture console and network activity, take an accessibility snapshot of a page, run multiple isolated browser sessions, or when user interaction with a visible browser is required.
```

- [ ] **Step 2: Add a "Sessions" section**

Insert after the "Setup" section:

````markdown
## Sessions

Every tool operates on a named **session** — one browser instance with its
own port, profile, and logs. This lets independent tasks run browsers in
parallel without colliding.

- Default session is `"default"` — omit `--session` and everything just works.
- Pass `--session NAME` to any tool, or export `BROWSER_SESSION=NAME` once so
  every later call in that environment is session-scoped with no flag.
- `{baseDir}/browser-sessions.js list` shows running sessions;
  `{baseDir}/browser-sessions.js kill <name|--all>` stops them.

```bash
{baseDir}/browser-start.js --session scrape
{baseDir}/browser-nav.js https://example.com --session scrape
```
````

- [ ] **Step 3: Add a "Snapshot and refs" section**

Insert before the "Click" section:

````markdown
## Accessibility Snapshot and Refs

```bash
{baseDir}/browser-snapshot.js          # interactive elements + refs
{baseDir}/browser-snapshot.js --all    # also include landmarks/headings
```

Prints a compact accessibility tree. Each element gets a stable `[ref=eN]`
id, e.g. `button "Sign Up" [ref=e5]`. Every interaction tool accepts that
ref as `@eN` in place of a CSS selector:

```bash
{baseDir}/browser-click.js @e5
{baseDir}/browser-type.js @e3 "hello"
```

This is the recommended loop: **snapshot → act on refs → re-snapshot**.
Prefer it over hand-written selectors — it is more robust and needs no
guessing about page structure. Refs go stale when the DOM changes; just run
`browser-snapshot.js` again to refresh them.
````

- [ ] **Step 4: Document the new interaction tools**

Add concise sections (matching the style of the existing "Click"/"Type" sections) for: `browser-wait.js`, `browser-hover.js`, `browser-select.js`, `browser-drag.js`, `browser-scroll.js`, `browser-key.js`, `browser-tabs.js`, `browser-upload.js`, and `browser-dialog.js`. For `browser-dialog.js`, show the background-arm pattern explicitly:

````markdown
## Dialogs (alert / confirm / prompt)

```bash
{baseDir}/browser-dialog.js accept & ; {baseDir}/browser-click.js @e3
{baseDir}/browser-dialog.js dismiss --timeout 5000 &
```

Arm the handler in the background **before** the action that triggers the
dialog. `accept --text "..."` supplies a response to a `prompt`.
````

- [ ] **Step 5: Note that click/type accept refs and auto-wait**

In the existing "Click" and "Type" sections, add that the selector argument
also accepts an `@eN` ref, and that the tools now wait for the element to be
visible, enabled, and stable before acting.

- [ ] **Step 6: Verify the skill still reads coherently**

Run: `cd browser-tools && head -40 SKILL.md`
Expected: updated description and a "Sessions" section present; no `{baseDir}` placeholders left unreplaced in prose (they are intentional in command examples).

- [ ] **Step 7: Commit**

```bash
git add browser-tools/SKILL.md
git commit -m "docs(browser-tools): document sessions, snapshot/refs, and new tools"
```

---

## Task 18: Re-benchmark (skill-creator iteration-2)

Re-run the skill-creator eval loop with the revised eval set, per the spec's testing section. This is done with the skill-creator skill, not coded here — this task records what iteration-2 must cover so it is not forgotten.

**Files:**
- Modify: `browser-tools/evals/evals.json`

- [ ] **Step 1: Revise the eval set**

Update `browser-tools/evals/evals.json`:
- Replace the `scrape-dynamic-list` Hacker News eval (static HTML — a poor discriminator) with a genuinely JS-rendered target.
- Keep `debug-broken-button` (deterministic, still valuable).
- Add an eval exercising the snapshot → `@ref` → act loop on `test/fixtures/form.html`.
- Add an eval exercising multi-tab handling.
- Add an eval exercising dialog handling on `test/fixtures/dialog.html`.

- [ ] **Step 2: Commit the eval set**

```bash
git add browser-tools/evals/evals.json
git commit -m "test(browser-tools): revise eval set for iteration-2"
```

- [ ] **Step 3: Run iteration-2 via skill-creator**

Hand off to the skill-creator workflow: run the revised evals with-skill vs. baseline. The global skills symlink MUST be removed for baseline runs so the comparison is not contaminated (iteration-1 finding). This step is interactive and produces `browser-tools-workspace/iteration-2/`.

---

## Self-Review Notes

- **Spec coverage:** Named multi-sessions → Tasks 1–5. Snapshot/refs → Tasks 6–7. Actionability waits → Task 1 (`waitActionable`), applied in Tasks 7, 9–11, 13. Tool inventory (snapshot, tabs, dialog, upload, wait, hover, select, drag, scroll, key, sessions) → Tasks 3, 6, 8–14. `getPage` active-tab resolution → Task 1, applied throughout. Error-handling contract → Task 1 helpers, used everywhere. `browser-trace.js` subresource fix → Task 15. SKILL.md docs → Task 17. Testing (fixtures, smoke test, iteration-2) → Tasks 6/11/12/13 fixtures, Task 16 smoke, Task 18 benchmark.
- **Sequencing risk:** Task 1 changes `connect()`/`tryConnect()` signatures; the codebase is not runnable until Tasks 4–5 update all callers. Tasks 1–5 should land together before mid-plan verification of unrelated tools. This is called out in Task 1.
- **Naming consistency:** `extractSession`, `connect(session)`, `getPage`, `resolveTarget`, `waitActionable`, `resolvePort`, `readMonitor(session)`, `isMonitorAlive(session)`, per-session path helpers (`sessionDir`/`profileDir`/`monitorJson`/`monitorErr`/`consoleLog`/`networkLog`) are used identically in every task that references them.
