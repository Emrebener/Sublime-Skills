#!/usr/bin/env node

import { spawn } from "node:child_process";
import {
	existsSync, openSync, closeSync, writeSync, writeFileSync,
	appendFileSync, readFileSync, rmSync, statSync, mkdirSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import {
	extractSession, sessionDir, monitorJson, monitorErr, consoleLog, networkLog,
	HEARTBEAT_MS, tryConnect, connect, resolvePort, readMonitor, isMonitorAlive,
} from "./lib.js";

const SELF = fileURLToPath(import.meta.url);

// ---------------------------------------------------------------------
// Daemon loop (runs as a detached background process: `__daemon <session>`)
// ---------------------------------------------------------------------
async function runDaemon() {
	const session = process.argv[3];
	mkdirSync(sessionDir(session), { recursive: true });
	const browser = await connect(session); // exits(1) -> stderr to monitor.err

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

	const attach = async (page) => {
		page.on("console", (msg) => {
			const loc = msg.location();
			logConsole({
				ts: Date.now(),
				tabUrl: page.url(),
				type: msg.type(),
				text: msg.text(),
				location: loc && loc.url ? `${loc.url}:${loc.lineNumber ?? ""}` : null,
			});
		});
		page.on("pageerror", (err) => {
			logConsole({ ts: Date.now(), tabUrl: page.url(), type: "error", text: err.message });
		});

		// Network via a raw CDP session: gives the native requestId and
		// the real transfer size (encodedDataLength).
		const client = await page.createCDPSession();
		await client.send("Network.enable");
		// reqs holds in-flight requests until loadingFinished/loadingFailed.
		// Streaming requests (SSE/WebSocket) that never finish are not evicted —
		// acceptable for short, session-scoped monitoring; cleared on each start.
		const reqs = new Map();
		client.on("Network.requestWillBeSent", (p) => {
			reqs.set(p.requestId, {
				method: p.request.method,
				url: p.request.url,
				type: p.type || "Other",
				startTs: p.timestamp,
				status: 0,
			});
		});
		client.on("Network.responseReceived", (p) => {
			const r = reqs.get(p.requestId);
			if (r) {
				r.status = p.response.status;
				r.type = p.type || r.type;
			}
		});
		client.on("Network.loadingFinished", (p) => {
			const r = reqs.get(p.requestId);
			if (!r) return;
			logNetwork({
				ts: Date.now(),
				tabUrl: page.url(),
				requestId: p.requestId,
				method: r.method,
				url: r.url,
				status: r.status,
				resourceType: r.type,
				size: Math.round(p.encodedDataLength || 0),
				timingMs: r.startTs ? Math.round((p.timestamp - r.startTs) * 1000) : null,
			});
			reqs.delete(p.requestId);
		});
		client.on("Network.loadingFailed", (p) => {
			const r = reqs.get(p.requestId) || {};
			logNetwork({
				ts: Date.now(),
				tabUrl: page.url(),
				requestId: p.requestId,
				method: r.method || null,
				url: r.url || null,
				errorText: p.errorText || "failed",
			});
			reqs.delete(p.requestId);
		});
	};

	for (const page of await browser.pages()) await attach(page);
	browser.on("targetcreated", async (target) => {
		if (target.type() !== "page") return; // skip workers etc.
		const page = await target.page();
		if (page) await attach(page);
	});

	browser.on("disconnected", () => {
		clearInterval(hb);
		try { rmSync(MON, { force: true }); } catch {}
		process.exit(0);
	});
}

// ---------------------------------------------------------------------
// CLI: start
// ---------------------------------------------------------------------
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
	// A non-alive monitor.json is stale — remove before the lock.
	if (existsSync(MON)) rmSync(MON, { force: true });

	// Exclusive create = atomic lock. Loses to a concurrent start.
	let fd;
	try {
		fd = openSync(MON, "wx");
	} catch {
		console.error("✗ Another monitor start is in progress");
		process.exit(1);
	}
	writeSync(fd, JSON.stringify({ pid: 0, startedAt: Date.now(), lastHeartbeat: 0 }));
	closeSync(fd);

	// Only now — lock held — clear the logs.
	writeFileSync(consoleLog(session), "");
	writeFileSync(networkLog(session), "");

	// Spawn the detached daemon, stderr -> monitor.err.
	const errFd = openSync(monitorErr(session), "w");
	const child = spawn(process.execPath, [SELF, "__daemon", session], {
		detached: true,
		stdio: ["ignore", "ignore", errFd],
	});
	child.unref();
	closeSync(errFd);

	// Wait up to 3s for the daemon's first real heartbeat.
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

// ---------------------------------------------------------------------
// CLI: stop
// ---------------------------------------------------------------------
function stopDaemon(session) {
	const info = readMonitor(session);
	if (isMonitorAlive(session, info)) {
		try { process.kill(info.pid); } catch {}
		rmSync(monitorJson(session), { force: true });
		console.log(`✓ Monitor stopped for "${session}" (pid ${info.pid})`);
	} else {
		if (info) rmSync(monitorJson(session), { force: true }); // clean stale file
		console.log(`Monitor not running for "${session}"`);
	}
}

// ---------------------------------------------------------------------
// CLI: status
// ---------------------------------------------------------------------
function countAndSize(path) {
	if (!existsSync(path)) return { lines: 0, bytes: 0 };
	const bytes = statSync(path).size;
	const lines = readFileSync(path, "utf8").split("\n").filter(Boolean).length;
	return { lines, bytes };
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

// ---------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------
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
