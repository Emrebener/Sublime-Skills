# browser-tools: Switch to Bundled Chromium — Design

**Date:** 2026-05-17
**Status:** Approved

## Goal

Make the `browser-tools` skill plug-and-play across platforms — especially
Windows, where installing Chromium separately is painful. After this change,
`npm install` alone fully provisions the skill: it downloads its own
Chromium, so no separate browser install is required.

## Background

The skill currently depends on **`puppeteer-core`**, which downloads no
browser. `browser-start.js` detects a system-installed Chromium/Chrome
binary and launches it with remote debugging on `:9222`; every other script
connects to `:9222`.

Switching to the full **`puppeteer`** package changes this: `puppeteer`'s
install step downloads a known-good Chromium (Chrome for Testing) into
`~/.cache/puppeteer`, and exposes its path via `puppeteer.executablePath()`.

## Decisions

- **Bundled only.** `browser-start.js` always launches the bundled
  Chromium. System-binary detection is removed entirely.
- **`--profile` made cross-platform.** The `--profile` flag's `rsync` call
  (rsync does not exist on Windows) is replaced with Node's built-in
  `fs.cpSync`.

## Changes

### 1. `package.json`

- Remove `puppeteer-core`. Add `puppeteer` at `^24.31.0`.
- All other dependencies (`@mozilla/readability`, `jsdom`, `turndown`,
  `turndown-plugin-gfm`) are unchanged.

`npm install` will now also download a Chromium (~150 MB) to
`~/.cache/puppeteer` — a one-time cost, outside the repository.

### 2. Import statements

Eight files import `puppeteer` from `"puppeteer-core"`. Each switches to
`"puppeteer"`. The full `puppeteer` package re-exports the identical API,
so this is a one-token change per file with no behavior change:

- `lib.js`
- `browser-start.js`
- `browser-nav.js`
- `browser-eval.js`
- `browser-content.js`
- `browser-screenshot.js`
- `browser-cookies.js`

The six debugging scripts (`browser-monitor/console/network/click/type/
trace.js`) import only from `lib.js` and need no change.

### 3. `browser-start.js` — bundled-only launch

- Remove `findBrowser()` and all system-path probing.
- The launch binary is `puppeteer.executablePath()`. If that path does not
  exist on disk, exit with a clear error:
  `✗ Bundled Chromium not found — run: npm install`.
- The browser is still `spawn`ed detached with
  `--remote-debugging-port=9222`, `--user-data-dir=<cache>`,
  `--no-first-run`, `--no-default-browser-check`, then waited on until it
  answers on `:9222`. The persistent-browser model is unchanged — no
  migration to `puppeteer.launch()`.

### 4. `browser-start.js` — `--profile` cross-platform

`--profile` copies the user's real browser profile into the throwaway
`--user-data-dir`. Binary detection is gone, so profile-source detection
becomes its own concern.

- Add `findUserProfile()`: returns the first existing default profile
  directory for the platform:
  - Linux: `~/.config/google-chrome`, then `~/.config/chromium`
  - macOS: `~/Library/Application Support/Google/Chrome`, then
    `~/Library/Application Support/Chromium`
  - Windows: `%LOCALAPPDATA%\Google\Chrome\User Data`, then
    `%LOCALAPPDATA%\Chromium\User Data`
  - If none exists, `--profile` exits with a clear error.
- Replace the `rsync` call (`execFileSync("rsync", ...)`) with
  `fs.cpSync(src, dest, { recursive: true, filter })`.
- The destination (`--user-data-dir`) is removed first
  (`rmSync(dir, { recursive: true, force: true })`) so the copy is a clean
  mirror — equivalent to the old `rsync --delete`.
- The `filter` function reproduces the old `--exclude` list. A path is
  skipped when its basename is `SingletonLock`, `SingletonSocket`,
  `SingletonCookie`, `Current Session`, `Current Tabs`, `Last Session`, or
  `Last Tabs`, or when it lies inside a `Sessions` directory. The
  `SingletonSocket` exclusion also keeps `cpSync` from failing on a socket
  file.

### 5. `SKILL.md`

- Setup section: note that `npm install` now also downloads a Chromium
  (~150 MB, one-time) and that no separate browser install is needed.
- "Start the Browser" section: remove the "binary is auto-detected on
  Linux, macOS, and Windows" wording; state that it launches puppeteer's
  bundled Chromium.

## Error Handling

- `browser-start.js`: clear error if the bundled Chromium path is missing
  (`npm install` not run); clear error if `--profile` finds no source
  profile directory.
- `cpSync` failure on an unreadable profile file surfaces as a normal
  error with the file path — acceptable for the opt-in `--profile` path.

## Testing

Manual verification (no test framework in this repo):

- `npm install` from a clean state — completes and downloads Chromium.
- `browser-start.js` — launches the bundled Chromium on `:9222`.
- Smoke test: `browser-nav.js` + `browser-eval.js` against a real URL.
- `browser-start.js --profile` on Linux — copies the profile without
  error and the browser starts.
- `node --check` passes for every changed script.

## Out of Scope (YAGNI)

- No changes to the six debugging scripts.
- No migration from `spawn` to `puppeteer.launch()`.
- No project-local browser cache — puppeteer's default `~/.cache/puppeteer`
  is outside the repository and needs no `.gitignore` entry.
- No exclusion of Chrome cache subdirectories from `--profile` copies —
  behavior stays equivalent to the current `rsync -a`.
