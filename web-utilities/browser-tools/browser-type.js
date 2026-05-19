#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const text = rest.slice(1).filter((a) => a !== "--clear" && a !== "--enter").join(" ");
const clear = rest.includes("--clear");
const enter = rest.includes("--enter");

if (!target) {
	console.log("Usage: browser-type.js <selector|@ref> <text> [--clear] [--enter] [--session NAME]");
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
	if (clear) {
		await handle.evaluate((el) => {
			if ("value" in el) el.value = "";
		});
	}
	await handle.type(text);
	if (enter) await p.keyboard.press("Enter");
} catch (err) {
	console.error(`✗ Type failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Typed into ${target}`);
await b.disconnect();
