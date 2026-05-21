#!/usr/bin/env bash
# Reads a single scalar value from .sublime-skills/config.yml at <block>.<key>.
#
# Usage:
#   ./scripts/get-config-value.sh <block> <key> [config-path]
#
# Example:
#   ./scripts/get-config-value.sh finishing test_command
#   ./scripts/get-config-value.sh preflight use_worktree
#   ./scripts/get-config-value.sh grill question_cap
#
# Outputs the value to stdout (no trailing newline if value is empty).
# Exit codes:
#   0 — value found and printed (may be empty string)
#   2 — config file not found, or block/key absent
#   3 — usage error
#
# LIMITATIONS:
#   - Only handles flat `block: \n  key: value` structures (one level of indent).
#   - Does NOT handle: nested objects beyond one level, YAML lists, anchors,
#     multi-line block scalars (| or >), references, or comments inside values.
#   - For anything more complex, skills should use a real YAML parser.

set -u

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <block> <key> [config-path]" >&2
  exit 3
fi

BLOCK="$1"
KEY="$2"
CONFIG="${3:-}"

if [ -z "$CONFIG" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  CONFIG="$REPO_ROOT/.sublime-skills/config.yml"
fi

if [ ! -f "$CONFIG" ]; then
  exit 2
fi

VALUE=$(awk -v block="$BLOCK" -v key="$KEY" '
  $0 ~ "^" block ":[[:space:]]*$" { in_block=1; next }
  /^[^[:space:]#]/ { in_block=0 }
  in_block && $0 ~ "^[[:space:]]+" key ":" {
    sub("^[[:space:]]+" key ":[[:space:]]*", "")
    sub(/[[:space:]]*#.*$/, "")
    gsub(/^"|"$/, "")
    gsub(/^'\''|'\''$/, "")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
    print
    found=1
    exit
  }
  END { exit !found }
' "$CONFIG")

awk_exit=$?

if [ $awk_exit -ne 0 ]; then
  exit 2
fi

printf '%s' "$VALUE"
