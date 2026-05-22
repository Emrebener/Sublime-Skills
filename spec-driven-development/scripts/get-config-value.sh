#!/usr/bin/env bash
# Reads a single scalar value at <block>.<key> from the layered config.
#
# Lookup order: config-local.yml overrides config.yml. The first file to
# define <block>.<key> wins. Per-key overlay, not deep merge — sufficient
# because the config schema is flat (block → scalar).
#
# Usage:
#   ./scripts/get-config-value.sh <block> <key> [config-path]
#
# Example:
#   ./scripts/get-config-value.sh finishing test_command
#   ./scripts/get-config-value.sh preflight branch_pattern
#   ./scripts/get-config-value.sh grill question_cap
#
# If [config-path] is supplied, the sibling overlay path is derived by
# replacing the trailing `config.yml` (or any `*.yml` filename) with
# `config-local.yml` in the same directory. If you want to skip the
# overlay entirely, point [config-path] at a file whose directory has
# no config-local.yml.
#
# Outputs the value to stdout (no trailing newline if value is empty).
# Exit codes:
#   0 — value found and printed (may be empty string)
#   2 — config file not found, or block/key absent in both layers
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

CONFIG_DIR="$(dirname "$CONFIG")"
LOCAL_CONFIG="$CONFIG_DIR/config-local.yml"

# Extracts a scalar at <block>.<key> from the given file. Prints the value
# (which may be empty) and exits with the awk found-flag. Caller treats
# exit 0 as "key present" and any non-zero as "key absent."
extract() {
  local file="$1"
  awk -v block="$BLOCK" -v key="$KEY" '
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
  ' "$file"
}

# Try overlay first, fall back to base. A key explicitly set in the
# overlay (including to `null` or empty-string) wins — the awk found-flag
# distinguishes "key present with empty value" from "key absent."
if [ -f "$LOCAL_CONFIG" ]; then
  VALUE=$(extract "$LOCAL_CONFIG")
  if [ $? -eq 0 ]; then
    printf '%s' "$VALUE"
    exit 0
  fi
fi

VALUE=$(extract "$CONFIG")
if [ $? -ne 0 ]; then
  exit 2
fi

printf '%s' "$VALUE"
