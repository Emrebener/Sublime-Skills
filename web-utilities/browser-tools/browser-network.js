#!/usr/bin/env node

import { extractSession, networkLog, isMonitorAlive } from "./lib.js";
import { existsSync, readFileSync } from "node:fs";

const { session, rest } = extractSession(process.argv.slice(2));
const LOG = networkLog(session);

if (!isMonitorAlive(session) && !existsSync(LOG)) {
	console.error(`✗ No monitor data for session "${session}"`);
	console.error("  Run: browser-monitor.js start");
	process.exit(1);
}

const failedOnly = rest.includes("--failed");
const limIdx = rest.indexOf("--limit");
const limit = limIdx !== -1 ? parseInt(rest[limIdx + 1], 10) : null;

if (limIdx !== -1 && (!limit || limit < 1)) {
	console.error("✗ --limit needs a positive number");
	process.exit(1);
}

let events = readFileSync(LOG, "utf8")
	.split("\n")
	.filter(Boolean)
	.map((l) => { try { return JSON.parse(l); } catch { return null; } })
	.filter(Boolean);

// A failure is a requestfailed entry, or a response with status >= 400.
// 304 (Not Modified) and 1xx are not failures.
if (failedOnly) {
	events = events.filter((e) => e.errorText || (typeof e.status === "number" && e.status >= 400));
}
if (limit) events = events.slice(-limit);

for (const e of events) {
	if (e.errorText) {
		console.log(`FAILED ${e.method || "?"} ${e.url || "?"} — ${e.errorText}`);
	} else {
		const kb = ((e.size || 0) / 1024).toFixed(1);
		const ms = e.timingMs ?? "?";
		console.log(`${e.status} ${e.method} ${e.url} [${e.resourceType}, ${kb} KB, ${ms} ms]`);
	}
}
if (events.length === 0) console.log("(no matching network entries)");

if (!isMonitorAlive(session)) {
	console.error("");
	console.error("⚠ Monitor not running — entries above are from a previous session.");
	console.error("  Run: browser-monitor.js start");
}
