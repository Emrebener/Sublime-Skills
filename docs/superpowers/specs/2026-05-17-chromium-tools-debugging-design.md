# chromium-tools: Browser Automation & Debugging Skill — Design

**Date:** 2026-05-17
**Status:** Approved

## Goal

Extend the `chromium-tools` skill from a browser *automation* skill into a
solid, reliable *automation and debugging* skill — without MCP, so it works
in agents (like pi) that have no MCP support.

The skill already covers navigation, JS evaluation, screenshots, element
picking, cookies, and content extraction. This adds the debugging half:
console capture, network inspection, dedicated interaction, and a
performance summary.

## Background

`chromium-tools` is a set of CLI scripts documented by `SKILL.md`. Each
script connects to a dedicated Chromium instance running with remote
debugging on `:9222` (launched by `browser-start.js` with an isolated
profile). Scripts speak the Chrome DevTools Protocol via `puppeteer-core`.

Console and network events are live streams — Chrome does not replay
history to a freshly connected CDP client. Capturing them therefore
requires a process that is attached *while the events happen*. The chosen
solution is a background collector daemon.

## Architecture

Five new scripts plus a `SKILL.md` rewrite. No new npm dependencies —
`puppeteer-core` already exposes console, network, input, and performance
APIs.

All scripts reuse the existing pattern: connect to `:9222` with a 5s
timeout, do one job, print result, exit. Errors reuse the existing
"Run: browser-start.js" guidance.

State files live in `~/.cache/browser-tools/` (the existing cache dir):

- `monitor.pid` — daemon PID, for lifecycle management
- `console.jsonl` — captured console + page-error events, one JSON per line
- `network.jsonl` — captured network events, one JSON per line

### Component: `browser-monitor.js` (daemon lifecycle)

Subcommands: `start`, `stop`, `status`.

- `start`:
  - If a daemon is already running (live PID), report and exit 0.
  - Clear `console.jsonl` and `network.jsonl` so each session is clean.
  - Spawn a detached background process (the daemon loop), write `monitor.pid`.
  - Fail clearly if Chromium is not running on `:9222`.
- The daemon loop:
  - Connects to `:9222`.
  - Attaches passive listeners to every existing page and to every new
    page (`targetcreated`).
  - Captures, appending one JSON line per event:
    - `console` → `{ ts, tabUrl, type, text, location }`
    - `pageerror` → `{ ts, tabUrl, type: "error", text }`
    - `response` → `{ ts, tabUrl, method, url, status, resourceType, size, timingMs }`
    - `requestfailed` → `{ ts, tabUrl, method, url, errorText }`
  - Captures **metadata only** — no response bodies — to keep logs bounded.
  - On browser disconnect: exit cleanly, remove `monitor.pid`.
- `stop`: kill the PID, remove `monitor.pid`. Report if not running.
- `status`: report running/stopped; if running, report event counts in
  each log file.

### Component: `browser-console.js` (query)

Reads `console.jsonl` and prints captured console messages and uncaught
errors. Flags:

- `--errors` — only `error` and `warning` entries
- `--limit N` — only the last N entries

If the monitor is not running (no PID, no log), print guidance to run
`browser-monitor.js start`.

### Component: `browser-network.js` (query)

Reads `network.jsonl` and prints captured requests with method, status,
type, size, timing, and originating tab URL. Flags:

- `--failed` — only failed requests and non-2xx/3xx responses
- `--limit N` — only the last N entries

Same "monitor not running" guidance as above.

### Component: `browser-click.js` (interaction)

`browser-click.js <selector>` — connects to the last active tab, waits for
the CSS selector (5s timeout), clicks it. Reports success or a clear
"selector not found" error.

### Component: `browser-type.js` (interaction)

`browser-type.js <selector> <text>` — connects to the last active tab,
waits for the selector, focuses it, types the text. Flags:

- `--clear` — clear the field before typing
- `--enter` — press Enter after typing

### Component: `browser-trace.js` (performance)

`browser-trace.js [url]` — navigates to `url` (or reloads the current tab
if omitted), then collects and prints a digestible performance summary:

- TTFB, First Contentful Paint, Largest Contentful Paint
- DOMContentLoaded, Load event timing
- Total request count and total transfer size
- The slowest few requests

Metrics come from the Navigation Timing, Paint Timing, Resource Timing,
and LCP (`PerformanceObserver`) APIs via page evaluation. Output is a
readable text summary an agent can act on — not a raw trace file.

### `SKILL.md` rewrite

Add one documented section per new tool. Add a "Debugging Workflow"
section describing the intended sequence:

```
browser-start.js
browser-monitor.js start
... navigate / click / type / eval ...
browser-console.js / browser-network.js
browser-monitor.js stop
```

## Error Handling

- Connection: existing 5s `Promise.race` timeout + "Run: browser-start.js".
- `browser-monitor.js start`: explicit failure if `:9222` is unreachable.
- Query scripts: explicit "monitor not running" guidance.
- Interaction scripts: explicit "selector not found" on `waitForSelector`
  timeout.
- Daemon: exits cleanly and removes its PID file on browser disconnect.

## Testing

Manual verification on the live skill (no test framework in this repo):

- Start Chromium, start monitor, navigate to a page that logs to console
  and makes network requests; confirm `browser-console.js` and
  `browser-network.js` show the events, including with `--errors` /
  `--failed` / `--limit` filters.
- `browser-click.js` / `browser-type.js` against a known form.
- `browser-trace.js` against a real URL; confirm the metrics are
  populated and reasonable.
- `browser-monitor.js status` / `stop` reflect the daemon state.

## Out of Scope (YAGNI)

- Raw trace-file export — only the digestible summary.
- Daemon auto-reconnect — exits on disconnect; honest and simple.
- Network response-body capture — metadata only.
- Renaming the internal `~/.cache/browser-tools` cache directory.
