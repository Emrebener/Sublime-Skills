# chromium-tools: MCP-parity upgrade

**Date:** 2026-05-19
**Status:** Approved design, pending implementation plan

## Goal

Raise the `chromium-tools` skill to be a practical, self-contained alternative
to Puppeteer MCP and Chrome DevTools MCP, for use in AI coding harnesses that
do not support MCP servers (the immediate target is the "pi" harness,
https://pi.dev). The skill must remain a set of plain CLI scripts an agent
invokes through the shell — no MCP protocol, no always-on server beyond the
browser itself.

## Non-goals

- Request interception / response mocking
- Network throttling, device/viewport emulation, geolocation spoofing
- PDF export
- A persistent command-router daemon (the stateless CLI model is kept
  deliberately — see "Architecture")

These are deferred. They can be added later as independent tools without
disturbing this design.

## Architecture

### Stateless CLI model (unchanged)

Every script connects fresh to a running browser, performs one action, and
disconnects. The browser instance holds all page state between calls. This
model is kept because it is crash-proof (no daemon to hang or go stale),
trivial to reason about, and needs no inter-process coordination. The measured
cost — a Node process spawn plus a CDP reconnect, roughly 0.5–1 s per call — is
acceptable for agent use.

The only shared state introduced by this upgrade is a small session registry
file, which is a passive lookup table, not a process.

### Named multi-sessions

A **session** is one browser instance with its own debugging port, profile
directory, and monitor logs. Sessions let multiple agents (or multiple tasks
of one agent) run browser work in parallel without colliding on a port.

**Registry.** `~/.cache/browser-tools/sessions.json` maps each session name to
`{ port, pid, userDataDir, startedAt }`. The registry is the source of truth
for which port a named session lives on.

**Default session.** When no session is specified, the session name is
`"default"`. Existing single-session workflows keep working unchanged.

**Selecting a session.** Every script resolves its target session in this
order of precedence:

1. An explicit `--session NAME` flag.
2. The `BROWSER_SESSION` environment variable.
3. The literal `"default"`.

A pi agent isolates itself by exporting `BROWSER_SESSION=<agent-id>` once; all
subsequent calls in that environment are then session-scoped with no per-call
flag.

**Port allocation.** `browser-start.js` scans upward from 9222 for a free TCP
port, launches the browser on it, and writes the registry entry. The default
session still lands on 9222 when free.

**Per-session monitor logs.** Monitor state and logs move from global files to
`~/.cache/browser-tools/sessions/<name>/` (`monitor.json`, `console.jsonl`,
`network.jsonl`, `monitor.err`).

**Lifecycle.** `browser-sessions.js` lists running sessions (name, port, pid,
liveness) and kills one (`--session NAME`) or all (`--all`). Killing a session
ends its browser and removes its registry entry. A session whose pid is dead is
reported as stale and is cleaned from the registry on the next access.

### Accessibility snapshot + ref system

This is the central capability gap with Puppeteer/Chrome MCP and the core of
this upgrade. Today the agent must hand-write CSS selectors or query the DOM
through `eval`; this is brittle and token-hungry.

**Chosen approach: DOM-attribute refs.** `browser-snapshot.js` walks the DOM,
assigns every interactive and structurally significant element a stable
attribute `data-ct-ref="eN"`, and prints a compact accessibility tree. Each
interaction tool then accepts an `@eN` token that resolves to the selector
`[data-ct-ref="eN"]`.

Rejected alternatives:

- *In-memory ref→selector map in a file.* Rejected: generating a unique, stable
  CSS selector for an arbitrary element is fragile.
- *`page.accessibility.snapshot()` with no refs.* Rejected: the tree can be
  read but not acted upon, which defeats the purpose.

**Why DOM-attribute refs fit this skill.** The refs live in the page's own DOM,
so they survive across separate stateless CLI invocations with zero shared
state — exactly aligned with the no-daemon decision. A ref goes stale only when
its DOM node is removed or replaced; the agent then re-runs `browser-snapshot.js`,
the same snapshot→act→re-snapshot loop Playwright MCP uses. The page mutation is
a single benign `data-*` attribute.

**Snapshot output.** An indented tree, one element per line, showing role,
accessible name, relevant state, and ref. Roles derive from the tag and any
explicit `role` attribute; the accessible name from `aria-label`, associated
`<label>`, `alt`, `placeholder`, or trimmed text content. Example:

```
form
  textbox "Email" [ref=e3]
  textbox "Password" [ref=e4]
  button "Sign Up" [ref=e5]
```

Snapshot covers interactive elements (links, buttons, inputs, selects,
textareas, `[role]`, `[tabindex]`, `[contenteditable]`) and structural
landmarks (headings, forms, nav, main, lists). Off-screen and `hidden`/
`display:none` elements are omitted. A `--all` flag includes non-interactive
text nodes for fuller page understanding when needed.

## Components

### `lib.js` — shared helpers (extended)

- `parseArgs(argv)` — extract `--session` and other common flags, apply the
  `BROWSER_SESSION` → `"default"` precedence chain, return remaining positional
  arguments.
- `resolveSession(name)` — read the registry, return the session's port, or
  exit(1) with guidance ("no such session — run `browser-start.js
  --session NAME`").
- `connect(session)` — connect to the resolved session's port (today's
  hardcoded 9222 becomes the resolved port).
- `resolveTarget(arg)` — if `arg` matches `^@e\d+$`, return the selector
  `[data-ct-ref="<id>"]`; otherwise return `arg` unchanged as a CSS selector.
- `waitActionable(page, target, timeout)` — resolve the target, then wait until
  the element is present, visible (`waitForSelector {visible:true}`), enabled
  (not `disabled`), and stable (bounding box unchanged across two animation
  frames). Throws a clear error on timeout. A stale `@eN` ref produces
  "ref @eN not found — re-run browser-snapshot.js".
- Registry read/write helpers and per-session path helpers.

### New tools

| Tool | Purpose |
|------|---------|
| `browser-snapshot.js` | Walk the DOM, assign `@eN` refs, print the accessibility tree. `--all` includes non-interactive content. |
| `browser-tabs.js` | `list` / `new [url]` / `select <index>` / `close <index>`. |
| `browser-dialog.js` | Pre-arm handling of the next `alert`/`confirm`/`prompt`: `accept` / `dismiss` / `accept --text "..."`. |
| `browser-upload.js` | Set one or more files on a file input (`@eN` or selector + file paths). |
| `browser-wait.js` | Wait for one of: selector visible, selector gone, text appears, text gone, navigation, network-idle, fixed delay. |
| `browser-hover.js` | Hover an element to reveal menus/tooltips. |
| `browser-select.js` | Choose one or more `<select>` options by value or visible label. |
| `browser-drag.js` | Drag from a source element/ref to a target element/ref. |
| `browser-scroll.js` | Scroll the page by amount, or scroll a given element into view. |
| `browser-key.js` | Press a key or chord (`Escape`, `Tab`, `Control+A`) not tied to a text field. |
| `browser-sessions.js` | List running sessions; kill one (`--session`) or all (`--all`). |

### Changed existing tools

- `browser-click.js`, `browser-type.js`: accept `@eN` refs as well as CSS
  selectors; route through `waitActionable` for proper actionability waiting.
- All 14 existing scripts: gain `--session` / `BROWSER_SESSION` resolution via
  `parseArgs`.
- `browser-start.js`: allocate a free port, write the registry entry, support
  `--session`.
- `browser-monitor.js`: per-session log paths.
- `browser-trace.js`: label the subresource count clearly so a zero-subresource
  page no longer reads as the confusing `Requests: 0` (iteration-1 finding).
- `SKILL.md`: document sessions, the snapshot/ref workflow, and every new tool.

## Data flow

Typical agent loop after the upgrade:

1. `browser-start.js --session work` — launch, registry records port.
2. `browser-nav.js https://app.example --session work`.
3. `browser-snapshot.js --session work` — get the tree with `@eN` refs.
4. `browser-click.js @e5 --session work` — act on a ref; `waitActionable`
   ensures the element is ready.
5. Re-run `browser-snapshot.js` after the DOM changes; refs refresh.
6. `browser-sessions.js --session work` kill, or `--all` at the end.

## Error handling

Every tool follows one contract, already established by `connect()`:

- Success prints a `✓`-prefixed line; failure prints a `✗`-prefixed line and
  exits non-zero.
- Failures carry actionable guidance, not raw stack traces: a missing session
  points at `browser-start.js`; a stale ref points at `browser-snapshot.js`; a
  failed actionability wait says which condition (visible/enabled/stable)
  timed out.
- `parseArgs`, `resolveSession`, `resolveTarget`, and `waitActionable`
  centralize this so every tool behaves consistently.

## Testing

Two layers:

1. **Deterministic fixture smoke test.** A set of local HTML fixtures under the
   workspace exercises every new tool — snapshot/refs, tabs, dialog, upload,
   wait, hover, select, drag, scroll, key — with no network dependency. This is
   the fast regression check.

2. **skill-creator eval loop, iteration-2.** Re-run the benchmark with the eval
   set revised per iteration-1 findings:
   - Replace the static-HTML Hacker News scrape (a poor discriminator — a plain
     fetch matched it) with a genuinely JS-dependent page, so the benchmark
     reflects the skill's real value.
   - Add evals exercising the snapshot→ref→act loop, multi-tab handling, and
     dialog handling.
   - Keep the deterministic broken-button debugging eval.
   - Baseline runs must execute with the global skills symlink removed, so the
     "without skill" comparison is not contaminated (iteration-1 finding).

## Open risks

- **Ref staleness on highly dynamic pages.** Mitigated by the documented
  re-snapshot loop; this matches Playwright MCP behavior and is expected.
- **`data-ct-ref` attribute visible to the page.** A page could in principle
  read it; this is benign for automation contexts and matches how Playwright
  MCP annotates the DOM.
- **Cross-platform.** The target friend's OS is unknown. `browser-start.js` is
  already cross-platform (per recent commits); new tools must avoid
  POSIX-only assumptions.
