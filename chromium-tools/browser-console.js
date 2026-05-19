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

const errorsOnly = rest.includes("--errors");
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

if (errorsOnly) {
	events = events.filter((e) => e.type === "error" || e.type === "warning" || e.type === "warn");
}
if (limit) events = events.slice(-limit);

for (const e of events) {
	const loc = e.location ? ` (${e.location})` : "";
	console.log(`[${e.type}] ${e.text}${loc}`);
}
if (events.length === 0) console.log("(no matching console entries)");

if (!isMonitorAlive(session)) {
	console.error("");
	console.error("⚠ Monitor not running — entries above are from a previous session.");
	console.error("  Run: browser-monitor.js start");
}
