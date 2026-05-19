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

### [web-search](web-search/)

Web search for AI agents via a self-hosted
[SearXNG](https://docs.searxng.org/) instance — a self-contained, MCP-free
search tool for harnesses that can't run MCP servers.

A single dependency-free CLI script that queries SearXNG's JSON API and
returns ranked results (`title / url / snippet`, or JSON). Supports result
count, category (general/news/images/videos), time range, language/region,
and safe-search level. The SearXNG endpoint is configured via the
`SEARXNG_URL` environment variable or a local `config.json`.

## Setup

What each skill needs before its tools will run:

### browser-tools

- **Node.js** 20, 22, or 24 LTS (Node 26 has a puppeteer extraction bug — see
  the skill's `SKILL.md`).
- **`npm install`** in the `browser-tools/` directory — this also downloads a
  private copy of Chromium (~150 MB, one-time), so no separate browser
  install is needed.

### web-search

- **Node.js** 18 or newer (for the built-in `fetch`). No `npm install` — the
  skill has no dependencies.
- **A reachable SearXNG instance** with the JSON format enabled (`json` listed
  under `search.formats` in its `settings.yml`).
- The instance URL configured via the `SEARXNG_URL` environment variable, or
  by copying `web-search/config.example.json` to `web-search/config.json` and
  setting `searxng_url`.
