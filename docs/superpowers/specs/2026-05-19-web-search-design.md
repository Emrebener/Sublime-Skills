# web-search: SearXNG-backed web search skill — Design

**Date:** 2026-05-19
**Status:** Approved design, pending implementation plan

## Goal

Give AI agents a way to search the web from harnesses that cannot run MCP
servers (the immediate target is the "pi" harness). The skill is a plain CLI
tool that queries a self-hosted [SearXNG](https://docs.searxng.org/) instance's
JSON API and returns ranked results the agent can act on.

It is the second skill in this repository and follows the same shape as
`browser-tools`: plain CLI scripts, no MCP, ESM Node.js.

## Non-goals

- No fetching/reading of result pages — that is `browser-tools`' job. This
  skill only searches.
- No bundled search backend — it queries an existing SearXNG instance the
  user already runs. Standing up SearXNG is out of scope.
- No fallback to other search providers when SearXNG is down.
- No result caching, ranking changes, or de-duplication beyond what SearXNG
  returns.

## Architecture

A dependency-free Node.js CLI skill. The only runtime operation is an HTTP GET
to SearXNG's JSON endpoint plus formatting of the response, so it uses Node's
built-in global `fetch` (Node 18+) and built-in modules only. There is **no
`npm install` step and no third-party dependency** — the friend only needs
Node, which `browser-tools` already requires.

The skill keeps a clean split between pure logic and I/O so the logic is unit
testable:

- `lib.js` — pure, side-effect-free helpers: endpoint resolution, argument
  parsing, request-URL construction, result formatting.
- `search.js` — the CLI entry point: reads argv, calls the `lib.js` helpers,
  performs the `fetch`, prints output, sets exit codes.

## Configuration

The SearXNG base URL is never hardcoded — each user (and the friend) runs a
different instance. Resolution order:

1. The `SEARXNG_URL` environment variable.
2. A `config.json` file in the skill directory: `{"searxng_url": "http://host:port"}`.
3. If neither is set, exit non-zero with guidance on how to set one.

`config.json` is git-ignored (`.gitignore` in the skill dir) so each person's
instance address is local and never committed. A committed
`config.example.json` serves as the copy-me template. A trailing slash on the
configured URL is tolerated (normalized away before building request URLs).

## Component: `search.js` (CLI)

Usage:

```
search.js "<query>" [--count N] [--category general|news|images|videos]
          [--time day|week|month|year] [--lang en|en-US|all]
          [--safe 0|1|2] [--json]
```

- `<query>` — required; the search query (positional; multiple words allowed).
- `--count N` — how many results to print. Default 10. SearXNG returns one
  page of results (typically 10-30); `--count` truncates that page
  client-side. If fewer results exist than requested, all are returned.
- `--category` — SearXNG `categories` param. Default `general`.
- `--time` — SearXNG `time_range` param. Omitted by default (all time).
- `--lang` — SearXNG `language` param. Default `all`.
- `--safe` — SearXNG `safesearch` param (0 off, 1 moderate, 2 strict).
  Default `0`.
- `--json` — emit the structured result list as JSON instead of text.

Default (text) output is a ranked list:

```
1. <title>
   <url>
   <snippet>

2. <title>
   ...
```

With `--json`, output is a JSON array of `{rank, title, url, snippet, engine}`
objects — the same fields, machine-readable.

## Component: `lib.js` (pure helpers)

- `resolveEndpoint(env, skillDir)` — apply the env-var → `config.json` →
  error resolution order; return the normalized base URL (no trailing slash).
- `parseArgs(argv)` — turn argv into `{query, count, category, time, lang,
  safe, json}` with the defaults above; reject unknown flags.
- `buildSearchUrl(base, opts)` — construct the SearXNG request URL with
  `q`, `format=json`, `categories`, `time_range` (only if set), `language`,
  `safesearch`. URL-encode all values.
- `formatResults(results, count, asJson)` — take SearXNG's `results` array,
  take the first `count`, and render either the text block or the JSON array.

`search.js` does only: resolve endpoint, parse args, build URL, `fetch`,
parse JSON, hand the `results` array to `formatResults`, print, exit.

## Data flow

1. `search.js` resolves the endpoint and parses argv via `lib.js`.
2. It builds the request URL and `fetch`es it.
3. SearXNG responds with JSON containing a `results` array. (Its
   `number_of_results` field is unreliable — often `0` even with results —
   and is ignored; the `results` array is authoritative.)
4. `formatResults` truncates to `--count` and renders text or JSON.
5. Output goes to stdout; exit 0.

## Error handling

Every failure prints a `✗`-prefixed message to stderr and exits non-zero,
except empty results which are not an error:

- **No endpoint configured** — `SEARXNG_URL` unset and no `config.json`:
  explain both ways to set it, point at `config.example.json`.
- **Instance unreachable** — `fetch` throws (DNS, connection refused,
  timeout): report the URL that failed and that the SearXNG instance may be
  down or the address wrong.
- **Non-JSON / error response** — HTTP >= 400, or the body does not parse as
  JSON (the common cause is `json` missing from `search.formats` in SearXNG's
  `settings.yml`): say so explicitly and name that fix.
- **Empty results** — print a plain "No results for: <query>" line and exit
  0. An agent asking a question that has no hits is a normal outcome, not a
  failure.

A request timeout (default ~15s, via `AbortController`) prevents the tool
from hanging if the instance is slow or unresponsive.

## Testing

Two layers:

1. **Unit tests** (`test/lib.test.js`, `node:test`) for the pure `lib.js`
   helpers — the bulk of the logic and fully deterministic:
   - `resolveEndpoint`: env var wins; `config.json` fallback; error when
     neither; trailing-slash normalization.
   - `parseArgs`: defaults; each flag parsed; multi-word query; unknown flag
     rejected.
   - `buildSearchUrl`: each option maps to the correct query parameter;
     `time_range` omitted when unset; values URL-encoded.
   - `formatResults`: text rendering; `--json` rendering; truncation to
     `count`; empty-results case.
2. **Smoke test** (`test/smoke.sh`) — runs one live query against the
   configured instance and checks that a result with a URL comes back.
   Requires a reachable SearXNG instance; documented as such.

## Out of scope (YAGNI)

- Pagination beyond SearXNG's first result page.
- Concurrent/batched multi-query search.
- Provider fallback, caching, retries.
- Reading or summarizing result pages (use `browser-tools`).
