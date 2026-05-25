#!/usr/bin/env bash
# Verifies that paths referenced inside the SDD state file still exist on disk.
# Used on resume — the state file lives at a fixed path but spec/plan it
# references live under docs/specs/<feature_id>/ and could have been deleted
# manually since the state was last written.
#
# Usage:
#   "$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/verify-state-references.sh" [state-path]
#
# Default state-path: .sublime-skills/state.json (resolved from current cwd).
#
# Output: prints each missing referenced path on its own line, prefixed with
# "  - " (two-space indent + dash) so the coordinator can splice it directly
# into a user-facing prompt.
#
# Exit codes:
#   0 = all referenced paths exist (or state file itself is missing — no refs)
#   1 = at least one referenced path is missing
#   2 = usage error (state file present but unreadable / unparseable)

set -u

STATE_PATH="${1:-.sublime-skills/state.json}"

if [ ! -f "$STATE_PATH" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed" >&2
  exit 2
fi

SPEC_PATH=$(jq -r '.spec_path // empty' "$STATE_PATH" 2>/dev/null) || {
  echo "ERROR: failed to parse $STATE_PATH" >&2
  exit 2
}
PLAN_PATH=$(jq -r '.plan_path // empty' "$STATE_PATH" 2>/dev/null) || {
  echo "ERROR: failed to parse $STATE_PATH" >&2
  exit 2
}

missing=0
if [ -n "$SPEC_PATH" ] && [ ! -f "$SPEC_PATH" ]; then
  echo "  - $SPEC_PATH"
  missing=1
fi
if [ -n "$PLAN_PATH" ] && [ ! -f "$PLAN_PATH" ]; then
  echo "  - $PLAN_PATH"
  missing=1
fi

exit "$missing"
