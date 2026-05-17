#!/usr/bin/env node

import { connect } from "./lib.js";

const args = process.argv.slice(2);
const clear = args.includes("--clear");
const enter = args.includes("--enter");
const positional = args.filter((a) => !a.startsWith("--"));
const selector = positional[0];
const text = positional.slice(1).join(" ");

if (!selector || !text) {
	console.log("Usage: browser-type.js <selector> <text> [--clear] [--enter]");
	console.log("\nExamples:");
	console.log('  browser-type.js "#search" "hello world"');
	console.log('  browser-type.js "#search" "hello" --clear --enter');
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
	if (clear) {
		await p.click(selector, { clickCount: 3 }); // select existing content
		await p.keyboard.press("Backspace");
	}
	await p.type(selector, text);
	if (enter) await p.keyboard.press("Enter");
} catch (err) {
	console.error(`✗ Type failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Typed into ${selector}${clear ? " (cleared first)" : ""}${enter ? " + Enter" : ""}`);

await b.disconnect();
