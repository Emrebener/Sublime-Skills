#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const byIdx = rest.indexOf("--by");

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	if (byIdx >= 0) {
		// Scroll the window by a pixel amount.
		const pixels = Number(rest[byIdx + 1]);
		await p.evaluate((y) => window.scrollBy(0, y), pixels);
		console.log(`✓ Scrolled window by ${pixels}px`);
	} else if (rest[0]) {
		// Scroll an element into view.
		const selector = resolveTarget(rest[0]);
		const handle = await p.waitForSelector(selector, { timeout: 5000 });
		await handle.evaluate((el) => el.scrollIntoView({ block: "center" }));
		console.log(`✓ Scrolled into view: ${rest[0]}`);
	} else {
		console.log("Usage: browser-scroll.js <selector|@ref> | --by <pixels> [--session NAME]");
		await b.disconnect();
		process.exit(0);
	}
} catch (err) {
	console.error(`✗ Scroll failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
