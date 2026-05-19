#!/usr/bin/env node

import { connect, extractSession } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const cmd = rest[0] || "list";

const b = await connect(session);
const pages = await b.pages();

try {
	if (cmd === "list") {
		for (let i = 0; i < pages.length; i++) {
			const title = await pages[i].title().catch(() => "");
			const visible = await pages[i]
				.evaluate(() => document.visibilityState === "visible")
				.catch(() => false);
			console.log(`[${i}]${visible ? " *" : "  "} ${pages[i].url()}  ${title}`);
		}
	} else if (cmd === "new") {
		const page = await b.newPage();
		if (rest[1]) await page.goto(rest[1], { waitUntil: "load" });
		await page.bringToFront();
		console.log(`✓ Opened tab [${(await b.pages()).length - 1}]${rest[1] ? ` → ${rest[1]}` : ""}`);
	} else if (cmd === "select") {
		const i = Number(rest[1]);
		if (!pages[i]) throw new Error(`no tab at index ${i}`);
		await pages[i].bringToFront();
		console.log(`✓ Selected tab [${i}] ${pages[i].url()}`);
	} else if (cmd === "close") {
		const i = Number(rest[1]);
		if (!pages[i]) throw new Error(`no tab at index ${i}`);
		const url = pages[i].url();
		await pages[i].close();
		console.log(`✓ Closed tab [${i}] ${url}`);
	} else {
		console.log("Usage: browser-tabs.js <list|new [url]|select <index>|close <index>> [--session NAME]");
		await b.disconnect();
		process.exit(1);
	}
} catch (err) {
	console.error(`✗ Tabs command failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
