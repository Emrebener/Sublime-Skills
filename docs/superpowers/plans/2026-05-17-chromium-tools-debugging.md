# chromium-tools Debugging Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `chromium-tools` skill with console capture, network inspection, dedicated interaction, and a performance summary — all as CLI scripts, no MCP.

**Architecture:** A background collector daemon (`browser-monitor.js`) attaches to the Chromium instance on `:9222` and appends console/network events to JSONL log files; query scripts read those logs. Interaction and performance scripts connect, act, and exit. A shared `lib.js` provides the connection helper and the daemon liveness predicate so the three monitor-aware scripts agree on one definition.

**Tech Stack:** Node.js (ESM), `puppeteer-core` (already a dependency), Chrome DevTools Protocol. No new npm dependencies.

---

## Reference

- Design spec: `docs/superpowers/specs/2026-05-17-chromium-tools-debugging-design.md`
- All new files go in `chromium-tools/`. Executable scripts need `chmod +x` and a `#!/usr/bin/env node` shebang, matching the existing `browser-*.js` scripts.
- `package.json` has `"type": "module"`, so scripts use ESM `import` and top-level `await`.
- Existing scripts connect with a 5s `Promise.race` timeout and print `Run: browser-start.js` on failure. New scripts reuse this via `lib.js`.

## File Structure

| File | Responsibility |
|---|---|
| `chromium-tools/lib.js` (new) | Shared: cache paths, `connect()`/`tryConnect()`, `readMonitor()`, `isMonitorAlive()` |
| `chromium-tools/browser-monitor.js` (new) | Daemon lifecycle (`start`/`stop`/`status`) + the daemon loop (`__daemon`) |
| `chromium-tools/browser-console.js` (new) | Query `console.jsonl` |
| `chromium-tools/browser-network.js` (new) | Query `network.jsonl` |
| `chromium-tools/browser-click.js` (new) | Click an element by selector |
| `chromium-tools/browser-type.js` (new) | Type text into a field |
| `chromium-tools/browser-trace.js` (new) | Navigate + print a performance summary |
| `chromium-tools/SKILL.md` (modify) | Document the six new tools + debugging workflow |

`lib.js` is new but justified: the spec mandates "a single predicate, used by `start`, `stop`, `status`, and the query scripts." One implementation prevents the predicate drifting across five files. The existing seven `browser-*.js` scripts are **not** refactored to use `lib.js` — that would be unrelated churn.

---

## Setup: Verification Environment

This skill has no test framework; verification is by running each script against a live Chromium, per the spec's Testing section. Do this setup once before Task 2.

- [ ] **Step 1: Install dependencies**

Run: `cd chromium-tools && npm install`
Expected: completes with `found 0 vulnerabilities` (or similar). `node_modules/` now exists.

- [ ] **Step 2: Create the verification fixture**

Create `/tmp/chromium-tools-fixture/index.html`:

```html
<!doctype html>
<html>
<head><title>Fixture</title></head>
<body>
<h1>Fixture Page</h1>
<input id="q" type="text">
<button id="go">Go</button>
<script>
console.log("fixture loaded");
console.warn("a sample warning");
console.error("a sample error");
fetch("/missing-endpoint").catch(() => {});
fetch("/").then(() => {});
setTimeout(() => { throw new Error("uncaught fixture error"); }, 100);
</script>
</body>
</html>
```

- [ ] **Step 3: Serve the fixture**

Run (in the background): `python3 -m http.server 8123 --directory /tmp/chromium-tools-fixture`
The fixture is now at `http://localhost:8123/`. `/` returns 200; `/missing-endpoint` returns 404.

- [ ] **Step 4: Start Chromium**

Run: `chromium-tools/browser-start.js`
Expected: `✓ Browser started on :9222 (/usr/bin/chromium)` (or `✓ Chrome already running on :9222`).

---

## Task 1: Shared library (`lib.js`)

**Files:**
- Create: `chromium-tools/lib.js`

- [ ] **Step 1: Write `lib.js`**

