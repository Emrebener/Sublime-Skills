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
