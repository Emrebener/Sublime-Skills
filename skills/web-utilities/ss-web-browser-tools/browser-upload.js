#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const files = rest.slice(1);

if (!target || files.length === 0) {
	console.log("Usage: browser-upload.js <selector|@ref> <file...> [--session NAME]");
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
	// File inputs are often visually hidden — wait for presence only.
	const handle = await p.waitForSelector(resolveTarget(target), { timeout: 5000 });
	await handle.uploadFile(...files);
} catch (err) {
	console.error(`✗ Upload failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Set ${files.length} file(s) on ${target}`);
await b.disconnect();
