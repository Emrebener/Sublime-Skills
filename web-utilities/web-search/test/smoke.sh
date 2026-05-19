#!/usr/bin/env bash
# End-to-end smoke test for web-search. Runs one live query against the
# configured SearXNG instance and checks a result with a URL comes back.
# Requires SEARXNG_URL to be set (or a config.json in the skill dir) and the
# instance to be reachable. Run from the web-search directory: ./test/smoke.sh
set -euo pipefail

cd "$(dirname "$0")/.."

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# Unit tests first.
node --test test/*.test.js >/dev/null && pass "lib unit tests" || fail "lib unit tests"

# Live text search.
OUT=$(node search.js "anthropic claude" --count 3)
case "$OUT" in
	*http*) pass "live search returned a result with a URL" ;;
	*) echo "  got: $OUT"; fail "live search returned no URL" ;;
esac

# Live JSON search.
JSON=$(node search.js "anthropic claude" --count 2 --json)
echo "$JSON" | node -e '
	let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
		const a = JSON.parse(s);
		if (!Array.isArray(a) || a.length < 1 || !a[0].url) { console.error("bad json"); process.exit(1); }
	});
' && pass "live --json search returned a valid array" || fail "live --json search"

echo "ALL SMOKE TESTS PASSED"
