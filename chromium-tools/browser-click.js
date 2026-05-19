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
