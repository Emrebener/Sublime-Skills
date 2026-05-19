#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];

if (!target) {
	console.log("Usage: browser-hover.js <selector|@ref> [--session NAME]");
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
	await handle.hover();
} catch (err) {
	console.error(`✗ Hover failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Hovered: ${target}`);
await b.disconnect();