```javascript
import { homedir } from "node:os";
import { join } from "node:path";
import { existsSync, readFileSync } from "node:fs";
import puppeteer from "puppeteer-core";

export const CACHE_DIR = join(homedir(), ".cache", "browser-tools");
export const MONITOR_JSON = join(CACHE_DIR, "monitor.json");
export const MONITOR_ERR = join(CACHE_DIR, "monitor.err");
export const CONSOLE_LOG = join(CACHE_DIR, "console.jsonl");
export const NETWORK_LOG = join(CACHE_DIR, "network.jsonl");

export const HEARTBEAT_MS = 5000;
export const HEARTBEAT_STALE_MS = 15000;

// Connect to the browser on :9222 with a 5s timeout. Returns the browser
// or null — never throws, never exits.
export async function tryConnect() {
	return Promise.race([
		puppeteer.connect({ browserURL: "http://localhost:9222", defaultViewport: null }),
		new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000)),
	]).catch(() => null);
}

// Connect or exit(1) with the standard guidance.
export async function connect() {
	const browser = await tryConnect();
	if (!browser) {
		console.error("✗ Could not connect to browser on :9222");
		console.error("  Run: browser-start.js");
		process.exit(1);
	}
	return browser;
}

// Read monitor.json, or null if absent/corrupt.
export function readMonitor() {
	if (!existsSync(MONITOR_JSON)) return null;
	try {
		return JSON.parse(readFileSync(MONITOR_JSON, "utf8"));
	} catch {
		return null;
	}
}

// Liveness predicate: monitor.json exists, its pid is alive, and the
// heartbeat is fresh. A stale heartbeat covers crashed daemons, PID
// reuse, hung daemons, and a Chromium restart that ended the daemon.
export function isMonitorAlive(info = readMonitor()) {
	if (!info || !info.pid || !info.lastHeartbeat) return false;
	try {
		process.kill(info.pid, 0);
	} catch {
		return false;
	}
	return Date.now() - info.lastHeartbeat < HEARTBEAT_STALE_MS;
}
```

- [ ] **Step 2: Verify it loads**

Run: `cd chromium-tools && node -e "import('./lib.js').then(m => console.log(Object.keys(m).join(',')))"`
Expected: `CACHE_DIR,MONITOR_JSON,MONITOR_ERR,CONSOLE_LOG,NETWORK_LOG,HEARTBEAT_MS,HEARTBEAT_STALE_MS,tryConnect,connect,readMonitor,isMonitorAlive`

- [ ] **Step 3: Commit**

```bash
git add chromium-tools/lib.js
git commit -m "Add shared lib.js for chromium-tools debugging scripts"
```

---

## Task 2: Monitor daemon (`browser-monitor.js`)

**Files:**
- Create: `chromium-tools/browser-monitor.js`

- [ ] **Step 1: Write `browser-monitor.js`**

