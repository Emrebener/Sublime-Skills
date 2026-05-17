#!/usr/bin/env node

import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { platform } from "node:os";
import puppeteer from "puppeteer-core";

const useProfile = process.argv[2] === "--profile";

if (process.argv[2] && process.argv[2] !== "--profile") {
	console.log("Usage: browser-start.js [--profile]");
	console.log("\nOptions:");
	console.log("  --profile  Copy your default Chromium profile (cookies, logins)");
	process.exit(1);
}

const SCRAPING_DIR = `${process.env.HOME}/.cache/browser-tools`;
const os = platform();

// Locate a browser binary. Chromium is preferred; Chrome is a fallback.
// Each candidate pairs an executable with its profile source directory.
function findBrowser() {
	const home = process.env.HOME;
	let candidates;

	if (os === "darwin") {
		candidates = [
			{ bin: "/Applications/Chromium.app/Contents/MacOS/Chromium", profile: `${home}/Library/Application Support/Chromium` },
			{ bin: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", profile: `${home}/Library/Application Support/Google/Chrome` },
		];
	} else if (os === "win32") {
		const pf = process.env["ProgramFiles"] || "C:\\Program Files";
		const local = process.env["LOCALAPPDATA"] || "";
		candidates = [
			{ bin: `${pf}\\Chromium\\Application\\chrome.exe`, profile: `${local}\\Chromium\\User Data` },
			{ bin: `${pf}\\Google\\Chrome\\Application\\chrome.exe`, profile: `${local}\\Google\\Chrome\\User Data` },
		];
	} else {
		// Linux: probe well-known absolute paths, Chromium first.
		const chromiumProfile = `${home}/.config/chromium`;
		const chromeProfile = `${home}/.config/google-chrome`;
		candidates = [
			{ bin: "/usr/bin/chromium", profile: chromiumProfile },
			{ bin: "/usr/bin/chromium-browser", profile: chromiumProfile },
			{ bin: "/snap/bin/chromium", profile: chromiumProfile },
			{ bin: "/usr/bin/google-chrome", profile: chromeProfile },
			{ bin: "/usr/bin/google-chrome-stable", profile: chromeProfile },
		];
	}

	return candidates.find((c) => existsSync(c.bin)) || null;
}

// Check if already running on :9222
try {
	const browser = await puppeteer.connect({
		browserURL: "http://localhost:9222",
		defaultViewport: null,
	});
	await browser.disconnect();
	console.log("✓ Chrome already running on :9222");
	process.exit(0);
} catch {}

const browser = findBrowser();
if (!browser) {
	console.error("✗ No Chromium or Chrome binary found");
	console.error("  Install Chromium, e.g. (Linux): sudo apt install chromium");
	process.exit(1);
}

// Setup profile directory
mkdirSync(SCRAPING_DIR, { recursive: true });

// Remove Singleton* lock files to allow a new instance
for (const f of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
	try {
		rmSync(`${SCRAPING_DIR}/${f}`, { force: true });
	} catch {}
}

if (useProfile) {
	if (!existsSync(browser.profile)) {
		console.error(`✗ Profile directory not found: ${browser.profile}`);
		process.exit(1);
	}
	console.log("Syncing profile...");
	// execFileSync (no shell) avoids any command-injection surface.
	execFileSync(
		"rsync",
		[
			"-a",
			"--delete",
			"--exclude=SingletonLock",
			"--exclude=SingletonSocket",
			"--exclude=SingletonCookie",
			"--exclude=*/Sessions/*",
			"--exclude=*/Current Session",
			"--exclude=*/Current Tabs",
			"--exclude=*/Last Session",
			"--exclude=*/Last Tabs",
			`${browser.profile}/`,
			`${SCRAPING_DIR}/`,
		],
		{ stdio: "pipe" },
	);
}

// Start the browser with flags to force a new instance
spawn(
	browser.bin,
	[
		"--remote-debugging-port=9222",
		`--user-data-dir=${SCRAPING_DIR}`,
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

console.log(`✓ Browser started on :9222 (${browser.bin})${useProfile ? " with your profile" : ""}`);
