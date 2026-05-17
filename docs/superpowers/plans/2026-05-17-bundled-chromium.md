# Bundled Chromium Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the `chromium-tools` skill from `puppeteer-core` to the full `puppeteer` package so `npm install` provisions its own Chromium — making the skill plug-and-play, especially on Windows.

**Architecture:** Replace the one dependency, update the eight files that import it, rewrite `browser-start.js` to launch puppeteer's bundled browser (and make `--profile` cross-platform via `fs.cpSync`), and update `SKILL.md`.

**Tech Stack:** Node.js (ESM), `puppeteer` (full package, bundles Chromium), Chrome DevTools Protocol.

---

## Reference

- Design spec: `docs/superpowers/specs/2026-05-17-bundled-chromium-design.md`
- All files are in `chromium-tools/`. `package.json` has `"type": "module"`.
- Executable scripts keep their `#!/usr/bin/env node` shebang and `chmod +x` bit (git tracks mode `100755` — unchanged by edits).
- The full `puppeteer` package re-exports the entire `puppeteer-core` API, so `import puppeteer from "puppeteer"` is a drop-in replacement for `import puppeteer from "puppeteer-core"`.

## File Structure

| File | Change |
|---|---|
| `chromium-tools/package.json` | Replace `puppeteer-core` dep with `puppeteer` |
| `chromium-tools/lib.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-nav.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-eval.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-content.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-pick.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-screenshot.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-cookies.js` | Import: `puppeteer-core` → `puppeteer` |
| `chromium-tools/browser-start.js` | Full rewrite: bundled-only launch + cross-platform `--profile` |
| `chromium-tools/SKILL.md` | Update Setup and Start-the-Browser sections |

The six debugging scripts (`browser-monitor/console/network/click/type/trace.js`) import only from `lib.js` and are not touched.

---

## Task 1: Swap the dependency and all imports

**Files:**
- Modify: `chromium-tools/package.json`
- Modify: `chromium-tools/lib.js`, `chromium-tools/browser-nav.js`, `chromium-tools/browser-eval.js`, `chromium-tools/browser-content.js`, `chromium-tools/browser-pick.js`, `chromium-tools/browser-screenshot.js`, `chromium-tools/browser-cookies.js`

- [ ] **Step 1: Replace the dependency in `package.json`**

In `chromium-tools/package.json`, find this line in the `dependencies` block:

```json
		"puppeteer-core": "^23.11.1",
```

Replace it with:

```json
		"puppeteer": "^24.31.0",
```

The full `dependencies` block must end up as:

```json
	"dependencies": {
		"@mozilla/readability": "^0.6.0",
		"jsdom": "^27.0.1",
		"puppeteer": "^24.31.0",
		"turndown": "^7.2.2",
		"turndown-plugin-gfm": "^1.0.2"
	}
```

- [ ] **Step 2: Switch the import in all seven scripts that import puppeteer directly**

Each of these seven files contains exactly one identical line:

```javascript
import puppeteer from "puppeteer-core";
```

In each file, replace it with:

```javascript
import puppeteer from "puppeteer";
```

The seven files: `chromium-tools/lib.js`, `chromium-tools/browser-nav.js`, `chromium-tools/browser-eval.js`, `chromium-tools/browser-content.js`, `chromium-tools/browser-pick.js`, `chromium-tools/browser-screenshot.js`, `chromium-tools/browser-cookies.js`.

(Note: `chromium-tools/browser-start.js` also imports `puppeteer-core`, but it is fully rewritten in Task 2 — do NOT edit its import here.)

- [ ] **Step 3: Verify no `puppeteer-core` references remain (except in browser-start.js)**

Run: `cd chromium-tools && grep -l 'puppeteer-core' *.js *.json`
Expected: only `browser-start.js` is listed (it is rewritten in Task 2). If any other file appears, fix it.

- [ ] **Step 4: Install dependencies (downloads Chromium)**

Run: `cd chromium-tools && npm install`
Expected: completes successfully. This downloads a Chromium build (~150 MB) to `~/.cache/puppeteer`; it may take a minute or two.

- [ ] **Step 5: Verify the bundled Chromium is present**

