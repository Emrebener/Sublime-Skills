#!/usr/bin/env node

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, cpSync } from "node:fs";
import { basename, join } from "node:path";
import { homedir, platform } from "node:os";
import puppeteer from "puppeteer";
import { CACHE_DIR } from "./lib.js";

const useProfile = process.argv[2] === "--profile";

if (process.argv[2] && process.argv[2] !== "--profile") {
	console.log("Usage: browser-start.js [--profile]");
	console.log("\nOptions:");
	console.log("  --profile  Copy your default Chrome/Chromium profile (cookies, logins)");
	process.exit(1);
}

// Locate the user's real browser profile directory, for --profile.
function findUserProfile() {
	const home = homedir();
	let candidates;
	if (platform() === "darwin") {
		candidates = [
			`${home}/Library/Application Support/Google/Chrome`,
			`${home}/Library/Application Support/Chromium`,
		];
	} else if (platform() === "win32") {
		const local = process.env.LOCALAPPDATA || "";
		candidates = [
			`${local}\\Google\\Chrome\\User Data`,
			`${local}\\Chromium\\User Data`,
		];
	} else {
		candidates = [
			`${home}/.config/google-chrome`,
			`${home}/.config/chromium`,
		];
	}
	return candidates.find((c) => existsSync(c)) || null;
}

// Names skipped when copying a profile: lock/socket files and session state.
const EXCLUDE_NAMES = new Set([
	"SingletonLock",
	"SingletonSocket",
	"SingletonCookie",
	"Current Session",
	"Current Tabs",
	"Last Session",
	"Last Tabs",
]);

function profileFilter(src) {
	if (EXCLUDE_NAMES.has(basename(src))) return false;
	if (src.split(/[\\/]/).includes("Sessions")) return false;
	return true;
}

// Check if already running on :9222
try {
	const browser = await puppeteer.connect({
		browserURL: "http://localhost:9222",
		defaultViewport: null,
	});
	await browser.disconnect();
	console.log("✓ Browser already running on :9222");
	process.exit(0);
} catch {}

// The bundled Chromium downloaded by `npm install`.
const binary = puppeteer.executablePath();
if (!existsSync(binary)) {
	console.error("✗ Bundled Chromium not found");
	console.error("  Run: npm install");
	process.exit(1);
}

if (useProfile) {
	const userProfile = findUserProfile();
	if (!userProfile) {
		console.error("✗ No Chrome/Chromium profile found to copy");
		process.exit(1);
	}
	console.log("Syncing profile...");
	// Wipe any stale copy, recreate an empty dir, then mirror the user
	// profile into it. cpSync (no shell) works on every platform.
	rmSync(CACHE_DIR, { recursive: true, force: true });
	mkdirSync(CACHE_DIR, { recursive: true });
	cpSync(userProfile, CACHE_DIR, { recursive: true, filter: profileFilter });
} else {
	mkdirSync(CACHE_DIR, { recursive: true });
	// Remove Singleton* lock files to allow a new instance
	for (const f of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
		try {
			rmSync(join(CACHE_DIR, f), { force: true });
		} catch {}
	}
}

// Start the bundled browser, detached, with remote debugging.
spawn(
	binary,
	[
		"--remote-debugging-port=9222",
		`--user-data-dir=${CACHE_DIR}`,
		"--no-first-run",
		"--no-default-browser-check",
	],
	{ detached: true, stdio: "ignore" },
).unref();

// Wait for the browser to be ready
let connected = false;
for (let i = 0; i < 30; i++) {
	try {
		const b = await puppeteer.connect({
			browserURL: "http://localhost:9222",
			defaultViewport: null,
		});
		await b.disconnect();
		connected = true;
		break;
	} catch {
		await new Promise((r) => setTimeout(r, 500));
	}
}

if (!connected) {
	console.error("✗ Failed to connect to browser");
	process.exit(1);
}

console.log(`✓ Browser started on :9222 (bundled Chromium)${useProfile ? " with your profile" : ""}`);
