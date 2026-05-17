#!/usr/bin/env node

import { spawn } from "node:child_process";
import {
	existsSync, openSync, closeSync, writeSync, writeFileSync,
	appendFileSync, readFileSync, rmSync, statSync, mkdirSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import {
	CACHE_DIR, MONITOR_JSON, MONITOR_ERR, CONSOLE_LOG, NETWORK_LOG,
	HEARTBEAT_MS, tryConnect, connect,
	readMonitor, isMonitorAlive,
} from "./lib.js";

const SELF = fileURLToPath(import.meta.url);

// ---------------------------------------------------------------------
// Daemon loop (runs as a detached background process: `__daemon`)
// ---------------------------------------------------------------------
async function runDaemon() {
	mkdirSync(CACHE_DIR, { recursive: true });
	const browser = await connect(); // exits(1) -> stderr to monitor.err

	const identity = {
		pid: process.pid,
		startedAt: Date.now(),
		wsEndpoint: browser.wsEndpoint(),
		lastHeartbeat: Date.now(),
	};
	const persist = () => writeFileSync(MONITOR_JSON, JSON.stringify(identity));
	persist();
	const hb = setInterval(() => {
		identity.lastHeartbeat = Date.now();
		persist();
	}, HEARTBEAT_MS);

	const logConsole = (e) => appendFileSync(CONSOLE_LOG, JSON.stringify(e) + "\n");
	const logNetwork = (e) => appendFileSync(NETWORK_LOG, JSON.stringify(e) + "\n");

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
		try { rmSync(MONITOR_JSON, { force: true }); } catch {}
		process.exit(0);
	});
}

// ---------------------------------------------------------------------
// CLI: start
// ---------------------------------------------------------------------
async function startDaemon() {
	mkdirSync(CACHE_DIR, { recursive: true });

	if (isMonitorAlive()) {
		console.log(`✓ Monitor already running (pid ${readMonitor().pid})`);
		process.exit(0);
	}

	// Pre-check the browser so the common "forgot browser-start" case
	// fails fast with clear guidance instead of after a 3s wait.
	const pre = await tryConnect();
	if (!pre) {
		console.error("✗ Chromium is not running on :9222");
		console.error("  Run: browser-start.js");
		process.exit(1);
	}
	await pre.disconnect();

	// A non-alive monitor.json is stale — remove before the lock.
	if (existsSync(MONITOR_JSON)) rmSync(MONITOR_JSON, { force: true });

	// Exclusive create = atomic lock. Loses to a concurrent start.
	let fd;
	try {
		fd = openSync(MONITOR_JSON, "wx");
	} catch {
		console.error("✗ Another monitor start is in progress");
		process.exit(1);
	}
	writeSync(fd, JSON.stringify({ pid: 0, startedAt: Date.now(), lastHeartbeat: 0 }));
	closeSync(fd);

	// Only now — lock held — clear the logs.
	writeFileSync(CONSOLE_LOG, "");
	writeFileSync(NETWORK_LOG, "");

	// Spawn the detached daemon, stderr -> monitor.err.
	const errFd = openSync(MONITOR_ERR, "w");
	const child = spawn(process.execPath, [SELF, "__daemon"], {
		detached: true,
		stdio: ["ignore", "ignore", errFd],
	});
	child.unref();
	closeSync(errFd);

	// Wait up to 3s for the daemon's first real heartbeat.
	const deadline = Date.now() + 3000;
	const tick = () => {
		if (isMonitorAlive()) {
			console.log(`✓ Monitor started (pid ${readMonitor().pid})`);
			process.exit(0);
		}
		if (Date.now() > deadline) {
			console.error("✗ Monitor failed to start");
			try {
				const tail = readFileSync(MONITOR_ERR, "utf8").trim().split("\n").slice(-10);
				if (tail.length && tail[0]) console.error("  monitor.err:\n  " + tail.join("\n  "));
			} catch {}
			rmSync(MONITOR_JSON, { force: true });
			process.exit(1);
		}
		setTimeout(tick, 200);
	};
	tick();
}

// ---------------------------------------------------------------------
// CLI: stop
// ---------------------------------------------------------------------
function stopDaemon() {
	const info = readMonitor();
	if (isMonitorAlive(info)) {
		try { process.kill(info.pid); } catch {}
		rmSync(MONITOR_JSON, { force: true });
		console.log(`✓ Monitor stopped (pid ${info.pid})`);
	} else {
		if (info) rmSync(MONITOR_JSON, { force: true }); // clean stale file
		console.log("Monitor not running");
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

function statusDaemon() {
	const info = readMonitor();
	if (isMonitorAlive(info)) {
		const c = countAndSize(CONSOLE_LOG);
		const n = countAndSize(NETWORK_LOG);
		console.log(`✓ Monitor running (pid ${info.pid})`);
		console.log(`  started: ${new Date(info.startedAt).toISOString()}`);
		console.log(`  console.jsonl: ${c.lines} events (${(c.bytes / 1024).toFixed(1)} KB)`);
		console.log(`  network.jsonl: ${n.lines} events (${(n.bytes / 1024).toFixed(1)} KB)`);
	} else {
		console.log("✗ Monitor not running");
		if (info) console.log("  (stale monitor.json present — a previous daemon ended)");
	}
}

// ---------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------
const cmd = process.argv[2];
if (cmd === "__daemon") {
	await runDaemon();
} else if (cmd === "start") {
	await startDaemon();
} else if (cmd === "stop") {
	stopDaemon();
} else if (cmd === "status") {
	statusDaemon();
} else {
	console.log("Usage: browser-monitor.js <start|stop|status>");
	console.log("\nStart a background daemon that records console and network");
	console.log("events from the browser on :9222 to log files.");
	process.exit(cmd ? 1 : 0);
}
