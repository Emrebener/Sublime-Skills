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
