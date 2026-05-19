#!/usr/bin/env node

import { connect, extractSession, getPage, resolveTarget } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const mode = rest[0];
const arg = rest[1];
const tIdx = rest.indexOf("--timeout");
const timeout = tIdx >= 0 ? Number(rest[tIdx + 1]) : 10000;

const USAGE =
	"Usage: browser-wait.js <visible|gone|text|text-gone|navigation|idle|delay> [arg] [--timeout MS] [--session NAME]";

if (!mode) {
	console.log(USAGE);
	process.exit(0);
}

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	if (mode === "visible") {
		await p.waitForSelector(resolveTarget(arg), { visible: true, timeout });
		console.log(`✓ Visible: ${arg}`);
	} else if (mode === "gone") {
		await p.waitForSelector(resolveTarget(arg), { hidden: true, timeout });
		console.log(`✓ Gone: ${arg}`);
	} else if (mode === "text") {
		await p.waitForFunction((t) => document.body.innerText.includes(t), { timeout }, arg);
		console.log(`✓ Text appeared: "${arg}"`);
	} else if (mode === "text-gone") {
		await p.waitForFunction((t) => !document.body.innerText.includes(t), { timeout }, arg);
		console.log(`✓ Text gone: "${arg}"`);
	} else if (mode === "navigation") {
		await p.waitForNavigation({ waitUntil: "load", timeout });
		console.log(`✓ Navigated: ${p.url()}`);
	} else if (mode === "idle") {
		await p.waitForNetworkIdle({ timeout });
		console.log("✓ Network idle");
	} else if (mode === "delay") {
		await new Promise((r) => setTimeout(r, Number(arg)));
		console.log(`✓ Waited ${arg}ms`);
	} else {
		console.log(USAGE);
		await b.disconnect();
		process.exit(1);
	}
} catch (err) {
	console.error(`✗ Wait failed (${mode}): ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

await b.disconnect();
