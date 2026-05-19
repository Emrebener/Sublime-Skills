---
name: chromium-tools
description: Interactive Chromium browser automation and debugging via Chrome DevTools Protocol — an MCP-free alternative to Puppeteer/Chrome MCP. Use when you need to interact with web pages, fill forms, test frontends, capture console and network activity, take an accessibility snapshot of a page, run multiple isolated browser sessions, or when user interaction with a visible browser is required.
---

# Chromium Tools

Chrome DevTools Protocol tools for agent-assisted web automation. These tools connect to Chromium (or Chrome) running on `:9222` with remote debugging enabled.

## Setup

Run once before first use:

```bash
cd {baseDir}
npm install
```

`npm install` also downloads a private copy of Chromium (~150 MB, one-time) — no separate browser installation is required.

**Node version:** use a current Node.js LTS (20, 22, or 24). Node 26 has a known puppeteer bug that downloads Chromium but fails to extract it — if `npm install` succeeds but `browser-start.js` reports the browser missing, switch to a Node LTS release and rerun `npm install`.

## Sessions

Every tool operates on a named **session** — one browser instance with its
own port, profile, and logs. This lets independent tasks run browsers in
parallel without colliding.

- Default session is `"default"` — omit `--session` and everything just works.
- Pass `--session NAME` to any tool, or export `BROWSER_SESSION=NAME` once so
  every later call in that environment is session-scoped with no flag.
- `{baseDir}/browser-sessions.js list` shows running sessions;
  `{baseDir}/browser-sessions.js kill <name>` stops one (also accepts `--session <name>`);
  `{baseDir}/browser-sessions.js kill --all` stops all.

```bash
{baseDir}/browser-start.js --session scrape
{baseDir}/browser-nav.js https://example.com --session scrape
```

## Start the Browser

```bash
{baseDir}/browser-start.js              # Fresh profile
{baseDir}/browser-start.js --profile    # Copy user's profile (cookies, logins)
```

Launch puppeteer's bundled Chromium with remote debugging on `:9222`. Use `--profile` to copy your real Chrome/Chromium profile (cookies, logins) into the throwaway session — `--profile` requires a Chrome or Chromium profile to already exist on this machine (created by running Chrome or Chromium at least once).

## Navigate

```bash
{baseDir}/browser-nav.js https://example.com
{baseDir}/browser-nav.js https://example.com --new
```

Navigate to URLs. Use `--new` flag to open in a new tab instead of reusing current tab.

## Evaluate JavaScript

```bash
{baseDir}/browser-eval.js 'document.title'
{baseDir}/browser-eval.js 'document.querySelectorAll("a").length'
```

Execute JavaScript in the active tab. Code runs in async context. Use this to extract data, inspect page state, or perform DOM operations programmatically.

## Screenshot

```bash
{baseDir}/browser-screenshot.js
```

Capture current viewport and return temporary file path. Use this to visually inspect page state or verify UI changes.

## Accessibility Snapshot and Refs

```bash
{baseDir}/browser-snapshot.js          # interactive elements + refs
{baseDir}/browser-snapshot.js --all    # also include landmarks/headings
```

Prints a compact accessibility tree. Each element gets a stable `[ref=eN]`
id, e.g. `button "Sign Up" [ref=e5]`. Every interaction tool accepts that
ref as `@eN` in place of a CSS selector:

```bash
{baseDir}/browser-click.js @e5
{baseDir}/browser-type.js @e3 "hello"
```

This is the recommended loop: **snapshot → act on refs → re-snapshot**.
Prefer it over hand-written selectors — it is more robust and needs no
guessing about page structure. Refs go stale when the DOM changes; just run
`browser-snapshot.js` again to refresh them.

## Cookies

```bash
{baseDir}/browser-cookies.js
```

Display all cookies for the current tab including domain, path, httpOnly, and secure flags. Use this to debug authentication issues or inspect session state.

## Extract Page Content

```bash
{baseDir}/browser-content.js https://example.com
```

Navigate to a URL and extract readable content as markdown. Uses Mozilla Readability for article extraction and Turndown for HTML-to-markdown conversion. Works on pages with JavaScript content (waits for page to load).

## Monitor Console & Network

```bash
{baseDir}/browser-monitor.js start    # begin capturing
{baseDir}/browser-monitor.js status   # is it running? event counts
{baseDir}/browser-monitor.js stop     # stop capturing
```

Console and network events are live streams — Chrome does not replay history to a newly connected client. Start the monitor *before* the activity you want to capture. It runs as a background daemon attached to the browser on `:9222`, recording console messages, uncaught errors, and network activity to log files. `start` clears previous logs, so each session is clean.

## Console Messages

```bash
{baseDir}/browser-console.js              # all captured console output
{baseDir}/browser-console.js --errors     # errors and warnings only
{baseDir}/browser-console.js --limit 20   # last 20 entries
```

