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
