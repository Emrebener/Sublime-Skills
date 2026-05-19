#!/usr/bin/env node

import { connect, extractSession, getPage, waitActionable } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const from = rest[0];
const to = rest[1];

if (!from || !to) {
	console.log("Usage: browser-drag.js <from selector|@ref> <to selector|@ref> [--session NAME]");
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
	const src = await waitActionable(p, from);
	const dst = await waitActionable(p, to);
	// HTML5-native drag (draggable="true") and mouse-gesture drag are
	// different mechanisms: a native drag consumes the synthetic mouseup, so a
	// plain mouse gesture silently fails on it. Detect which kind the source
	// is and use the matching technique.
	const native = await src.evaluate((el) => el.draggable === true);
	if (native) {
		await p.setDragInterception(true);
		await src.dragAndDrop(dst);
	} else {
		const sb = await src.boundingBox();
		const db = await dst.boundingBox();
		if (!sb || !db) throw new Error("could not measure element positions");
		await p.mouse.move(sb.x + sb.width / 2, sb.y + sb.height / 2);
		await p.mouse.down();
		// Move in steps so drag-tracking handlers fire.
		await p.mouse.move(db.x + db.width / 2, db.y + db.height / 2, { steps: 10 });
		await p.mouse.up();
	}
} catch (err) {
	console.error(`✗ Drag failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Dragged ${from} → ${to}`);
await b.disconnect();
