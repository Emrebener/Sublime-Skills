#!/usr/bin/env bash
# Discovers project context files for SDD skills.
# Outputs JSON to stdout listing the resolved paths (or null when absent).
#
# Usage:
#   ./spec-driven-development/scripts/discover-context.sh
#
# Source of truth: .sdd/config.yml at the repo root.
# - context.<name>_path values name the project's convention files
# - paths.spec_dir and paths.adr_dir resolve the spec and ADR directories
# The script reads ONLY from config — there is no fallback search. If config
# is absent or a key is unset, the corresponding output is null.
#
# For each configured context path the script verifies the file exists; if
# it doesn't, the output is null (the path stays as a hint via state /
# coordinator logs, but discovery does not invent a file).

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" 2>/dev/null || { echo '{"error": "not in a git repo or readable cwd"}'; exit 1; }

CONFIG=""
if [ -f ".sdd/config.yml" ]; then
  CONFIG=".sdd/config.yml"
fi

# Minimal YAML extractor for scalar values under a top-level block. Limited
# to flat `block: \n  key: value` structures — does NOT handle nested
# objects beyond one level, lists, anchors, multi-line block scalars
# (| or >), or references. Sufficient for the singular scalar paths in
# .sdd/config.yml's `paths:` and `context:` blocks.
#
# Usage: yaml_block_key <config_file> <block> <key>
yaml_block_key() {
  local config="$1"
  local block="$2"
  local key="$3"
  [ ! -f "$config" ] && return
  awk -v block="$block" -v key="$key" '
    $0 ~ "^" block ":[[:space:]]*$" { in_block=1; next }
    /^[^[:space:]#]/ { in_block=0 }
    in_block && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if ($0 != "") print $0
      exit
    }
  ' "$config"
}

# Read a context file path from config and verify it exists on disk.
# Returns the path if both conditions hold; empty string otherwise.
resolve_context_path() {
  local key="$1"
  local raw=""
  if [ -n "$CONFIG" ]; then
    raw="$(yaml_block_key "$CONFIG" context "$key")"
  fi
  # Treat null/~ as "not set"
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

# Resolve spec_dir and adr_dir from config (no implicit defaults).
SPEC_DIR=""
ADR_DIR=""
if [ -n "$CONFIG" ]; then
  SPEC_DIR="$(yaml_block_key "$CONFIG" paths spec_dir)"
  ADR_DIR="$(yaml_block_key "$CONFIG" paths adr_dir)"
fi

# All ADRs under <adr_dir>/ (sorted by filename for deterministic output).
# If adr_dir is unset or doesn't exist, the array is empty.
ADRS=""
if [ -n "$ADR_DIR" ] && [ -d "$ADR_DIR" ]; then
  ADRS=$(find "$ADR_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi

# Active feature states (one state.json per in-progress spec).
STATES=""
if [ -n "$SPEC_DIR" ] && [ -d "$SPEC_DIR" ]; then
  STATES=$(find "$SPEC_DIR" -maxdepth 2 -type f -name 'state.json' 2>/dev/null | sort)
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
  "constitution": $(json_string "$CONSTITUTION"),
  "architecture": $(json_string "$ARCHITECTURE"),
  "glossary": $(json_string "$GLOSSARY"),
  "domain": $(json_string "$DOMAIN"),
  "design": $(json_string "$DESIGN"),
  "readme": $(json_string "$README"),
  "spec_dir": $(json_string "$SPEC_DIR"),
  "adr_dir": $(json_string "$ADR_DIR"),
  "adrs": $(json_array "$ADRS"),
  "active_states": $(json_array "$STATES")
}
EOF
