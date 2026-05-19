#!/usr/bin/env bash
# End-to-end smoke test for chromium-tools. Exercises every tool against
# local fixtures in an isolated session. Exits non-zero on the first
# failure. Run from the chromium-tools directory: ./test/smoke.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SESSION="smoke-$$"
FIX="file://$(pwd)/test/fixtures"

cleanup() { ./browser-sessions.js kill "$SESSION" >/dev/null 2>&1 || true; }
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }
expect() { # expect <description> <haystack> <needle>
	case "$2" in
		*"$3"*) pass "$1" ;;
		*) echo "  expected to contain: $3"; echo "  got: $2"; fail "$1" ;;
	esac
}

export BROWSER_SESSION="$SESSION"

./browser-start.js >/dev/null
./browser-monitor.js start >/dev/null

# unit tests
node --test "test/*.test.js" >/dev/null && pass "lib unit tests" || fail "lib unit tests"

# snapshot + ref interaction
./browser-nav.js "$FIX/form.html" >/dev/null
SNAP=$(./browser-snapshot.js)
expect "snapshot lists the email textbox" "$SNAP" 'textbox "Email" [ref=e1]'
expect "snapshot marks the disabled button" "$SNAP" 'disabled [ref=e4]'

./browser-type.js @e1 "user@test.com" >/dev/null
VAL=$(./browser-eval.js 'document.getElementById("email").value')
expect "type via ref set the value" "$VAL" "user@test.com"

CLICK_DISABLED=$(./browser-click.js @e4 2>&1 || true)
expect "click on disabled element is rejected" "$CLICK_DISABLED" "disabled"

# select
./browser-select.js "#plan" "Pro" >/dev/null
PLAN=$(./browser-eval.js 'document.getElementById("plan").value')
expect "select chose the Pro option" "$PLAN" "pro"

# wait
W=$(./browser-wait.js text "Account")
expect "wait detected page text" "$W" "Text appeared"

# hover / key / scroll
expect "hover" "$(./browser-hover.js '#save')" "Hovered"
expect "scroll into view" "$(./browser-scroll.js '#link')" "Scrolled into view"
expect "key press" "$(./browser-key.js Tab)" "Pressed: Tab"

# drag
./browser-nav.js "$FIX/drag.html" >/dev/null
./browser-drag.js "#src" "#dst" >/dev/null
DRAG=$(./browser-eval.js 'document.getElementById("status").textContent')
expect "drag triggered drop" "$DRAG" "dropped"

# upload
./browser-nav.js "$FIX/upload.html" >/dev/null
./browser-upload.js "#file" "$(pwd)/test/fixtures/upload.html" >/dev/null
UP=$(./browser-eval.js 'document.getElementById("out").textContent')
expect "upload set a file" "$UP" "1 file(s)"

# dialog
./browser-nav.js "$FIX/dialog.html" >/dev/null
./browser-snapshot.js >/dev/null
( ./browser-dialog.js accept & ) ; sleep 1 ; ./browser-click.js @e1 >/dev/null
sleep 1
DLG=$(./browser-eval.js 'document.getElementById("out").textContent')
expect "dialog was accepted" "$DLG" "accepted"

# tabs
./browser-tabs.js new "$FIX/form.html" >/dev/null
TABS=$(./browser-tabs.js list)
expect "tabs list shows two tabs" "$TABS" "[1]"

# monitor read-back
expect "monitor status" "$(./browser-monitor.js status)" "Monitor running"

echo "ALL SMOKE TESTS PASSED"
