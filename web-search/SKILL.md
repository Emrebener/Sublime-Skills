---
name: web-search
description: Web search for AI agents via a self-hosted SearXNG instance — an MCP-free search tool. Use this skill whenever you need to search the web, look something up online, find current information, research a topic, or get web results for a query, in any environment without a search MCP server.
---

# Web Search

A CLI tool that searches the web through a self-hosted
[SearXNG](https://docs.searxng.org/) instance and returns ranked results.
It is dependency-free — it needs only Node.js 18+ (for built-in `fetch`),
no `npm install`.

## Setup

The skill needs the URL of a running SearXNG instance. Provide it either way:

- Set the `SEARXNG_URL` environment variable, or
- Copy `config.example.json` to `config.json` (in this skill directory) and
  set `searxng_url`.

The environment variable takes precedence. `config.json` is git-ignored.

The SearXNG instance must have the JSON format enabled — `json` must be
listed under `search.formats` in its `settings.yml`.

## Search

```bash
{baseDir}/search.js "<query>"
```

Options:

- `--count N` — number of results to return (default 10).
- `--category general|news|images|videos` — result category (default general).
- `--time day|week|month|year` — restrict to recent results (default: all time).
- `--lang LANG` — language/region, e.g. `en`, `en-US`, `all` (default all).
- `--safe 0|1|2` — safe-search: 0 off, 1 moderate, 2 strict (default 0).
- `--json` — output a JSON array instead of text.

```bash
{baseDir}/search.js "rust async runtime comparison" --count 5
{baseDir}/search.js "openai news" --category news --time week
{baseDir}/search.js "claude api pricing" --json
```

Default output is a ranked list of `title / url / snippet`. With `--json`,
each result is an object with `rank`, `title`, `url`, `snippet`, `engine`.

## When to Use

- Looking up current or factual information on the web.
- Researching a topic, finding documentation, or finding source URLs.
- Any task that needs search-engine results.

To read the full content of a result page, use the `browser-tools` skill —
this skill only returns search results.
