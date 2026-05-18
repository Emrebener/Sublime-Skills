#!/usr/bin/env node

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, cpSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { homedir, platform } from "node:os";
import { fileURLToPath } from "node:url";

// Preflight: dependencies must be installed before puppeteer/lib.js can be
// imported. A static import of a missing package fails at module
// resolution, so this check and the imports it guards are dynamic.
const SKILL_DIR = dirname(fileURLToPath(import.meta.url));
if (!existsSync(join(SKILL_DIR, "node_modules", "puppeteer"))) {
	console.error("✗ chromium-tools dependencies not installed");
	console.error(`  Run: cd "${SKILL_DIR}" && npm install`);
	process.exit(1);
}

const puppeteer = (await import("puppeteer")).default;
const lib = await import("./lib.js");
const { extractSession, profileDir, sessionDir, findFreePort, readRegistry, writeRegistry, pidAlive } = lib;

// Parse: browser-start.js [--profile] [--session NAME]
const { session, rest } = extractSession(process.argv.slice(2));
const useProfile = rest.includes("--profile");
const unknown = rest.filter((a) => a !== "--profile");
if (unknown.length) {
	console.log("Usage: browser-start.js [--profile] [--session NAME]");
	console.log("\nOptions:");
	console.log("  --profile       Copy your default Chrome/Chromium profile (cookies, logins)");
	console.log("  --session NAME  Name this browser session (default: \"default\")");
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
		candidates = [`${local}\\Google\\Chrome\\User Data`, `${local}\\Chromium\\User Data`];
	} else {
		candidates = [`${home}/.config/google-chrome`, `${home}/.config/chromium`];
	}
	return candidates.find((c) => existsSync(c)) || null;
}

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

// If this session is already registered and alive, nothing to do.
const reg = readRegistry();
if (reg[session] && pidAlive(reg[session].pid)) {
	try {
		const b = await puppeteer.connect({
			browserURL: `http://localhost:${reg[session].port}`,
			defaultViewport: null,
		});
		await b.disconnect();
		console.log(`✓ Session "${session}" already running on :${reg[session].port}`);
		process.exit(0);
	} catch {
		// Registered pid alive but not reachable — fall through and relaunch.
	}
}

const binary = puppeteer.executablePath();
if (!existsSync(binary)) {
	console.error("✗ Bundled Chromium not found");
	console.error("  Run: npm install");
	process.exit(1);
}

const profile = profileDir(session);

if (useProfile) {
	const userProfile = findUserProfile();
	if (!userProfile) {
		console.error("✗ No Chrome/Chromium profile found to copy");
		process.exit(1);
	}
	console.log("Syncing profile...");
	rmSync(profile, { recursive: true, force: true });
	mkdirSync(profile, { recursive: true });
	cpSync(userProfile, profile, { recursive: true, filter: profileFilter });
} else {
	mkdirSync(profile, { recursive: true });
	for (const f of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
		try {
			rmSync(join(profile, f), { force: true });
		} catch {}
	}
}

const port = await findFreePort(9222);

const child = spawn(
	binary,
	[
		`--remote-debugging-port=${port}`,
		`--user-data-dir=${profile}`,
		"--no-first-run",
		"--no-default-browser-check",
	],
	{ detached: true, stdio: "ignore" },
);
child.unref();

// Wait for the browser to accept connections.
let connected = false;
for (let i = 0; i < 30; i++) {
	try {
		const b = await puppeteer.connect({
			browserURL: `http://localhost:${port}`,
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

// Record the session. child.pid is the launcher; Chromium may fork, but
// the launcher process staying alive is a sufficient liveness signal and
// killing it terminates the browser.
mkdirSync(sessionDir(session), { recursive: true });
const reg2 = readRegistry();
reg2[session] = { port, pid: child.pid, userDataDir: profile, startedAt: Date.now() };
writeRegistry(reg2);

console.log(
	`✓ Session "${session}" started on :${port} (bundled Chromium)${useProfile ? " with your profile" : ""}`,
);
