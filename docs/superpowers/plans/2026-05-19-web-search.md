# web-search Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `web-search`, a dependency-free Node.js CLI skill that queries a self-hosted SearXNG instance's JSON API and returns ranked web-search results for AI agents in MCP-free harnesses.

**Architecture:** Pure logic (endpoint resolution, arg parsing, URL building, result formatting) lives in `lib.js` and is unit-tested with `node:test`. `search.js` is the thin CLI entry point that wires those helpers to a single `fetch` call. No third-party dependencies — Node's built-in global `fetch` (Node 18+) is the only network primitive, so there is no `npm install` step.

**Tech Stack:** Node.js (ESM, top-level await), built-in `fetch`, built-in `node:test`.

**Spec:** `docs/superpowers/specs/2026-05-19-web-search-design.md`

---

## File Structure

All paths under `web-search/` unless noted.

**Created:**
- `package.json` — minimal: `"type": "module"`, no dependencies
- `.gitignore` — ignores the user-local `config.json`
- `config.example.json` — committed template for the endpoint config
- `lib.js` — pure helpers: `resolveEndpoint`, `parseArgs`, `buildSearchUrl`, `formatResults`
- `search.js` — CLI entry point
- `SKILL.md` — skill instructions
- `test/lib.test.js` — `node:test` unit tests for `lib.js`
- `test/smoke.sh` — live end-to-end query against the configured instance

**Modified:**
- `README.md` (repo root) — add a `web-search` entry under "Skills"

---

## Task 1: Scaffold the skill directory

Create the static files: the package manifest, gitignore, and config template. No code logic yet.

**Files:**
- Create: `web-search/package.json`
- Create: `web-search/.gitignore`
- Create: `web-search/config.example.json`

- [ ] **Step 1: Create `web-search/package.json`**

```json
{
	"name": "web-search",
	"version": "1.0.0",
	"description": "SearXNG-backed web search for AI agents",
	"type": "module",
	"private": true
}
```

The `"type": "module"` line is required so the `.js` files are treated as ESM (allowing `import`/`export` and top-level `await`). There are no dependencies, so no `npm install` is ever needed.

- [ ] **Step 2: Create `web-search/.gitignore`**

```
config.json
```

`config.json` holds a user-specific SearXNG address and must never be committed.

- [ ] **Step 3: Create `web-search/config.example.json`**

```json
{
	"searxng_url": "http://localhost:8080"
}
```

This is the copy-me template. A user without the `SEARXNG_URL` env var copies this to `config.json` and edits the URL.

- [ ] **Step 4: Verify the files are valid JSON**

Run: `cd web-search && node -e "JSON.parse(require('fs').readFileSync('package.json')); JSON.parse(require('fs').readFileSync('config.example.json')); console.log('valid')"`
Expected: prints `valid`.

- [ ] **Step 5: Commit**

```bash
git add web-search/package.json web-search/.gitignore web-search/config.example.json
git commit -m "feat(web-search): scaffold skill directory"
```

---

## Task 2: `resolveEndpoint` in `lib.js`

Resolves the SearXNG base URL from the environment or a config file.

**Files:**
- Create: `web-search/lib.js`
- Create: `web-search/test/lib.test.js`

- [ ] **Step 1: Write the failing test**

Create `web-search/test/lib.test.js`:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { resolveEndpoint } from "../lib.js";