Print console messages and uncaught JavaScript errors captured by the monitor. Run `browser-monitor.js start` first.

## Network Activity

```bash
{baseDir}/browser-network.js              # all captured requests
{baseDir}/browser-network.js --failed     # failures and HTTP >= 400 only
{baseDir}/browser-network.js --limit 20   # last 20 entries
```

Print network requests captured by the monitor: method, status, type, size, timing. Run `browser-monitor.js start` first.

## Click

```bash
{baseDir}/browser-click.js "#submit"
{baseDir}/browser-click.js @e5
```

Wait for a CSS selector or `@eN` ref to become visible, enabled, and stable (actionability wait), then click it.

## Type

```bash
{baseDir}/browser-type.js "#search" "hello world"
{baseDir}/browser-type.js @e3 "hello" --clear --enter
```

Wait for a CSS selector or `@eN` ref to become actionable, then type text into it. `--clear` empties the field first; `--enter` presses Enter after.

## Hover

```bash
{baseDir}/browser-hover.js "#menu-item"
{baseDir}/browser-hover.js @e7
```

Wait for a CSS selector or `@eN` ref to become actionable, then hover over it. Useful for revealing dropdown menus or tooltips.

## Keys

```bash
{baseDir}/browser-key.js Escape
{baseDir}/browser-key.js Tab
{baseDir}/browser-key.js "Control+A"
```

Press a key or chord on the currently focused element. Use standard Puppeteer key names (`Enter`, `Tab`, `Escape`, `ArrowDown`, etc.) and `+` to combine with modifiers.

## Select

```bash
{baseDir}/browser-select.js "#country" "United States"
{baseDir}/browser-select.js @e4 "CA"
```

Wait for a `<select>` element (by CSS selector or `@eN` ref) to become actionable, then choose an option by its visible label or `value` attribute. Pass multiple values to select more than one option in a multi-select.

## Drag

```bash
{baseDir}/browser-drag.js "#item-1" "#drop-zone"
{baseDir}/browser-drag.js @e2 @e9
```

Drag an element to a target (both accept CSS selector or `@eN` ref). Automatically detects native HTML5 drag (`draggable="true"`) vs. mouse-gesture drag and uses the appropriate mechanism.

## Scroll

```bash
{baseDir}/browser-scroll.js "#footer"
{baseDir}/browser-scroll.js @e12
{baseDir}/browser-scroll.js --by 500
```

Scroll an element into view (by CSS selector or `@eN` ref), or scroll the window by a pixel amount with `--by <pixels>` (positive = down, negative = up).

## Wait

```bash
{baseDir}/browser-wait.js visible "#modal"
{baseDir}/browser-wait.js gone "#spinner"
{baseDir}/browser-wait.js text "Order confirmed"
{baseDir}/browser-wait.js text-gone "Loading..."
{baseDir}/browser-wait.js navigation
{baseDir}/browser-wait.js idle
{baseDir}/browser-wait.js delay 2000
```

Wait for a condition before proceeding. Use `--timeout MS` to override the default 10 000 ms limit. Modes: `visible`/`gone` wait for a selector to appear or disappear; `text`/`text-gone` wait for body text; `navigation` waits for a full page load; `idle` waits for network quiet; `delay` is a fixed pause.

## Tabs

```bash
{baseDir}/browser-tabs.js list
{baseDir}/browser-tabs.js new https://example.com
{baseDir}/browser-tabs.js select 1
{baseDir}/browser-tabs.js close 1
```

Manage browser tabs. `list` shows all open tabs with their index, URL, and title (active tab marked with `*`). `new` opens and focuses a new tab, optionally navigating to a URL. `select`/`close` target a tab by its numeric index from `list`.

## Upload

```bash
{baseDir}/browser-upload.js "#file-input" /path/to/file.pdf
{baseDir}/browser-upload.js @e6 /img/a.png /img/b.png
```

Set one or more files on a file input element (by CSS selector or `@eN` ref). File inputs are often visually hidden — the tool waits for the element's presence without requiring it to be visible.

## Dialogs (alert / confirm / prompt)

```bash
# Arm the handler in the background, wait until it is ready, then trigger:
{baseDir}/browser-dialog.js accept &
until [ -f ~/.cache/browser-tools/sessions/default/dialog-armed ]; do sleep 0.1; done
{baseDir}/browser-click.js @e3
```

`browser-dialog.js` writes a `dialog-armed` marker file once its handler is
attached; wait for that file before triggering the dialog so the handler is
never missed. For a non-default session, the path is
`~/.cache/browser-tools/sessions/<session>/dialog-armed`.

`accept --text "..."` supplies a response to a `prompt`. Use `dismiss` to cancel.

## Performance Trace

```bash
{baseDir}/browser-trace.js https://example.com
{baseDir}/browser-trace.js                       # reload current tab
```