```javascript
#!/usr/bin/env node

import { spawn } from "node:child_process";
import {
	existsSync, openSync, closeSync, writeSync, writeFileSync,
	appendFileSync, readFileSync, rmSync, statSync, mkdirSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import {
	CACHE_DIR, MONITOR_JSON, MONITOR_ERR, CONSOLE_LOG, NETWORK_LOG,
	HEARTBEAT_MS, HEARTBEAT_STALE_MS, tryConnect, connect,
	readMonitor, isMonitorAlive,
} from "./lib.js";

const SELF = fileURLToPath(import.meta.url);

// ---------------------------------------------------------------------
// Daemon loop (runs as a detached background process: `__daemon`)
// ---------------------------------------------------------------------
async function runDaemon() {
	mkdirSync(CACHE_DIR, { recursive: true });
	const browser = await connect(); // exits(1) -> stderr to monitor.err

	const identity = {
		pid: process.pid,
		startedAt: Date.now(),
		wsEndpoint: browser.wsEndpoint(),
		lastHeartbeat: Date.now(),
	};
	const persist = () => writeFileSync(MONITOR_JSON, JSON.stringify(identity));
	persist();
	const hb = setInterval(() => {
		identity.lastHeartbeat = Date.now();
		persist();
	}, HEARTBEAT_MS);

	const logConsole = (e) => appendFileSync(CONSOLE_LOG, JSON.stringify(e) + "\n");
	const logNetwork = (e) => appendFileSync(NETWORK_LOG, JSON.stringify(e) + "\n");

	const attach = async (page) => {
		page.on("console", (msg) => {
			const loc = msg.location();
			logConsole({
				ts: Date.now(),
				tabUrl: page.url(),
				type: msg.type(),
				text: msg.text(),
				location: loc && loc.url ? `${loc.url}:${loc.lineNumber ?? ""}` : null,
			});
		});
		page.on("pageerror", (err) => {
			logConsole({ ts: Date.now(), tabUrl: page.url(), type: "error", text: err.message });
		});

		// Network via a raw CDP session: gives the native requestId and
		// the real transfer size (encodedDataLength).
		const client = await page.createCDPSession();
		await client.send("Network.enable");
		const reqs = new Map();
		client.on("Network.requestWillBeSent", (p) => {
			reqs.set(p.requestId, {
				method: p.request.method,
				url: p.request.url,
				type: p.type || "Other",
				startTs: p.timestamp,
				status: 0,
			});
		});
		client.on("Network.responseReceived", (p) => {
			const r = reqs.get(p.requestId);
			if (r) {
				r.status = p.response.status;
				r.type = p.type || r.type;
			}
		});
		client.on("Network.loadingFinished", (p) => {
			const r = reqs.get(p.requestId);
			if (!r) return;
			logNetwork({
				ts: Date.now(),
				tabUrl: page.url(),
				requestId: p.requestId,
				method: r.method,
				url: r.url,
				status: r.status,
				resourceType: r.type,
				size: Math.round(p.encodedDataLength || 0),
				timingMs: r.startTs ? Math.round((p.timestamp - r.startTs) * 1000) : null,
			});
			reqs.delete(p.requestId);
		});
		client.on("Network.loadingFailed", (p) => {
			const r = reqs.get(p.requestId) || {};
			logNetwork({
				ts: Date.now(),
				tabUrl: page.url(),
				requestId: p.requestId,
				method: r.method || null,
				url: r.url || null,
				errorText: p.errorText || "failed",
			});
			reqs.delete(p.requestId);
		});
	};

	for (const page of await browser.pages()) await attach(page);
	browser.on("targetcreated", async (target) => {
		if (target.type() !== "page") return; // skip workers etc.
		const page = await target.page();
		if (page) await attach(page);
	});

	browser.on("disconnected", () => {
		clearInterval(hb);
		try { rmSync(MONITOR_JSON, { force: true }); } catch {}
		process.exit(0);
	});
}

// ---------------------------------------------------------------------
// CLI: start
// ---------------------------------------------------------------------
async function startDaemon() {
	mkdirSync(CACHE_DIR, { recursive: true });

	if (isMonitorAlive()) {
		console.log(`✓ Monitor already running (pid ${readMonitor().pid})`);
		process.exit(0);
	}

	// Pre-check the browser so the common "forgot browser-start" case
	// fails fast with clear guidance instead of after a 3s wait.
	const pre = await tryConnect();
	if (!pre) {
		console.error("✗ Chromium is not running on :9222");
		console.error("  Run: browser-start.js");
		process.exit(1);
	}
	await pre.disconnect();

	// A non-alive monitor.json is stale — remove before the lock.
	if (existsSync(MONITOR_JSON)) rmSync(MONITOR_JSON, { force: true });

	// Exclusive create = atomic lock. Loses to a concurrent start.
	let fd;
	try {
		fd = openSync(MONITOR_JSON, "wx");
	} catch {
		console.error("✗ Another monitor start is in progress");
		process.exit(1);
	}
	writeSync(fd, JSON.stringify({ pid: 0, startedAt: Date.now(), lastHeartbeat: 0 }));
	closeSync(fd);

	// Only now — lock held — clear the logs.
	writeFileSync(CONSOLE_LOG, "");
	writeFileSync(NETWORK_LOG, "");

	// Spawn the detached daemon, stderr -> monitor.err.
	const errFd = openSync(MONITOR_ERR, "w");
	const child = spawn(process.execPath, [SELF, "__daemon"], {
		detached: true,
		stdio: ["ignore", "ignore", errFd],
	});
	child.unref();
	closeSync(errFd);

	// Wait up to 3s for the daemon's first real heartbeat.
	const deadline = Date.now() + 3000;
	const tick = () => {
		if (isMonitorAlive()) {
			console.log(`✓ Monitor started (pid ${readMonitor().pid})`);
			process.exit(0);
		}
		if (Date.now() > deadline) {
			console.error("✗ Monitor failed to start");
			try {
				const tail = readFileSync(MONITOR_ERR, "utf8").trim().split("\n").slice(-10);
				if (tail.length && tail[0]) console.error("  monitor.err:\n  " + tail.join("\n  "));
			} catch {}
			rmSync(MONITOR_JSON, { force: true });
			process.exit(1);
		}
		setTimeout(tick, 200);
	};
	tick();
}

// ---------------------------------------------------------------------
// CLI: stop
// ---------------------------------------------------------------------
function stopDaemon() {
	const info = readMonitor();
	if (isMonitorAlive(info)) {
		try { process.kill(info.pid); } catch {}
		rmSync(MONITOR_JSON, { force: true });
		console.log(`✓ Monitor stopped (pid ${info.pid})`);
	} else {
		if (info) rmSync(MONITOR_JSON, { force: true }); // clean stale file
		console.log("Monitor not running");
	}
}

// ---------------------------------------------------------------------
// CLI: status
// ---------------------------------------------------------------------
function countAndSize(path) {
	if (!existsSync(path)) return { lines: 0, bytes: 0 };
	const bytes = statSync(path).size;
	const lines = readFileSync(path, "utf8").split("\n").filter(Boolean).length;
	return { lines, bytes };
}

function statusDaemon() {
	const info = readMonitor();
	if (isMonitorAlive(info)) {
		const c = countAndSize(CONSOLE_LOG);
		const n = countAndSize(NETWORK_LOG);
		console.log(`✓ Monitor running (pid ${info.pid})`);
		console.log(`  started: ${new Date(info.startedAt).toISOString()}`);
		console.log(`  console.jsonl: ${c.lines} events (${(c.bytes / 1024).toFixed(1)} KB)`);
		console.log(`  network.jsonl: ${n.lines} events (${(n.bytes / 1024).toFixed(1)} KB)`);
	} else {
		console.log("✗ Monitor not running");
		if (info) console.log("  (stale monitor.json present — a previous daemon ended)");
	}
}

// ---------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------
const cmd = process.argv[2];
if (cmd === "__daemon") {
	await runDaemon();
} else if (cmd === "start") {
	await startDaemon();
} else if (cmd === "stop") {
	stopDaemon();
} else if (cmd === "status") {
	statusDaemon();
} else {
	console.log("Usage: browser-monitor.js <start|stop|status>");
	console.log("\nStart a background daemon that records console and network");
	console.log("events from the browser on :9222 to log files.");
	process.exit(cmd ? 1 : 0);
}
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-monitor.js`