Run: `cd chromium-tools && node -e "import('puppeteer').then(p => { const fs = require('node:fs'); const ep = p.default.executablePath(); console.log(ep, fs.existsSync(ep) ? 'EXISTS' : 'MISSING'); })"`
Expected: prints a path ending in a Chrome/Chromium executable, followed by `EXISTS`.

- [ ] **Step 6: Syntax-check the changed scripts**

Run: `cd chromium-tools && for f in lib.js browser-nav.js browser-eval.js browser-content.js browser-pick.js browser-screenshot.js browser-cookies.js; do node --check "$f" && echo "ok: $f"; done`
Expected: `ok:` for all seven files.

- [ ] **Step 7: Commit**

```bash
git add chromium-tools/package.json chromium-tools/lib.js chromium-tools/browser-nav.js chromium-tools/browser-eval.js chromium-tools/browser-content.js chromium-tools/browser-pick.js chromium-tools/browser-screenshot.js chromium-tools/browser-cookies.js chromium-tools/package-lock.json
git commit -m "Switch dependency from puppeteer-core to full puppeteer"
```

(If git complains about identity, prefix the commit: `git -c user.name="emre" -c user.email="emre.bener@icloud.com" commit ...`)

---

## Task 2: Rewrite `browser-start.js` — bundled-only launch + cross-platform `--profile`

**Files:**
- Modify (full rewrite): `chromium-tools/browser-start.js`

- [ ] **Step 1: Replace the entire contents of `browser-start.js`**

Overwrite `chromium-tools/browser-start.js` with exactly this content (tab indentation):

```javascript
#!/usr/bin/env node

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, cpSync } from "node:fs";
import { basename, sep } from "node:path";
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
	if (src.split(sep).includes("Sessions")) return false;
	return true;
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
	// Ensure the parent dir exists, then mirror the user profile into a
	// clean throwaway dir. cpSync (no shell) works on every platform.
	mkdirSync(CACHE_DIR, { recursive: true });
	rmSync(CACHE_DIR, { recursive: true, force: true });
	cpSync(userProfile, CACHE_DIR, { recursive: true, filter: profileFilter });
} else {
	mkdirSync(CACHE_DIR, { recursive: true });
	// Remove Singleton* lock files to allow a new instance
	for (const f of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
		try {
			rmSync(`${CACHE_DIR}/${f}`, { force: true });
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
```

Note on the `CACHE_DIR` import: `lib.js` defines `CACHE_DIR` as `~/.cache/browser-tools` via `os.homedir()` (cross-platform). The old `browser-start.js` computed this path itself with `process.env.HOME`, which is unset on Windows. Importing `CACHE_DIR` from `lib.js` reuses the single correct definition.

- [ ] **Step 2: Confirm the file is still executable**

Run: `ls -l chromium-tools/browser-start.js`
Expected: permissions show the `x` bit (e.g. `-rwxr-xr-x`). If not, run `chmod +x chromium-tools/browser-start.js`.

- [ ] **Step 3: Syntax-check**

Run: `node --check chromium-tools/browser-start.js`
Expected: no output, exit 0.

- [ ] **Step 4: Verify it launches the bundled Chromium**

First, make sure no skill Chromium is already running: `pkill -f 'user-data-dir=.*browser-tools' 2>/dev/null; sleep 2`

Run: `chromium-tools/browser-start.js`
Expected: `✓ Browser started on :9222 (bundled Chromium)`

- [ ] **Step 5: Smoke-test a connecting script**

Run: `chromium-tools/browser-nav.js https://example.com`
Expected: `✓ Navigated to: https://example.com`

Run: `chromium-tools/browser-eval.js 'document.title'`
Expected: `Example Domain`

- [ ] **Step 6: Verify `--profile`**

Stop the running browser: `pkill -f 'user-data-dir=.*browser-tools' 2>/dev/null; sleep 2`

Run: `chromium-tools/browser-start.js --profile`
Expected: prints `Syncing profile...` then `✓ Browser started on :9222 (bundled Chromium) with your profile`. (On this Linux box a `~/.config/google-chrome` or `~/.config/chromium` profile exists, so the copy succeeds. If the machine genuinely has no Chrome/Chromium profile, the expected output is instead `✗ No Chrome/Chromium profile found to copy` — that is also correct behavior.)

