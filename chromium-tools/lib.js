import { homedir } from "node:os";
import { join } from "node:path";
import { existsSync, readFileSync } from "node:fs";
import puppeteer from "puppeteer-core";

export const CACHE_DIR = join(homedir(), ".cache", "browser-tools");
export const MONITOR_JSON = join(CACHE_DIR, "monitor.json");
export const MONITOR_ERR = join(CACHE_DIR, "monitor.err");
export const CONSOLE_LOG = join(CACHE_DIR, "console.jsonl");
export const NETWORK_LOG = join(CACHE_DIR, "network.jsonl");

export const HEARTBEAT_MS = 5000;
export const HEARTBEAT_STALE_MS = 15000;

// Connect to the browser on :9222 with a 5s timeout. Returns the browser
// or null — never throws, never exits.
export async function tryConnect() {
	let browser;
	try {
		browser = await Promise.race([
			puppeteer.connect({ browserURL: "http://localhost:9222", defaultViewport: null }),
			new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000)),
		]);
		return browser;
	} catch {
		// If connect() resolved after the race rejected, disconnect it.
		if (browser) browser.disconnect().catch(() => {});
		return null;
	}
}

// Connect or exit(1) with the standard guidance.
export async function connect() {
	const browser = await tryConnect();
	if (!browser) {
		console.error("✗ Could not connect to browser on :9222");
		console.error("  Run: browser-start.js");
		process.exit(1);
	}
	return browser;
}

// Read monitor.json, or null if absent/corrupt.
export function readMonitor() {
	if (!existsSync(MONITOR_JSON)) return null;
	try {
		return JSON.parse(readFileSync(MONITOR_JSON, "utf8"));
	} catch {
		return null;
	}
}

// Liveness predicate: monitor.json exists, its pid is alive, and the
// heartbeat is fresh. A stale heartbeat covers crashed daemons, PID
// reuse, hung daemons, and a Chromium restart that ended the daemon.
export function isMonitorAlive(info = readMonitor()) {
	if (!info || !info.pid || !info.lastHeartbeat) return false;
	try {
		process.kill(info.pid, 0);
	} catch {
		return false;
	}
	return Date.now() - info.lastHeartbeat < HEARTBEAT_STALE_MS;
}
