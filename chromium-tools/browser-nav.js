#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const url = rest.find(a => !a.startsWith("--"));
const newTab = rest.includes("--new");
const reload = rest.includes("--reload");

if (!url) {
	console.log("Usage: browser-nav.js <url> [--new] [--reload] [--session NAME]");
	console.log("\nExamples:");
	console.log("  browser-nav.js https://example.com          # Navigate current tab");
	console.log("  browser-nav.js https://example.com --new    # Open in new tab");
	console.log("  browser-nav.js https://example.com --reload # Navigate and force reload");
	process.exit(1);
}

const b = await connect(session);

if (newTab) {
	const p = await b.newPage();
	await p.bringToFront();
	await p.goto(url, { waitUntil: "domcontentloaded" });
	console.log("✓ Opened:", url);
} else {
	const p = await getPage(b);
	await p.goto(url, { waitUntil: "domcontentloaded" });
	if (reload) {
		await p.reload({ waitUntil: "domcontentloaded" });
	}
	console.log("✓ Navigated to:", url);
}

await b.disconnect();