- [ ] **Step 3: Verify `start` fails clearly when the browser is down**

If Chromium is running, skip this step. Otherwise run `chromium-tools/browser-monitor.js start`
Expected: `✗ Chromium is not running on :9222` / `  Run: browser-start.js`, exit 1.

- [ ] **Step 4: Verify `start` then `status`**

Run: `chromium-tools/browser-monitor.js start`
Expected: `✓ Monitor started (pid <N>)`

Run: `chromium-tools/browser-monitor.js status`
Expected: `✓ Monitor running (pid <N>)` with `started:` and two log lines showing `0 events`.

- [ ] **Step 5: Verify capture and the start-twice guard**

Run: `chromium-tools/browser-nav.js http://localhost:8123/`
Wait ~1s for the fixture's delayed error, then run: `chromium-tools/browser-monitor.js status`
Expected: `console.jsonl` shows ≥ 3 events, `network.jsonl` shows ≥ 2 events.

Run: `chromium-tools/browser-monitor.js start` again
Expected: `✓ Monitor already running (pid <N>)` — same pid, exit 0. (Logs were not cleared: a following `status` still shows the captured events.)

- [ ] **Step 6: Verify stale detection and `stop`**

Run: `kill -9 (cat ~/.cache/browser-tools/monitor.json | python3 -c "import sys,json; print(json.load(sys.stdin)['pid'])")`
Wait 16s (heartbeat must go stale), then run: `chromium-tools/browser-monitor.js status`
Expected: `✗ Monitor not running` + `(stale monitor.json present — a previous daemon ended)`.

Run: `chromium-tools/browser-monitor.js stop`
Expected: `Monitor not running` (and `monitor.json` is removed).

- [ ] **Step 7: Commit**

```bash
git add chromium-tools/browser-monitor.js
git commit -m "Add browser-monitor.js collector daemon"
```

---

## Task 3: Console query (`browser-console.js`)

**Files:**
- Create: `chromium-tools/browser-console.js`

- [ ] **Step 1: Write `browser-console.js`**