Stop the browser again afterward: `pkill -f 'user-data-dir=.*browser-tools' 2>/dev/null`

- [ ] **Step 7: Commit**

```bash
git add chromium-tools/browser-start.js
git commit -m "Rewrite browser-start.js: launch bundled Chromium, cross-platform --profile"
```

---

## Task 3: Update `SKILL.md`

**Files:**
- Modify: `chromium-tools/SKILL.md`

- [ ] **Step 1: Update the Setup section**

In `chromium-tools/SKILL.md`, find this block:

```markdown
## Setup

Run once before first use:

```bash
cd {baseDir}
npm install
```
```

Replace it with:

```markdown
## Setup

Run once before first use:

```bash
cd {baseDir}
npm install
```

`npm install` also downloads a private copy of Chromium (~150 MB, one-time) — no separate browser installation is required.
```

- [ ] **Step 2: Update the Start-the-Browser description**

In `chromium-tools/SKILL.md`, find this exact paragraph (it follows the Start-the-Browser code block):

```
Launch the browser with remote debugging on `:9222`. Chromium is preferred and Chrome is used as a fallback; the binary is auto-detected on Linux, macOS, and Windows. Use `--profile` to preserve the user's authentication state.
```

Replace it with:

```
Launch puppeteer's bundled Chromium with remote debugging on `:9222`. Use `--profile` to copy your real Chrome/Chromium profile (cookies, logins) into the throwaway session — `--profile` requires Chrome or Chromium to be installed with an existing profile.
```

- [ ] **Step 3: Verify**

Run: `cd chromium-tools && head -17 SKILL.md` — confirm the Setup section now ends with the "~150 MB" sentence.
Run: `grep -c 'auto-detected' SKILL.md` — expect `0` (the old wording is gone).
Run: `grep -c 'bundled Chromium' SKILL.md` — expect `1`.

- [ ] **Step 4: Commit**

```bash
git add chromium-tools/SKILL.md
git commit -m "Update SKILL.md for bundled-Chromium setup"
```

---

## Final Verification

- [ ] **Step 1: Syntax-check every script**

Run: `cd chromium-tools && for f in browser-*.js lib.js; do node --check "$f" && echo "ok: $f"; done`
Expected: `ok:` for all 14 files.

- [ ] **Step 2: Confirm no `puppeteer-core` references survive**

Run: `cd chromium-tools && grep -rl 'puppeteer-core' *.js *.json || echo "clean — no puppeteer-core references"`
Expected: `clean — no puppeteer-core references`.

- [ ] **Step 3: End-to-end check**

Run: `pkill -f 'user-data-dir=.*browser-tools' 2>/dev/null; sleep 2`
Run: `chromium-tools/browser-start.js` — expect `✓ Browser started on :9222 (bundled Chromium)`.
Run: `chromium-tools/browser-eval.js 'navigator.userAgent'` — expect a Chrome user-agent string printed.
Run: `pkill -f 'user-data-dir=.*browser-tools' 2>/dev/null` to clean up.

---

## Self-Review Notes

Checked against the spec on 2026-05-17:

- **Spec coverage:** package.json dep swap (Task 1 Step 1), all 8 import sites switched (Task 1 Step 2 covers 7; browser-start.js's import is replaced by the Task 2 rewrite), `npm install` downloads Chromium (Task 1 Step 4), bundled-only launch via `executablePath()` with missing-binary error (Task 2), `findUserProfile()` per-platform detection (Task 2), `rsync` → `fs.cpSync` with the exclude `filter` and clean-mirror `rmSync` (Task 2), `SKILL.md` Setup + Start-the-Browser updates (Task 3). All covered.
- **Placeholder scan:** none — every step has complete code or an exact command.
- **Type consistency:** `browser-start.js` imports `CACHE_DIR` from `lib.js`, which exports it (confirmed against the existing `lib.js`). The `profileFilter`/`findUserProfile` helper names are used consistently within the one file that defines them.