test("resolveEndpoint: SEARXNG_URL env var wins", () => {
	const dir = mkdtempSync(join(tmpdir(), "ws-"));
	try {
		assert.equal(resolveEndpoint({ SEARXNG_URL: "http://x:8080" }, dir), "http://x:8080");
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test("resolveEndpoint: strips a trailing slash", () => {
	assert.equal(resolveEndpoint({ SEARXNG_URL: "http://x:8080/" }, "/nonexistent-dir"), "http://x:8080");
});

test("resolveEndpoint: falls back to config.json when env var unset", () => {
	const dir = mkdtempSync(join(tmpdir(), "ws-"));
	try {
		writeFileSync(join(dir, "config.json"), JSON.stringify({ searxng_url: "http://cfg:9090" }));
		assert.equal(resolveEndpoint({}, dir), "http://cfg:9090");
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test("resolveEndpoint: throws when nothing is configured", () => {
	const dir = mkdtempSync(join(tmpdir(), "ws-"));
	try {
		assert.throws(() => resolveEndpoint({}, dir), /No SearXNG endpoint configured/);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-search && node --test test/*.test.js`
Expected: FAIL — `lib.js` does not exist / `resolveEndpoint` is not exported.

- [ ] **Step 3: Create `web-search/lib.js` with `resolveEndpoint`**

```js
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Resolve the SearXNG base URL. Order: SEARXNG_URL env var, then a
// config.json in the skill directory, then throw. The returned URL has any
// trailing slash removed so request paths can be appended cleanly.
export function resolveEndpoint(env, skillDir) {
	let url = env.SEARXNG_URL;
	if (!url) {
		const cfgPath = join(skillDir, "config.json");
		if (existsSync(cfgPath)) {
			let parsed;
			try {
				parsed = JSON.parse(readFileSync(cfgPath, "utf8"));
			} catch {
				throw new Error(`config.json is not valid JSON: ${cfgPath}`);
			}
			url = parsed.searxng_url;
		}
	}
	if (!url) {
		throw new Error(
			"No SearXNG endpoint configured. Set the SEARXNG_URL environment " +
				"variable, or copy config.example.json to config.json and set searxng_url.",
		);
	}
	return url.replace(/\/+$/, "");
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-search && node --test test/*.test.js`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add web-search/lib.js web-search/test/lib.test.js
git commit -m "feat(web-search): resolveEndpoint helper"
```

---

## Task 3: `parseArgs` in `lib.js`

Parses CLI argv into a validated options object.

**Files:**
- Modify: `web-search/lib.js`
- Modify: `web-search/test/lib.test.js`

- [ ] **Step 1: Add failing tests**

Append to `web-search/test/lib.test.js`:

```js
import { parseArgs } from "../lib.js";

test("parseArgs: defaults with a single-word query", () => {
	const o = parseArgs(["hello"]);
	assert.equal(o.query, "hello");
	assert.equal(o.count, 10);
	assert.equal(o.category, "general");
	assert.equal(o.time, null);
	assert.equal(o.lang, "all");
	assert.equal(o.safe, "0");
	assert.equal(o.json, false);
});

test("parseArgs: joins a multi-word positional query", () => {
	assert.equal(parseArgs(["claude", "code", "review"]).query, "claude code review");
});

test("parseArgs: parses every flag", () => {
	const o = parseArgs([
		"q", "--count", "5", "--category", "news", "--time", "week",
		"--lang", "en-US", "--safe", "1", "--json",
	]);
	assert.equal(o.query, "q");
	assert.equal(o.count, 5);
	assert.equal(o.category, "news");
	assert.equal(o.time, "week");
	assert.equal(o.lang, "en-US");
	assert.equal(o.safe, "1");
	assert.equal(o.json, true);
});

test("parseArgs: rejects an unknown flag", () => {
	assert.throws(() => parseArgs(["q", "--bogus"]), /unknown flag: --bogus/);
});

test("parseArgs: rejects an invalid category", () => {
	assert.throws(() => parseArgs(["q", "--category", "music"]), /--category must be one of/);
});

test("parseArgs: rejects a non-positive --count", () => {
	assert.throws(() => parseArgs(["q", "--count", "0"]), /--count must be a positive integer/);
	assert.throws(() => parseArgs(["q", "--count", "abc"]), /--count must be a positive integer/);
});

test("parseArgs: rejects an invalid --safe value", () => {
	assert.throws(() => parseArgs(["q", "--safe", "9"]), /--safe must be 0, 1, or 2/);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd web-search && node --test test/*.test.js`
Expected: FAIL — `parseArgs` is not exported.

- [ ] **Step 3: Add `parseArgs` to `web-search/lib.js`**

Append to `web-search/lib.js`:

```js
const CATEGORIES = ["general", "news", "images", "videos"];
const TIME_RANGES = ["day", "week", "month", "year"];
const SAFE_LEVELS = ["0", "1", "2"];

// Parse the CLI argument array (everything after `node search.js`) into a
// validated options object. Throws Error on an unknown flag or bad value.
// Non-flag arguments are joined with spaces into the query.
export function parseArgs(argv) {
	const opts = {
		query: "",
		count: 10,
		category: "general",
		time: null,
		lang: "all",
		safe: "0",
		json: false,
	};
	const positional = [];
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--json") {
			opts.json = true;
		} else if (a === "--count") {
			const n = Number(argv[++i]);
			if (!Number.isInteger(n) || n < 1) {
				throw new Error("--count must be a positive integer");
			}
			opts.count = n;
		} else if (a === "--category") {
			const v = argv[++i];
			if (!CATEGORIES.includes(v)) {
				throw new Error(`--category must be one of: ${CATEGORIES.join(", ")}`);
			}
			opts.category = v;
		} else if (a === "--time") {
			const v = argv[++i];
			if (!TIME_RANGES.includes(v)) {
				throw new Error(`--time must be one of: ${TIME_RANGES.join(", ")}`);
			}
			opts.time = v;
		} else if (a === "--lang") {
			opts.lang = argv[++i];
		} else if (a === "--safe") {
			const v = argv[++i];
			if (!SAFE_LEVELS.includes(v)) {
				throw new Error("--safe must be 0, 1, or 2");
			}
			opts.safe = v;
		} else if (a.startsWith("--")) {
			throw new Error(`unknown flag: ${a}`);
		} else {
			positional.push(a);
		}
	}
	opts.query = positional.join(" ").trim();
	return opts;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd web-search && node --test test/*.test.js`
Expected: PASS — all tests pass (4 from Task 2 + 7 new).

- [ ] **Step 5: Commit**

```bash
git add web-search/lib.js web-search/test/lib.test.js
git commit -m "feat(web-search): parseArgs helper"
```

---

## Task 4: `buildSearchUrl` in `lib.js`

Builds the SearXNG JSON request URL from the parsed options.

**Files:**
- Modify: `web-search/lib.js`
- Modify: `web-search/test/lib.test.js`

- [ ] **Step 1: Add failing tests**

Append to `web-search/test/lib.test.js`:

```js
import { buildSearchUrl } from "../lib.js";

const baseOpts = { query: "hello", category: "general", lang: "all", safe: "0", time: null };

test("buildSearchUrl: sets the core query parameters", () => {
	const u = new URL(buildSearchUrl("http://x:8080", baseOpts));
	assert.equal(u.pathname, "/search");
	assert.equal(u.searchParams.get("q"), "hello");
	assert.equal(u.searchParams.get("format"), "json");
	assert.equal(u.searchParams.get("categories"), "general");
	assert.equal(u.searchParams.get("language"), "all");
	assert.equal(u.searchParams.get("safesearch"), "0");
});

test("buildSearchUrl: omits time_range when time is null", () => {
	const u = new URL(buildSearchUrl("http://x:8080", baseOpts));
	assert.equal(u.searchParams.has("time_range"), false);
});

test("buildSearchUrl: includes time_range when time is set", () => {
	const u = new URL(buildSearchUrl("http://x:8080", { ...baseOpts, time: "week" }));
	assert.equal(u.searchParams.get("time_range"), "week");
});

test("buildSearchUrl: URL-encodes the query", () => {
	const u = new URL(buildSearchUrl("http://x:8080", { ...baseOpts, query: "a & b=c" }));
	assert.equal(u.searchParams.get("q"), "a & b=c");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd web-search && node --test test/*.test.js`
Expected: FAIL — `buildSearchUrl` is not exported.

- [ ] **Step 3: Add `buildSearchUrl` to `web-search/lib.js`**

Append to `web-search/lib.js`:

```js
// Build the SearXNG JSON search request URL. `base` is the trailing-slash-free
// endpoint from resolveEndpoint; `opts` is the object from parseArgs. The URL
// API handles all parameter encoding.
export function buildSearchUrl(base, opts) {
	const u = new URL(base + "/search");
	u.searchParams.set("q", opts.query);
	u.searchParams.set("format", "json");
	u.searchParams.set("categories", opts.category);
	u.searchParams.set("language", opts.lang);
	u.searchParams.set("safesearch", opts.safe);
	if (opts.time) u.searchParams.set("time_range", opts.time);
	return u.toString();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd web-search && node --test test/*.test.js`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add web-search/lib.js web-search/test/lib.test.js
git commit -m "feat(web-search): buildSearchUrl helper"
```

---

## Task 5: `formatResults` in `lib.js`

Renders SearXNG's `results` array as text or JSON.

**Files:**
- Modify: `web-search/lib.js`
- Modify: `web-search/test/lib.test.js`

- [ ] **Step 1: Add failing tests**

Append to `web-search/test/lib.test.js`:

```js
import { formatResults } from "../lib.js";

const sampleResults = [
	{ title: "First", url: "http://a.com", content: "  alpha  ", engine: "google" },
	{ title: "Second", url: "http://b.com", content: "beta", engine: "bing" },
	{ title: "Third", url: "http://c.com", content: "gamma", engine: "ddg" },
];

test("formatResults: text format renders rank, title, url, snippet", () => {
	const out = formatResults(sampleResults, 10, false);
	assert.match(out, /1\. First/);
	assert.match(out, /http:\/\/a\.com/);
	assert.match(out, /alpha/);
	assert.match(out, /3\. Third/);
});

test("formatResults: truncates to count", () => {
	const out = formatResults(sampleResults, 2, false);
	assert.match(out, /2\. Second/);
	assert.equal(/3\. Third/.test(out), false);
});

test("formatResults: json format returns a parseable array", () => {
	const out = formatResults(sampleResults, 2, true);
	const arr = JSON.parse(out);
	assert.equal(arr.length, 2);
	assert.deepEqual(arr[0], {
		rank: 1, title: "First", url: "http://a.com", snippet: "alpha", engine: "google",
	});
});

test("formatResults: empty results give an empty string in text mode", () => {
	assert.equal(formatResults([], 10, false), "");
});

test("formatResults: empty results give '[]' in json mode", () => {
	assert.equal(formatResults([], 10, true), "[]");
});

test("formatResults: tolerates missing fields", () => {
	const out = formatResults([{ url: "http://x.com" }], 10, true);
	assert.deepEqual(JSON.parse(out)[0], {
		rank: 1, title: "", url: "http://x.com", snippet: "", engine: "",
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd web-search && node --test test/*.test.js`
Expected: FAIL — `formatResults` is not exported.

- [ ] **Step 3: Add `formatResults` to `web-search/lib.js`**

Append to `web-search/lib.js`:

```js
// Render SearXNG's `results` array. Takes the first `count` entries and
// returns either a human-readable text block or a JSON array string.
// Missing fields on a result are tolerated and become empty strings.
export function formatResults(results, count, asJson) {
	const top = results.slice(0, count).map((r, i) => ({
		rank: i + 1,
		title: r.title || "",
		url: r.url || "",
		snippet: (r.content || "").trim(),
		engine: r.engine || "",
	}));
	if (asJson) return JSON.stringify(top, null, 2);
	return top.map((r) => `${r.rank}. ${r.title}\n   ${r.url}\n   ${r.snippet}`).join("\n\n");
}
```

Note: `JSON.stringify([], null, 2)` is exactly the string `"[]"`, satisfying the empty-json test.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd web-search && node --test test/*.test.js`
Expected: PASS — all tests pass (the full `lib.js` suite).

- [ ] **Step 5: Commit**

```bash
git add web-search/lib.js web-search/test/lib.test.js
git commit -m "feat(web-search): formatResults helper"
```

---

## Task 6: `search.js` CLI entry point

Wires the `lib.js` helpers to a single `fetch` call, with full error handling.

**Files:**
- Create: `web-search/search.js`

- [ ] **Step 1: Create `web-search/search.js`**

```js
#!/usr/bin/env node

import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveEndpoint, parseArgs, buildSearchUrl, formatResults } from "./lib.js";

const SKILL_DIR = dirname(fileURLToPath(import.meta.url));
const USAGE =
	'Usage: search.js "<query>" [--count N] [--category general|news|images|videos]\n' +
	"          [--time day|week|month|year] [--lang LANG] [--safe 0|1|2] [--json]";

// --- parse arguments ---
let opts;
try {
	opts = parseArgs(process.argv.slice(2));
} catch (err) {
	console.error(`✗ ${err.message}`);
	console.error(USAGE);
	process.exit(1);
}
if (!opts.query) {
	console.error("✗ No search query given");
	console.error(USAGE);
	process.exit(1);
}

// --- resolve the SearXNG endpoint ---
let base;
try {
	base = resolveEndpoint(process.env, SKILL_DIR);
} catch (err) {
	console.error(`✗ ${err.message}`);
	process.exit(1);
}

// --- perform the request ---
const url = buildSearchUrl(base, opts);
let res;
try {
	const ctrl = new AbortController();
	const timer = setTimeout(() => ctrl.abort(), 15000);
	try {
		res = await fetch(url, { signal: ctrl.signal, headers: { Accept: "application/json" } });
	} finally {
		clearTimeout(timer);
	}
} catch (err) {
	console.error(`✗ Could not reach SearXNG at ${base}`);
	console.error(`  ${err.name === "AbortError" ? "Request timed out after 15s." : err.message}`);
	console.error("  The instance may be down or the configured URL may be wrong.");
	process.exit(1);
}

if (!res.ok) {
	console.error(`✗ SearXNG returned HTTP ${res.status}`);
	if (res.status === 403) {
		console.error("  The instance may not allow the JSON format. Ensure 'json' is");
		console.error("  listed under search.formats in SearXNG's settings.yml.");
	}
	process.exit(1);
}

// --- parse the response ---
let data;
const body = await res.text();
try {
	data = JSON.parse(body);
} catch {
	console.error("✗ SearXNG did not return JSON.");
	console.error("  Ensure 'json' is listed under search.formats in SearXNG's settings.yml.");
	process.exit(1);
}

// --- render ---
// SearXNG's `number_of_results` is unreliable (often 0); the `results` array
// is authoritative.
const results = Array.isArray(data.results) ? data.results : [];
if (!opts.json && results.length === 0) {
	console.log(`No results for: ${opts.query}`);
	process.exit(0);
}
console.log(formatResults(results, opts.count, opts.json));
```

- [ ] **Step 2: Make it executable**

Run: `cd web-search && chmod +x search.js`

- [ ] **Step 3: Verify the error paths without a configured endpoint**

Run: `cd web-search && env -u SEARXNG_URL node search.js "test"` (run from a state where no `config.json` exists)
Expected: prints `✗ No SearXNG endpoint configured...` and exits non-zero.

Run: `cd web-search && SEARXNG_URL=http://127.0.0.1:1 node search.js "test"`
Expected: prints `✗ Could not reach SearXNG at http://127.0.0.1:1` and exits non-zero.

Run: `cd web-search && node search.js --count 0 "test"`
Expected: prints `✗ --count must be a positive integer` and the usage line.

- [ ] **Step 4: Verify a live search against the real instance**

Run: `cd web-search && SEARXNG_URL=http://100.67.220.44:8080 node search.js "anthropic claude" --count 3`
Expected: a numbered list of 3 results, each with a title, a URL, and a snippet.

Run: `cd web-search && SEARXNG_URL=http://100.67.220.44:8080 node search.js "anthropic claude" --count 2 --json`
Expected: a JSON array of 2 objects with `rank`, `title`, `url`, `snippet`, `engine`.

(If the instance at `http://100.67.220.44:8080` is not reachable from the run environment, note it and rely on the Task 7 smoke test instead — the error-path checks in Step 3 still validate the script.)

- [ ] **Step 5: Commit**

```bash
git add web-search/search.js
git commit -m "feat(web-search): search.js CLI entry point"
```

---

## Task 7: `SKILL.md`, smoke test, and README entry

Documentation and the end-to-end smoke test.

**Files:**
- Create: `web-search/SKILL.md`
- Create: `web-search/test/smoke.sh`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Create `web-search/SKILL.md`**

```markdown
---
name: web-search
description: Web search for AI agents via a self-hosted SearXNG instance — an MCP-free search tool. Use this skill whenever you need to search the web, look something up online, find current information, research a topic, or get web results for a query, in any environment without a search MCP server.
---

# Web Search

A CLI tool that searches the web through a self-hosted
[SearXNG](https://docs.searxng.org/) instance and returns ranked results.
It is dependency-free — it needs only Node.js 18+ (for built-in `fetch`),
no `npm install`.

## Setup

The skill needs the URL of a running SearXNG instance. Provide it either way:

- Set the `SEARXNG_URL` environment variable, or
- Copy `config.example.json` to `config.json` (in this skill directory) and
  set `searxng_url`.

The environment variable takes precedence. `config.json` is git-ignored.

The SearXNG instance must have the JSON format enabled — `json` must be
listed under `search.formats` in its `settings.yml`.

## Search

```bash
{baseDir}/search.js "<query>"
```

Options:

- `--count N` — number of results to return (default 10).
- `--category general|news|images|videos` — result category (default general).
- `--time day|week|month|year` — restrict to recent results (default: all time).
- `--lang LANG` — language/region, e.g. `en`, `en-US`, `all` (default all).
- `--safe 0|1|2` — safe-search: 0 off, 1 moderate, 2 strict (default 0).
- `--json` — output a JSON array instead of text.

```bash
{baseDir}/search.js "rust async runtime comparison" --count 5
{baseDir}/search.js "openai news" --category news --time week
{baseDir}/search.js "claude api pricing" --json
```

Default output is a ranked list of `title / url / snippet`. With `--json`,
each result is an object with `rank`, `title`, `url`, `snippet`, `engine`.

## When to Use

- Looking up current or factual information on the web.
- Researching a topic, finding documentation, or finding source URLs.
- Any task that needs search-engine results.

To read the full content of a result page, use the `browser-tools` skill —
this skill only returns search results.
```

- [ ] **Step 2: Create `web-search/test/smoke.sh`**

```bash
#!/usr/bin/env bash
# End-to-end smoke test for web-search. Runs one live query against the
# configured SearXNG instance and checks a result with a URL comes back.
# Requires SEARXNG_URL to be set (or a config.json in the skill dir) and the
# instance to be reachable. Run from the web-search directory: ./test/smoke.sh
set -euo pipefail

cd "$(dirname "$0")/.."

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# Unit tests first.
node --test test/*.test.js >/dev/null && pass "lib unit tests" || fail "lib unit tests"

# Live text search.
OUT=$(node search.js "anthropic claude" --count 3)
case "$OUT" in
	*http*) pass "live search returned a result with a URL" ;;
	*) echo "  got: $OUT"; fail "live search returned no URL" ;;
esac

# Live JSON search.
JSON=$(node search.js "anthropic claude" --count 2 --json)
echo "$JSON" | node -e '
	let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
		const a = JSON.parse(s);
		if (!Array.isArray(a) || a.length < 1 || !a[0].url) { console.error("bad json"); process.exit(1); }
	});
' && pass "live --json search returned a valid array" || fail "live --json search"

echo "ALL SMOKE TESTS PASSED"
```

- [ ] **Step 3: Make the smoke test executable**

Run: `cd web-search && chmod +x test/smoke.sh`

- [ ] **Step 4: Run the smoke test**

Run: `cd web-search && SEARXNG_URL=http://100.67.220.44:8080 ./test/smoke.sh`
Expected: `PASS:` lines and a final `ALL SMOKE TESTS PASSED`. (If the instance is unreachable from the run environment, the unit-test line still passes; note the live-query result.)

- [ ] **Step 5: Add a `web-search` entry to `README.md`**

In the repo-root `README.md`, under the `## Skills` heading, add this entry after the `browser-tools` entry:

```markdown
### [web-search](web-search/)

Web search for AI agents via a self-hosted
[SearXNG](https://docs.searxng.org/) instance — a self-contained, MCP-free
search tool for harnesses that can't run MCP servers.

A single dependency-free CLI script that queries SearXNG's JSON API and
returns ranked results (`title / url / snippet`, or JSON). Supports result
count, category (general/news/images/videos), time range, language/region,
and safe-search level. The SearXNG endpoint is configured via the
`SEARXNG_URL` environment variable or a local `config.json`.
```

- [ ] **Step 6: Commit**

```bash
git add web-search/SKILL.md web-search/test/smoke.sh README.md
git commit -m "feat(web-search): SKILL.md, smoke test, and README entry"
```

---

## Self-Review Notes

- **Spec coverage:** Goal/architecture → Tasks 1-6. Configuration (env var → `config.json` → error, trailing-slash normalization, git-ignored `config.json`, committed example) → Task 1 (`.gitignore`, `config.example.json`) + Task 2 (`resolveEndpoint`). CLI `search.js` with all flags → Task 3 (`parseArgs`) + Task 6. SearXNG request params → Task 4 (`buildSearchUrl`). Text/JSON output → Task 5 (`formatResults`). Error handling (no endpoint, unreachable, non-JSON, empty results, timeout) → Task 6. Testing (unit + smoke) → Tasks 2-5 (unit) + Task 7 (smoke). README entry → Task 7.
- **No third-party dependencies:** confirmed — `search.js` uses only built-in `fetch`, `node:path`, `node:url`; `lib.js` uses only `node:fs`, `node:path`; tests use `node:test`. No `package.json` dependencies, no `npm install`.
- **Naming consistency:** `resolveEndpoint(env, skillDir)`, `parseArgs(argv)`, `buildSearchUrl(base, opts)`, `formatResults(results, count, asJson)`, and the `opts` object shape (`query`, `count`, `category`, `time`, `lang`, `safe`, `json`) are used identically across Tasks 2-6.
- **Node version:** `node --test test/*.test.js` (the explicit glob) is used throughout — a bare directory argument fails on Node 26.
