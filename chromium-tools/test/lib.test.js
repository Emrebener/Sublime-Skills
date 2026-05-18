import test from "node:test";
import assert from "node:assert/strict";
import { extractSession } from "../lib.js";

test("extractSession: defaults to 'default' with no flag or env", () => {
	delete process.env.BROWSER_SESSION;
	const { session, rest } = extractSession(["nav", "https://x.com"]);
	assert.equal(session, "default");
	assert.deepEqual(rest, ["nav", "https://x.com"]);
});

test("extractSession: --session flag wins and is stripped from rest", () => {
	process.env.BROWSER_SESSION = "fromenv";
	const { session, rest } = extractSession(["--session", "work", "https://x.com"]);
	assert.equal(session, "work");
	assert.deepEqual(rest, ["https://x.com"]);
	delete process.env.BROWSER_SESSION;
});

test("extractSession: BROWSER_SESSION env used when no flag", () => {
	process.env.BROWSER_SESSION = "envsess";
	const { session, rest } = extractSession(["--errors"]);
	assert.equal(session, "envsess");
	assert.deepEqual(rest, ["--errors"]);
	delete process.env.BROWSER_SESSION;
});

import { resolveTarget } from "../lib.js";

test("resolveTarget: @eN token becomes a data-ct-ref selector", () => {
	assert.equal(resolveTarget("@e5"), '[data-ct-ref="e5"]');
});

test("resolveTarget: ordinary selectors pass through unchanged", () => {
	assert.equal(resolveTarget("#submit"), "#submit");
	assert.equal(resolveTarget("button.primary"), "button.primary");
});
