# browser-tools: Browser Automation & Debugging Skill — Design

**Date:** 2026-05-17
**Status:** Approved

## Goal

Extend the `browser-tools` skill from a browser *automation* skill into a
solid, reliable *automation and debugging* skill — without MCP, so it works
in agents (like pi) that have no MCP support.

The skill already covers navigation, JS evaluation, screenshots,
cookies, and content extraction. This adds the debugging half:
console capture, network inspection, dedicated interaction, and a
performance summary.

## Background

`browser-tools` is a set of CLI scripts documented by `SKILL.md`. Each
script connects to a dedicated Chromium instance running with remote
debugging on `:9222` (launched by `browser-start.js` with an isolated
profile). Scripts speak the Chrome DevTools Protocol via `puppeteer-core`.

Console and network events are live streams — Chrome does not replay
history to a freshly connected CDP client. Capturing them therefore
requires a process that is attached *while the events happen*. The chosen
solution is a background collector daemon.

## Architecture

Six new scripts plus a `SKILL.md` rewrite. No new npm dependencies —
`puppeteer-core` already exposes console, network, input, and performance
APIs.

All scripts reuse the existing pattern: connect to `:9222` with a 5s
timeout, do one job, print result, exit. Errors reuse the existing
"Run: browser-start.js" guidance.

State files live in `~/.cache/browser-tools/` (the existing cache dir):

- `monitor.json` — daemon identity + heartbeat: `{ pid, startedAt,
  wsEndpoint, lastHeartbeat }`. Replaces a bare PID file so liveness can
  be determined precisely (see Concurrency & Lifecycle below).
- `monitor.err` — daemon startup/runtime diagnostics (stderr). Lets a
  detached daemon that dies after spawn leave a trace.
- `console.jsonl` — captured console + page-error events, one JSON per line
- `network.jsonl` — captured network events, one JSON per line

### Concurrency & Lifecycle

The daemon's liveness is determined by a single predicate, used by
`start`, `stop`, `status`, and the query scripts:

> **alive** = `monitor.json` exists *and* its `pid` responds to
> `process.kill(pid, 0)` *and* `lastHeartbeat` is within 15s of now.

The daemon rewrites `lastHeartbeat` every 5s. This one predicate resolves
several failure modes together:

- **Stale PID** (daemon crashed) — heartbeat goes stale; treated as dead.
- **PID reuse** (an unrelated process inherited the PID) — that process
  is not updating *our* `monitor.json`, so the heartbeat is stale.
- **Hung daemon** — heartbeat stops; treated as dead.
- **Chromium restarted** — daemon loses its connection and exits (it does
  not auto-reconnect), so the heartbeat goes stale and `status` reports
  the monitor as dead. The user must re-run `browser-monitor.js start`.

`start` acquires `monitor.json` as a lock via an **exclusive create**
(`fs.openSync(path, "wx")`). The clear-logs step and the daemon spawn
happen *only* after the lock is acquired — so a repeated or concurrent
`start` cannot truncate logs out from under a running daemon. If the file
already exists, `start` evaluates the liveness predicate: alive → report
"already running" and exit 0; dead/stale → overwrite the stale file and
proceed.

The daemon is a single Node process with a single-threaded event loop.
All page listeners fire sequentially, and each event is written with one
synchronous `fs.appendFileSync` of a complete JSON line (terminated by
`\n`). Appends therefore cannot interleave, and a complete line is the
unit of write — a daemon killed mid-run cannot leave a half-written line.
The multi-writer case (two daemons) is prevented by the `monitor.json`
lock above.

### Component: `browser-monitor.js` (daemon lifecycle)

Subcommands: `start`, `stop`, `status`.

- `start`:
  - Evaluate the liveness predicate. If alive → report "already running"
    and exit 0.
  - Acquire `monitor.json` via exclusive create (`wx`); overwrite a
    dead/stale file. *Only after the lock is held:* clear
    `console.jsonl` / `network.jsonl`, then spawn the detached daemon
    with stderr redirected to `monitor.err`.
  - After spawn, wait up to ~3s for the daemon to write its first
    `lastHeartbeat`. If it does not, report failure and print the tail
    of `monitor.err` — so a daemon that dies on startup is diagnosed,
    not silently reported as success.
  - Fail clearly if Chromium is not running on `:9222`.
- The daemon loop:
  - Connects to `:9222`; records `wsEndpoint` and writes the first
    heartbeat.
  - Attaches passive listeners to every existing page and to every new
    target, filtered to `target.type() === "page"` (non-page targets —
    workers, etc. — are skipped; `target.page()` is null for them).
  - Console/network scope is page-level; out-of-process iframe and
    worker contexts are not separately captured.
  - Captures, appending one synchronous complete JSON line per event:
    - `console` → `{ ts, tabUrl, type, text, location }`
    - `pageerror` → `{ ts, tabUrl, type: "error", text }`
    - `response` → `{ ts, tabUrl, requestId, method, url, status,
      resourceType, size, timingMs }`
    - `requestfailed` → `{ ts, tabUrl, requestId, method, url, errorText }`
  - `ts` is epoch milliseconds (number). `requestId` is the CDP request
    id, so a `requestfailed` entry can be correlated with any prior
    `response`/request for the same id. `size` is the response transfer
    size (encoded data length) reported by CDP, falling back to the
    `Content-Length` header, else 0.
  - Captures **metadata only** — no response bodies — to keep logs bounded.
  - Rewrites `lastHeartbeat` every 5s.
  - On browser disconnect: exit cleanly, remove `monitor.json`.
