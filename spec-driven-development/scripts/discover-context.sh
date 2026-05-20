#!/usr/bin/env bash
# Discovers project context files for SDD skills.
# Outputs JSON to stdout listing the paths of files found (or null if absent).
#
# Usage:
#   ./spec-driven-development/scripts/discover-context.sh
#
# Override defaults by adding a `context:` block to .sdd/config.yml at repo root.
# This script does NOT parse the config — skills read it directly if overrides
# are configured. See README.md alongside this script for the override schema.

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" 2>/dev/null || { echo '{"error": "not in a git repo or readable cwd"}'; exit 1; }

# Default search paths (space-separated, first match wins)
DEFAULT_CONSTITUTION="docs/constitution.md constitution.md"
DEFAULT_ARCHITECTURE="ARCHITECTURE.md docs/ARCHITECTURE.md docs/architecture.md"
DEFAULT_CONTEXT="CONTEXT.md docs/CONTEXT.md"
DEFAULT_GLOSSARY="GLOSSARY.md docs/GLOSSARY.md docs/glossary.md"
DEFAULT_DOMAIN="DOMAIN.md docs/DOMAIN.md"
DEFAULT_CONTEXT_MAP="CONTEXT-MAP.md docs/CONTEXT-MAP.md"
DEFAULT_README="README.md"

# Find first existing file from a space-separated list
find_first() {
  local paths="$1"
  for p in $paths; do
    if [ -f "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  echo ""
}

CONSTITUTION="$(find_first "$DEFAULT_CONSTITUTION")"
ARCHITECTURE="$(find_first "$DEFAULT_ARCHITECTURE")"
CONTEXT_FILE="$(find_first "$DEFAULT_CONTEXT")"
GLOSSARY="$(find_first "$DEFAULT_GLOSSARY")"
DOMAIN="$(find_first "$DEFAULT_DOMAIN")"
CONTEXT_MAP="$(find_first "$DEFAULT_CONTEXT_MAP")"
README="$(find_first "$DEFAULT_README")"

# SDD config
CONFIG=""
if [ -f ".sdd/config.yml" ]; then
  CONFIG=".sdd/config.yml"
fi

# Minimal YAML extractor for SCALAR values under any top-level block. Limited
# to flat `block: \n  key: value` structures — does NOT handle nested objects,
# lists, anchors, multi-line scalars, or `|`/`>` block strings. Skills that
# need those (e.g., `context.constitution_paths` lists) parse the YAML
# themselves with a proper parser.
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

# Resolve spec_dir and adr_dir (config overrides default)
SPEC_DIR="docs/specs"
ADR_DIR="docs/adr"
if [ -n "$CONFIG" ]; then
  SPEC_DIR_OVERRIDE="$(yaml_block_key "$CONFIG" paths spec_dir)"
  ADR_DIR_OVERRIDE="$(yaml_block_key "$CONFIG" paths adr_dir)"
  [ -n "$SPEC_DIR_OVERRIDE" ] && SPEC_DIR="$SPEC_DIR_OVERRIDE"
  [ -n "$ADR_DIR_OVERRIDE" ] && ADR_DIR="$ADR_DIR_OVERRIDE"
fi

# All ADRs under <adr_dir>/ (sorted by filename for deterministic output)
ADRS=""
if [ -d "$ADR_DIR" ]; then
  ADRS=$(find "$ADR_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi

# Active feature states (one state.json per in-progress spec)
STATES=""
if [ -d "$SPEC_DIR" ]; then
  STATES=$(find "$SPEC_DIR" -maxdepth 2 -type f -name 'state.json' 2>/dev/null | sort)
fi

# Monorepo detection — presence of CONTEXT-MAP.md is the signal
IS_MONOREPO="false"
if [ -n "$CONTEXT_MAP" ]; then
  IS_MONOREPO="true"
fi

# JSON helpers
json_string() {
  if [ -z "${1:-}" ]; then
    echo "null"
  else
    # Escape backslashes and double quotes
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
  "context": $(json_string "$CONTEXT_FILE"),
  "glossary": $(json_string "$GLOSSARY"),
  "domain": $(json_string "$DOMAIN"),
  "context_map": $(json_string "$CONTEXT_MAP"),
  "readme": $(json_string "$README"),
  "is_monorepo": $IS_MONOREPO,
  "spec_dir": $(json_string "$SPEC_DIR"),
  "adr_dir": $(json_string "$ADR_DIR"),
  "adrs": $(json_array "$ADRS"),
  "active_states": $(json_array "$STATES")
}
EOF
