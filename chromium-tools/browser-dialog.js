#!/usr/bin/env node

import { connect, extractSession } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const action = rest[0];
const textIdx = rest.indexOf("--text");
const promptText = textIdx >= 0 ? rest[textIdx + 1] : "";
const tIdx = rest.indexOf("--timeout");
const timeout = tIdx >= 0 ? Number(rest[tIdx + 1]) : 30000;

if (action !== "accept" && action !== "dismiss") {
	console.log("Usage: browser-dialog.js <accept|dismiss> [--text TEXT] [--timeout MS] [--session NAME]");
	console.log("\nArms a handler for the NEXT dialog. Run in the background before the");
	console.log("action that triggers the dialog, e.g.:");
	console.log("  browser-dialog.js accept & ; browser-click.js @e3");
	process.exit(action ? 1 : 0);
}

const b = await connect(session);
let handled = false;

function arm(page) {
	page.on("dialog", async (dialog) => {
		if (handled) return;
		handled = true;
		const msg = dialog.message();
		const type = dialog.type();
		try {
			if (action === "accept") await dialog.accept(promptText);
			else await dialog.dismiss();
			console.log(`✓ ${action === "accept" ? "Accepted" : "Dismissed"} ${type}: "${msg}"`);
		} catch (err) {
			console.error(`✗ Dialog handling failed: ${err.message}`);
		}
		await b.disconnect();
		process.exit(0);
	});
}

for (const page of await b.pages()) arm(page);
b.on("targetcreated", async (t) => {
	if (t.type() !== "page") return;
	const page = await t.page();
	if (page) arm(page);
});

setTimeout(async () => {
	if (!handled) {
		console.error(`✗ No dialog appeared within ${timeout}ms`);
		await b.disconnect();
		process.exit(1);
	}
}, timeout);