```javascript
#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { CONSOLE_LOG, isMonitorAlive } from "./lib.js";

const args = process.argv.slice(2);
const errorsOnly = args.includes("--errors");
const limIdx = args.indexOf("--limit");
const limit = limIdx !== -1 ? parseInt(args[limIdx + 1], 10) : null;

if (limIdx !== -1 && (!limit || limit < 1)) {
	console.error("✗ --limit needs a positive number");
	process.exit(1);
}

if (!existsSync(CONSOLE_LOG)) {
	console.error("✗ No console log found.");
	console.error("  Run: browser-monitor.js start");
	process.exit(1);
}

let events = readFileSync(CONSOLE_LOG, "utf8")
	.split("\n")
	.filter(Boolean)
	.map((l) => { try { return JSON.parse(l); } catch { return null; } })
	.filter(Boolean);

if (errorsOnly) {
	events = events.filter((e) => e.type === "error" || e.type === "warning" || e.type === "warn");
}
if (limit) events = events.slice(-limit);

for (const e of events) {
	const loc = e.location ? ` (${e.location})` : "";
	console.log(`[${e.type}] ${e.text}${loc}`);
}
if (events.length === 0) console.log("(no matching console entries)");

if (!isMonitorAlive()) {
	console.error("");
	console.error("⚠ Monitor not running — entries above are from a previous session.");
	console.error("  Run: browser-monitor.js start");
}
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-console.js`

- [ ] **Step 3: Verify against a fresh capture**

Run: `chromium-tools/browser-monitor.js start`
Run: `chromium-tools/browser-nav.js http://localhost:8123/` then wait ~1s.

Run: `chromium-tools/browser-console.js`
Expected: lines including `[log] fixture loaded`, `[warning] a sample warning`, `[error] a sample error`, and `[error] uncaught fixture error`.

Run: `chromium-tools/browser-console.js --errors`
Expected: only the warning and the two error lines — not `fixture loaded`.

Run: `chromium-tools/browser-console.js --limit 1`
Expected: exactly one line (the most recent entry).

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/browser-console.js
git commit -m "Add browser-console.js for querying captured console output"
```

---

## Task 4: Network query (`browser-network.js`)

**Files:**
- Create: `chromium-tools/browser-network.js`

- [ ] **Step 1: Write `browser-network.js`**

```javascript
#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { NETWORK_LOG, isMonitorAlive } from "./lib.js";

const args = process.argv.slice(2);
const failedOnly = args.includes("--failed");
const limIdx = args.indexOf("--limit");
const limit = limIdx !== -1 ? parseInt(args[limIdx + 1], 10) : null;

if (limIdx !== -1 && (!limit || limit < 1)) {
	console.error("✗ --limit needs a positive number");
	process.exit(1);
}

if (!existsSync(NETWORK_LOG)) {
	console.error("✗ No network log found.");
	console.error("  Run: browser-monitor.js start");
	process.exit(1);
}

let events = readFileSync(NETWORK_LOG, "utf8")
	.split("\n")
	.filter(Boolean)
	.map((l) => { try { return JSON.parse(l); } catch { return null; } })
	.filter(Boolean);

// A failure is a requestfailed entry, or a response with status >= 400.
// 304 (Not Modified) and 1xx are not failures.
if (failedOnly) {
	events = events.filter((e) => e.errorText || (typeof e.status === "number" && e.status >= 400));
}
if (limit) events = events.slice(-limit);

for (const e of events) {
	if (e.errorText) {
		console.log(`FAILED ${e.method || "?"} ${e.url || "?"} — ${e.errorText}`);
	} else {
		const kb = ((e.size || 0) / 1024).toFixed(1);
		const ms = e.timingMs ?? "?";
		console.log(`${e.status} ${e.method} ${e.url} [${e.resourceType}, ${kb} KB, ${ms} ms]`);
	}
}
if (events.length === 0) console.log("(no matching network entries)");

if (!isMonitorAlive()) {
	console.error("");
	console.error("⚠ Monitor not running — entries above are from a previous session.");
	console.error("  Run: browser-monitor.js start");
}
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-network.js`

- [ ] **Step 3: Verify against a fresh capture**

Run: `chromium-tools/browser-monitor.js start`
Run: `chromium-tools/browser-nav.js http://localhost:8123/` then wait ~1s.

Run: `chromium-tools/browser-network.js`
Expected: a `200 GET http://localhost:8123/ [...]` line and a line for `/missing-endpoint`.

