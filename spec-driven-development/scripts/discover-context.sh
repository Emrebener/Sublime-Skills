#!/usr/bin/env bash
# Discovers project context files for SDD skills.
# Outputs JSON to stdout listing the resolved paths (or null when absent).
#
# Usage:
#   ./spec-driven-development/scripts/discover-context.sh
#
# Source of truth: .sublime-skills/config.yml at the repo root, with
# .sublime-skills/config-local.yml overlaid per-key when present.
# - context.<name>_path values name the project's convention files
# - spec_dir (docs/specs) and adr_dir (docs/adr) are hardcoded (no longer configurable)
# The script reads ONLY from these files — there is no fallback search. If
# both are absent or a key is unset in both, the corresponding output is null.
#
# For each configured context path the script verifies the file exists; if
# it doesn't, the output is null (the path stays as a hint via state /
# coordinator logs, but discovery does not invent a file).
#
# All scalar reads are delegated to the sibling get-config-value.sh script,
# which is the single source of truth for both YAML extraction and overlay
# (config-local.yml shadows config.yml per-key) semantics.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GET_CONFIG="$SCRIPT_DIR/get-config-value.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" 2>/dev/null || { echo '{"error": "not in a git repo or readable cwd"}'; exit 1; }

CONFIG=""
LOCAL_CONFIG=""
if [ -f ".sublime-skills/config.yml" ]; then
  CONFIG=".sublime-skills/config.yml"
fi
if [ -f ".sublime-skills/config-local.yml" ]; then
  LOCAL_CONFIG=".sublime-skills/config-local.yml"
fi

# Read a scalar from the layered config via the shared helper. Returns
# empty string when the key is absent in both layers, when config is
# missing entirely, or when the helper script is unavailable.
#
# Usage: read_scalar <block> <key>
read_scalar() {
  local block="$1"
  local key="$2"
  [ -z "$CONFIG" ] && return
  [ -x "$GET_CONFIG" ] || return
  "$GET_CONFIG" "$block" "$key" "$CONFIG" 2>/dev/null
}

# Read a context file path from config and verify it exists on disk.
# Returns the path if both conditions hold; empty string otherwise.
resolve_context_path() {
  local key="$1"
  local raw="$(read_scalar context "$key")"
  # Treat null/~/empty as "not set"
  if [ -z "$raw" ] || [ "$raw" = "null" ] || [ "$raw" = "~" ]; then
    echo ""
    return
  fi
  if [ -f "$raw" ]; then
    echo "$raw"
  else
    echo ""
  fi
}

CONSTITUTION="$(resolve_context_path constitution_path)"
ARCHITECTURE="$(resolve_context_path architecture_path)"
GLOSSARY="$(resolve_context_path glossary_path)"
DOMAIN="$(resolve_context_path domain_path)"
DESIGN="$(resolve_context_path design_path)"

# README is not configurable — there is exactly one conventional location.
README=""
[ -f "README.md" ] && README="README.md"

# Hardcoded artifact locations (no longer configurable via .sublime-skills/config.yml).
SPEC_DIR="docs/specs"
ADR_DIR="docs/adr"

# All ADRs under docs/adr/ (sorted by filename for deterministic output).
# If docs/adr/ doesn't exist (no ADRs yet), the array is empty.
ADRS=""
if [ -n "$ADR_DIR" ] && [ -d "$ADR_DIR" ]; then
  ADRS=$(find "$ADR_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi

# Active SDD state file (single global path; absent between runs).
ACTIVE_STATE=""
if [ -f ".sublime-skills/state.json" ]; then
  ACTIVE_STATE=".sublime-skills/state.json"
fi

# JSON helpers.
json_string() {
  if [ -z "${1:-}" ]; then
    echo "null"
  else
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "\"$s\""
  fi
}

json_array() {
  local items="${1:-}"
  if [ -z "$items" ]; then
    echo "[]"
    return
  fi
  local first=1
  local out="["
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ $first -eq 1 ]; then
      first=0
    else
      out="$out, "
    fi
    local s="${line//\\/\\\\}"
    s="${s//\"/\\\"}"
    out="$out\"$s\""
  done <<< "$items"
  out="$out]"
  echo "$out"
}

cat <<EOF
{
  "repo_root": $(json_string "$REPO_ROOT"),
  "config": $(json_string "$CONFIG"),
  "config_local": $(json_string "$LOCAL_CONFIG"),
  "constitution": $(json_string "$CONSTITUTION"),
  "architecture": $(json_string "$ARCHITECTURE"),
  "glossary": $(json_string "$GLOSSARY"),
  "domain": $(json_string "$DOMAIN"),
  "design": $(json_string "$DESIGN"),
  "readme": $(json_string "$README"),
  "spec_dir": $(json_string "$SPEC_DIR"),
  "adr_dir": $(json_string "$ADR_DIR"),
  "adrs": $(json_array "$ADRS"),
  "active_state": $(json_string "$ACTIVE_STATE")
}
EOF
