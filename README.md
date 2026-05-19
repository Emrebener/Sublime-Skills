# Sublime-Skills

A personal registry of agent skills. Each skill lives in its own directory
with a `SKILL.md`; this file summarizes what each one does.

## Skills

### [browser-tools](browser-tools/)

Interactive Chromium browser automation and debugging over the Chrome
DevTools Protocol — a self-contained, MCP-free alternative to Puppeteer MCP
and Chrome DevTools MCP, for agent harnesses that can't run MCP servers.

A set of plain CLI scripts covering:

- **Named multi-sessions** — run isolated browsers in parallel.
- **Accessibility snapshot + element refs** — act on stable `@eN` refs
  instead of guessed CSS selectors.
- **Actionability waits** — interactions wait for elements to be visible,
  enabled, and stable.
- **Navigation & interaction** — click, type, hover, select, drag, scroll,
  key presses, tabs, dialogs, file uploads.
- **Debugging** — console and network capture, performance traces,
  page-content extraction, screenshots.