Run: `chromium-tools/browser-network.js --failed`
Expected: only the `/missing-endpoint` request (status 404, or a `FAILED` line) — the 200 for `/` is excluded.

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/browser-network.js
git commit -m "Add browser-network.js for querying captured network activity"
```

---

## Task 5: Click (`browser-click.js`)

**Files:**
- Create: `chromium-tools/browser-click.js`

- [ ] **Step 1: Write `browser-click.js`**

```javascript
#!/usr/bin/env node

import { connect } from "./lib.js";

const selector = process.argv[2];
if (!selector) {
	console.log("Usage: browser-click.js <selector>");
	console.log("\nExample:");
	console.log('  browser-click.js "#submit"');
	process.exit(1);
}

const b = await connect();
const p = (await b.pages()).at(-1); // last open tab, as every script does

if (!p) {
	console.error("✗ No active tab found");
	process.exit(1);
}

try {
	await p.waitForSelector(selector, { timeout: 5000 });
} catch {
	console.error(`✗ Selector not found: ${selector}`);
	await b.disconnect();
	process.exit(1);
}

await p.click(selector);
console.log(`✓ Clicked: ${selector}`);

await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-click.js`

- [ ] **Step 3: Verify success and not-found**

Run: `chromium-tools/browser-nav.js http://localhost:8123/`

Run: `chromium-tools/browser-click.js "#go"`
Expected: `✓ Clicked: #go`

Run: `chromium-tools/browser-click.js "#does-not-exist"`
Expected: `✗ Selector not found: #does-not-exist`, exit 1 (after ~5s).

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/browser-click.js
git commit -m "Add browser-click.js for clicking elements by selector"
```

---

## Task 6: Type (`browser-type.js`)

**Files:**
- Create: `chromium-tools/browser-type.js`

- [ ] **Step 1: Write `browser-type.js`**

```javascript
#!/usr/bin/env node

import { connect } from "./lib.js";

const args = process.argv.slice(2);
const clear = args.includes("--clear");
const enter = args.includes("--enter");
const positional = args.filter((a) => !a.startsWith("--"));
const selector = positional[0];
const text = positional.slice(1).join(" ");

if (!selector || !text) {
	console.log("Usage: browser-type.js <selector> <text> [--clear] [--enter]");
	console.log("\nExamples:");
	console.log('  browser-type.js "#search" "hello world"');
	console.log('  browser-type.js "#search" "hello" --clear --enter');
	process.exit(1);
}

const b = await connect();
const p = (await b.pages()).at(-1); // last open tab, as every script does

if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

try {
	await p.waitForSelector(selector, { timeout: 5000 });
} catch {
	console.error(`✗ Selector not found: ${selector}`);
	await b.disconnect();
	process.exit(1);
}

