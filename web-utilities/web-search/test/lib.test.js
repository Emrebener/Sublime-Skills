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
