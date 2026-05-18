#!/usr/bin/env node

import { tmpdir } from "node:os";
import { join } from "node:path";
import { connect, extractSession, getPage } from "./lib.js";

const { session } = extractSession(process.argv.slice(2));

const b = await connect(session);
const p = await getPage(b);

if (!p) {
	console.error("✗ No active tab found");
	process.exit(1);
}

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const filename = `screenshot-${timestamp}.png`;
const filepath = join(tmpdir(), filename);

await p.screenshot({ path: filepath });

console.log(filepath);

await b.disconnect();
