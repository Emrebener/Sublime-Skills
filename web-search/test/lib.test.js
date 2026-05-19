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