- `stop`: evaluate liveness; if alive, kill the `pid` and remove
  `monitor.json`. If dead/stale, just remove the file. Report if not
  running. The liveness check ensures `stop` never kills a reused PID.
- `status`: report alive/dead via the predicate; if alive, report
  `startedAt`, event counts, and the byte size of each log file (so a
  bloated log on a chatty SPA is visible — see Out of Scope).

### Component: `browser-console.js` (query)

Reads `console.jsonl` and prints captured console messages and uncaught
errors. Flags:

- `--errors` — only `error` and `warning` entries
- `--limit N` — only the last N entries (read the file, take the last N
  lines; logs are session-scoped so a full read is acceptable)

Evaluates the monitor liveness predicate. If the monitor is dead/stale,
print guidance to run `browser-monitor.js start` — and note that any
shown entries are from a previous, ended session.

### Component: `browser-network.js` (query)

Reads `network.jsonl` and prints captured requests with method, status,
type, size, timing, and originating tab URL. Flags:

- `--failed` — only failures: `requestfailed` entries plus `response`
  entries with status ≥ 400. Status 304 (Not Modified) and 1xx
  informational responses are **not** treated as failures.
- `--limit N` — only the last N lines (same tail-read as above)

Same monitor-liveness guidance as `browser-console.js`.

### Component: `browser-click.js` (interaction)

`browser-click.js <selector>` — connects to the last open tab
(`pages().at(-1)`, matching every existing script — this is the
last-created tab, not necessarily the OS-focused one), waits for the CSS
selector (5s timeout), clicks it. Reports success or a clear "selector
not found" error.

### Component: `browser-type.js` (interaction)

`browser-type.js <selector> <text>` — connects to the last open tab
(`pages().at(-1)`, as above), waits for the selector, focuses it, types
the text. Flags:

- `--clear` — clear the field before typing
- `--enter` — press Enter after typing

### Component: `browser-trace.js` (performance)

`browser-trace.js [url]` — navigates to `url` (or reloads the current tab
if omitted), then collects and prints a digestible performance summary:

- TTFB, First Contentful Paint, Largest Contentful Paint
- DOMContentLoaded, Load event timing
- Total request count and total transfer size
- The 5 slowest requests

LCP is the failure-prone metric: a one-shot read after navigation misses
it. The script therefore registers a `PerformanceObserver` for
`largest-contentful-paint` **before navigation**, via
`page.evaluateOnNewDocument`, so the observer is live from the first
frame. After the `load` event it waits a short settle period (~1s) for a
late LCP candidate, then reads the buffered value. The reported LCP is
labelled "LCP at capture time" — accurate for a load-and-measure run,
not a claim about a still-interacting page.

Other metrics come from the Navigation Timing, Paint Timing, and Resource
Timing APIs via page evaluation. Output is a readable text summary an
agent can act on — not a raw trace file.

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

The workflow section must state explicitly that the monitor attaches to
one running Chromium: **if Chromium is restarted, the monitor must be
restarted too** (`browser-monitor.js status` will show it as dead).

## Error Handling

- Connection: existing 5s `Promise.race` timeout + "Run: browser-start.js".
- `browser-monitor.js start`: explicit failure if `:9222` is unreachable;
  if the daemon dies on startup, the failure includes the `monitor.err`
  tail.
- Query scripts: explicit "monitor not running" guidance via the liveness
  predicate; stale-session entries are labelled as such.
- Interaction scripts: explicit "selector not found" on `waitForSelector`
  timeout.
- Daemon: exits cleanly and removes `monitor.json` on browser disconnect;
  a crashed/hung daemon is detected by the stale-heartbeat predicate.

## Testing

Manual verification on the live skill (no test framework in this repo).

Happy path:

- Start Chromium, start monitor, navigate to a page that logs to console
  and makes network requests; confirm `browser-console.js` and
  `browser-network.js` show the events, including with `--errors` /
  `--failed` / `--limit` filters.
- `browser-click.js` / `browser-type.js` against a known form.
- `browser-trace.js` against a real URL; confirm the metrics are
  populated and reasonable.
- `browser-monitor.js status` / `stop` reflect the daemon state.

Failure paths:

- Navigate to a page that throws an uncaught error and makes a request
  that 404s; confirm `--errors` and `--failed` isolate them and that a
  304 response is *not* flagged by `--failed`.
- Run `browser-monitor.js start` twice; confirm the second reports
  "already running" and the existing logs are not truncated.
- Kill the daemon process directly, then run `status` and a query
  script; confirm both report the monitor as dead (stale heartbeat) and
  query output is labelled as a previous session.
- Restart Chromium with the monitor running; confirm `status` reports
  dead and a fresh `start` recovers.
- `browser-click.js` with a selector that does not exist; confirm the
  "selector not found" error.

## Out of Scope (YAGNI)

- Raw trace-file export — only the digestible summary.
- Daemon auto-reconnect — exits on disconnect; honest and simple. The
  user restarts the monitor after a Chromium restart.
- Network response-body capture — metadata only.
- Renaming the internal `~/.cache/browser-tools` cache directory.
- A hard cap / ring buffer on log size. Logs are session-scoped — `start`
  clears them — so they are bounded by one monitoring session. The
  intended use is to monitor a focused window of activity, then `stop`.
  `status` reports log byte sizes so a chatty SPA bloating `network.jsonl`
  is visible; if it grows large, restart the monitor. A hard cap is
  unnecessary complexity for a session-bounded debugging tool.