Navigate (or reload the current tab) and print a performance summary: TTFB, First/Largest Contentful Paint, DOMContentLoaded, Load, request count, total transfer size, and the 5 slowest requests.

## Debugging Workflow

```bash
{baseDir}/browser-start.js
{baseDir}/browser-monitor.js start
{baseDir}/browser-nav.js https://your-app.example
# ... interact: browser-click.js / browser-type.js / browser-eval.js ...
{baseDir}/browser-console.js --errors
{baseDir}/browser-network.js --failed
{baseDir}/browser-monitor.js stop
```

The monitor attaches to one running Chromium. **If you restart Chromium, restart the monitor too** — `browser-monitor.js status` shows it as not running after a browser restart.

## When to Use

- Testing frontend code in a real browser
- Interacting with pages that require JavaScript
- When user needs to visually see or interact with a page
- Debugging authentication or session issues
- Scraping dynamic content that requires JS execution

---

## Efficiency Guide

### Choosing an Approach: Dedicated Tools vs. `eval`

There are two ways to act on a page, and they have different strengths:

- **Dedicated tools** — `browser-click.js`, `browser-type.js`, `browser-nav.js`, `browser-screenshot.js` — are for ordinary, single interactions: click a button, fill a field, open a URL. They wait for the selector and dispatch real input events, so apps that depend on genuine events (React and the like) behave correctly. Prefer these for normal interaction.
- **`browser-eval.js`** is for *bulk or programmatic* DOM work: extracting structured data, reading a lot of page state in one shot, or driving many elements at once where a separate call per element would be wasteful. The patterns below are its niche.

Rule of thumb: "click this one button" → `browser-click.js`; "pull the title, price, and stock of all 40 items" → `browser-eval.js`.

### Inspect the DOM to Read State

To understand page *state* — what is on the page, what is interactive — parse the DOM with `eval`. It is cheaper and more precise than a screenshot:

```javascript
// Get page structure
document.body.innerHTML.slice(0, 5000)

// Find interactive elements
Array.from(document.querySelectorAll('button, input, [role="button"]')).map(e => ({
  id: e.id,
  text: e.textContent.trim(),
  class: e.className
}))
```

Screenshots (`browser-screenshot.js`) do a different job: confirming *visual* rendering — layout, styling, what a human would actually see. Reach for a screenshot to verify appearance, not to read state.

### Complex Scripts in Single Calls

Wrap everything in an IIFE to run multi-statement code:

```javascript
(function() {
  // Multiple operations
  const data = document.querySelector('#target').textContent;
  const buttons = document.querySelectorAll('button');
  
  // Interactions
  buttons[0].click();
  
  // Return results
  return JSON.stringify({ data, buttonCount: buttons.length });
})()
```

### Bulk Programmatic Clicks

For a *single* real interaction, use `browser-click.js`. But to drive *many* elements at once — every cell of a grid, a run of game controls — one `eval` call beats one `browser-click.js` call per element:

```javascript
(function() {
  const ids = ["cell-1", "cell-2", "cell-3"];
  ids.forEach(id => document.getElementById(id).click());
  return "Done";
})()
```

`el.click()` dispatches a synthetic event. Most apps accept it; if a target relies on real pointer events and ignores it, fall back to `browser-click.js` for that one.

### Driving On-Screen Keyboards

To type into a normal form field, use `browser-type.js`. This pattern is for something else — *clicking on-screen key elements*, as on a virtual keyboard, a calculator, or a game's letter buttons:

```javascript
(function() {
  const text = "HELLO";
  for (const char of text) {
    document.getElementById("key-" + char).click();
  }
  document.getElementById("submit").click();
  return "Entered: " + text;
})()
```

### Reading App/Game State

Extract structured state in one call:

```javascript
(function() {
  const state = {
    score: document.querySelector('.score')?.textContent,
    status: document.querySelector('.status')?.className,
    items: Array.from(document.querySelectorAll('.item')).map(el => ({
      text: el.textContent,
      active: el.classList.contains('active')
    }))
  };
  return JSON.stringify(state, null, 2);
})()
```

### Waiting for Updates

If DOM updates after actions, add a small delay with bash:

```bash
sleep 0.5 && {baseDir}/browser-eval.js '...'
```

### Investigate Before Interacting

Always start by understanding the page structure:

```javascript
(function() {
  return {
    title: document.title,
    forms: document.forms.length,
    buttons: document.querySelectorAll('button').length,
    inputs: document.querySelectorAll('input').length,
    mainContent: document.body.innerHTML.slice(0, 3000)
  };
})()
```

Then target specific elements based on what you find.

When the task is debugging rather than scraping, start `browser-monitor.js` before reproducing the issue, then read `browser-console.js --errors` and `browser-network.js --failed` — console errors and failed requests usually point straight at the cause.
