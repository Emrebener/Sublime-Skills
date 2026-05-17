#!/usr/bin/env node

import { connect } from "./lib.js";

const selector = process.argv[2];
if (!selector) {
	console.log("Usage: browser-click.js <selector>");
	console.log("\nExample:");
	console.log('  browser-click.js "#submit"');
	process.exit(1);
}

const b = await connect();
const p = (await b.pages()).at(-1); // last open tab, as every script does

if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	await p.waitForSelector(selector, { timeout: 5000 });
} catch {
	console.error(`✗ Selector not found: ${selector}`);
	await b.disconnect();
	process.exit(1);
}

try {
	await p.click(selector);
} catch (err) {
	console.error(`✗ Click failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}
console.log(`✓ Clicked: ${selector}`);

await b.disconnect();
