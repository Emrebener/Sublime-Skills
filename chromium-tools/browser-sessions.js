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
