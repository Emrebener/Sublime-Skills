#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const target = rest[0];
const choices = rest.slice(1);

if (!target || choices.length === 0) {
	console.log("Usage: browser-select.js <selector|@ref> <value-or-label...> [--session NAME]");
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
	// Map each requested choice to an option value: accept either the
	// option's `value` or its visible label.
	const values = await handle.evaluate((el, wanted) => {
		const opts = Array.from(el.options || []);
		return wanted.map((w) => {
			const byValue = opts.find((o) => o.value === w);
			if (byValue) return byValue.value;
			const byLabel = opts.find((o) => o.textContent.trim() === w);
			if (byLabel) return byLabel.value;
			return null;
		});
	}, choices);
	const missing = choices.filter((_, i) => values[i] === null);
	if (missing.length) {
		throw new Error(`no option matching: ${missing.join(", ")}`);
	}
	await handle.select(...values);
} catch (err) {
	console.error(`✗ Select failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Selected ${choices.join(", ")} in ${target}`);
await b.disconnect();
