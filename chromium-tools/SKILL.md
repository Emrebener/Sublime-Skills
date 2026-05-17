---
name: chromium-tools
description: Interactive Chromium browser automation and debugging via Chrome DevTools Protocol. Use when you need to interact with web pages, test frontends, capture console and network activity, or when user interaction with a visible browser is required.
---

# Chromium Tools

Chrome DevTools Protocol tools for agent-assisted web automation. These tools connect to Chromium (or Chrome) running on `:9222` with remote debugging enabled.

## Setup

Run once before first use:

```bash
cd {baseDir}
npm install
```

## Start the Browser

```bash
{baseDir}/browser-start.js              # Fresh profile
{baseDir}/browser-start.js --profile    # Copy user's profile (cookies, logins)
```

Launch the browser with remote debugging on `:9222`. Chromium is preferred and Chrome is used as a fallback; the binary is auto-detected on Linux, macOS, and Windows. Use `--profile` to preserve the user's authentication state.

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

## Pick Elements

```bash
{baseDir}/browser-pick.js "Click the submit button"
```

**IMPORTANT**: Use this tool when the user wants to select specific DOM elements on the page. This launches an interactive picker that lets the user click elements to select them. The user can select multiple elements (Cmd/Ctrl+Click) and press Enter when done. The tool returns CSS selectors for the selected elements.

Common use cases:
- User says "I want to click that button" → Use this tool to let them select it
- User says "extract data from these items" → Use this tool to let them select the elements
- When you need specific selectors but the page structure is complex or ambiguous

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
```

Wait for a CSS selector (5s) and click it.

## Type

```bash
{baseDir}/browser-type.js "#search" "hello world"
{baseDir}/browser-type.js "#search" "hello" --clear --enter
```

Wait for a CSS selector, then type text into it. `--clear` empties the field first; `--enter` presses Enter after.

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

### DOM Inspection Over Screenshots

**Don't** take screenshots to see page state. **Do** parse the DOM directly:

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

### Batch Interactions

**Don't** make separate calls for each click. **Do** batch them:

```javascript
(function() {
  const actions = ["btn1", "btn2", "btn3"];
  actions.forEach(id => document.getElementById(id).click());
  return "Done";
})()
```

### Typing/Input Sequences

```javascript
(function() {
  const text = "HELLO";
  for (const char of text) {
    document.getElementById("key-" + char).click();
  }
  document.getElementById("submit").click();
  return "Submitted: " + text;
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