try {
	if (clear) {
		await p.click(selector, { clickCount: 3 }); // select existing content
		await p.keyboard.press("Backspace");
	}
	await p.type(selector, text);
	if (enter) await p.keyboard.press("Enter");
} catch (err) {
	console.error(`✗ Type failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`✓ Typed into ${selector}${clear ? " (cleared first)" : ""}${enter ? " + Enter" : ""}`);

await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-type.js`

- [ ] **Step 3: Verify typing, clear, and not-found**

Run: `chromium-tools/browser-nav.js http://localhost:8123/`

Run: `chromium-tools/browser-type.js "#q" "hello world"`
Expected: `✓ Typed into #q`

Run: `chromium-tools/browser-eval.js 'document.querySelector("#q").value'`
Expected: `hello world`

Run: `chromium-tools/browser-type.js "#q" "replaced" --clear`
Run: `chromium-tools/browser-eval.js 'document.querySelector("#q").value'`
Expected: `replaced` (not `hello worldreplaced`).

Run: `chromium-tools/browser-type.js "#nope" "x"`
Expected: `✗ Selector not found: #nope`, exit 1.

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/browser-type.js
git commit -m "Add browser-type.js for typing into fields"
```

---

## Task 7: Performance trace (`browser-trace.js`)

**Files:**
- Create: `chromium-tools/browser-trace.js`

- [ ] **Step 1: Write `browser-trace.js`**

```javascript
#!/usr/bin/env node

import { connect } from "./lib.js";

const url = process.argv[2];

const b = await connect();
const p = (await b.pages()).at(-1); // last open tab, as every script does

if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

let m;
try {
	// Register the LCP observer BEFORE navigation so it is live from the
	// first frame — a one-shot read after load misses LCP.
	await p.evaluateOnNewDocument(() => {
		window.__lcp = 0;
		try {
			new PerformanceObserver((list) => {
				for (const e of list.getEntries()) window.__lcp = e.startTime;
			}).observe({ type: "largest-contentful-paint", buffered: true });
		} catch {}
	});

	if (url) {
		await p.goto(url, { waitUntil: "load" });
	} else {
		await p.reload({ waitUntil: "load" });
	}

	// Settle for a late LCP candidate before reading.
	await new Promise((r) => setTimeout(r, 1000));

	m = await p.evaluate(() => {
		const nav = performance.getEntriesByType("navigation")[0] || {};
		const paint = performance.getEntriesByType("paint");
		const fcp = paint.find((e) => e.name === "first-contentful-paint");
		const res = performance.getEntriesByType("resource");
		const slowest = res
			.map((r) => ({ url: r.name, ms: Math.round(r.duration), size: r.transferSize || 0 }))
			.sort((a, b) => b.ms - a.ms)
			.slice(0, 5);
		const totalBytes = res.reduce((s, r) => s + (r.transferSize || 0), 0);
		return {
			ttfb: nav.responseStart ? Math.round(nav.responseStart) : null,
			fcp: fcp ? Math.round(fcp.startTime) : null,
			lcp: Math.round(window.__lcp || 0),
			dcl: nav.domContentLoadedEventEnd ? Math.round(nav.domContentLoadedEventEnd) : null,
			load: nav.loadEventEnd ? Math.round(nav.loadEventEnd) : null,
			count: res.length,
			totalKB: Math.round(totalBytes / 1024),
			slowest,
		};
	});
} catch (err) {
	console.error(`✗ Trace failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`URL: ${p.url()}`);
console.log(`TTFB:                     ${m.ttfb ?? "?"} ms`);
console.log(`First Contentful Paint:   ${m.fcp ?? "?"} ms`);
console.log(`Largest Contentful Paint: ${m.lcp || "?"} ms (LCP at capture time)`);
console.log(`DOMContentLoaded:         ${m.dcl ?? "?"} ms`);
console.log(`Load:                     ${m.load ?? "?"} ms`);
console.log(`Requests:                 ${m.count} (${m.totalKB} KB total)`);
console.log("Slowest requests:");
for (const r of m.slowest) {
	console.log(`  ${r.ms} ms  ${(r.size / 1024).toFixed(1)} KB  ${r.url}`);
}

await b.disconnect();
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x chromium-tools/browser-trace.js`

- [ ] **Step 3: Verify against the fixture and a real URL**

Run: `chromium-tools/browser-trace.js http://localhost:8123/`
Expected: a summary block — `TTFB`, `First Contentful Paint`, `Largest Contentful Paint`, `DOMContentLoaded`, `Load`, `Requests`, and a `Slowest requests:` list. Metric values are small positive numbers (the fixture is tiny).

Run: `chromium-tools/browser-trace.js https://example.com`
Expected: the same summary with populated, plausible values for a real page.

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/browser-trace.js
git commit -m "Add browser-trace.js for page performance summaries"
```

---

## Task 8: Document the new tools in `SKILL.md`

**Files:**
- Modify: `chromium-tools/SKILL.md`

- [ ] **Step 1: Update the frontmatter description**

Replace this line:

```
description: Interactive Chromium browser automation via Chrome DevTools Protocol. Use when you need to interact with web pages, test frontends, or when user interaction with a visible browser is required.
```

with:

```
description: Interactive Chromium browser automation and debugging via Chrome DevTools Protocol. Use when you need to interact with web pages, test frontends, capture console and network activity, or when user interaction with a visible browser is required.
```

- [ ] **Step 2: Insert the new tool sections**

In `SKILL.md`, find the `## When to Use` heading. Immediately **before** it, insert the following block:

````markdown
## Monitor Console & Network

```bash
{baseDir}/browser-monitor.js start    # begin capturing
{baseDir}/browser-monitor.js status   # is it running? event counts
{baseDir}/browser-monitor.js stop     # stop capturing
```

Console and network events are live streams — Chrome does not replay history to a newly connected client. Start the monitor *before* the activity you want to capture. It runs as a background daemon attached to the browser on `:9222`, recording console messages, uncaught errors, and network activity to log files. `start` clears previous logs, so each session is clean.

## Console Messages

```bash
{baseDir}/browser-console.js              # all captured console output
{baseDir}/browser-console.js --errors     # errors and warnings only
{baseDir}/browser-console.js --limit 20   # last 20 entries
```

Print console messages and uncaught JavaScript errors captured by the monitor. Run `browser-monitor.js start` first.

## Network Activity

```bash
{baseDir}/browser-network.js              # all captured requests
{baseDir}/browser-network.js --failed     # failures and HTTP >= 400 only
{baseDir}/browser-network.js --limit 20   # last 20 entries
```

Print network requests captured by the monitor: method, status, type, size, timing. Run `browser-monitor.js start` first.

## Click

```bash
{baseDir}/browser-click.js "#submit"
```

Wait for a CSS selector (5s) and click it.

## Type

```bash
{baseDir}/browser-type.js "#search" "hello world"
{baseDir}/browser-type.js "#search" "hello" --clear --enter
```

Wait for a CSS selector, then type text into it. `--clear` empties the field first; `--enter` presses Enter after.

## Performance Trace

```bash
{baseDir}/browser-trace.js https://example.com
{baseDir}/browser-trace.js                       # reload current tab
```

Navigate (or reload the current tab) and print a performance summary: TTFB, First/Largest Contentful Paint, DOMContentLoaded, Load, request count, total transfer size, and the 5 slowest requests.

## Debugging Workflow

```bash
{baseDir}/browser-start.js
{baseDir}/browser-monitor.js start
{baseDir}/browser-nav.js https://your-app.example
# ... interact: browser-click.js / browser-type.js / browser-eval.js ...
{baseDir}/browser-console.js --errors
{baseDir}/browser-network.js --failed
{baseDir}/browser-monitor.js stop
```

The monitor attaches to one running Chromium. **If you restart Chromium, restart the monitor too** — `browser-monitor.js status` shows it as not running after a browser restart.

````

- [ ] **Step 3: Verify the file**

Run: `head -3 chromium-tools/SKILL.md && grep -c '^## ' chromium-tools/SKILL.md`
Expected: frontmatter intact; the `## ` heading count increased by 7 (Monitor, Console, Network, Click, Type, Performance Trace, Debugging Workflow).

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/SKILL.md
git commit -m "Document monitor, console, network, click, type, trace tools in SKILL.md"
```

---

## Final Verification

- [ ] **Step 1: Full debugging workflow end to end**

```bash
chromium-tools/browser-start.js
chromium-tools/browser-monitor.js start
chromium-tools/browser-nav.js http://localhost:8123/
sleep 1
chromium-tools/browser-console.js --errors
chromium-tools/browser-network.js --failed
chromium-tools/browser-type.js "#q" "search term" --enter
chromium-tools/browser-click.js "#go"
chromium-tools/browser-trace.js http://localhost:8123/
chromium-tools/browser-monitor.js status
chromium-tools/browser-monitor.js stop
```

Expected: console shows the warning + two errors; network shows the 404; type and click succeed; trace prints a full summary; status shows the daemon running then stop ends it.

- [ ] **Step 2: Syntax-check every script**

Run: `cd chromium-tools && for f in browser-*.js lib.js; do node --check "$f" && echo "ok: $f"; done`
Expected: `ok:` for all eight files (`lib.js` + seven `browser-*.js`, including the six new ones).

- [ ] **Step 3: Stop the fixture server**

Stop the background `python3 -m http.server` process started in Setup.

---

## Self-Review Notes

Checked against the spec on 2026-05-17:

- **Spec coverage:** `monitor.json` + heartbeat liveness (Task 1 `isMonitorAlive`, Task 2 daemon), exclusive-create lock before clearing logs (Task 2 `startDaemon`), `monitor.err` startup diagnostics (Task 2), `target.type() === "page"` filter (Task 2), one synchronous whole-line append (Task 2 `logConsole`/`logNetwork`), `requestId`/`ts`/`size` schema (Task 2 CDP handlers), `--failed` = requestfailed + status ≥ 400 excluding 304/1xx (Task 4), `--limit` tail (Tasks 3–4), pre-navigation LCP observer + settle (Task 7), `.at(-1)` last-open-tab (Tasks 5–7), Chromium-restart caveat (Task 8 workflow), failure-path tests (Tasks 2–7 verification steps). All covered.
- **Placeholder scan:** none — every step has complete code or an exact command.
- **Type consistency:** the event schemas written by `browser-monitor.js` (`type`, `text`, `location`, `status`, `errorText`, `size`, `timingMs`, `resourceType`) match the fields read by `browser-console.js` and `browser-network.js`. `lib.js` export names match every importing script.
