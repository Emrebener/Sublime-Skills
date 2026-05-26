#!/usr/bin/env bash
# Validates .sublime-skills/config.yml structurally and semantically.
#
# If a sibling .sublime-skills/config-local.yml exists, it is overlaid onto
# the base config per-key (overlay wins), and validation runs against the
# merged result. Unknown blocks/keys in the overlay are flagged. An empty
# overlay file (zero bytes or YAML null) is treated as "no overrides."
#
# Usage:
#   "$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh" [config-path]
#
# Default config-path: <repo-root>/.sublime-skills/config.yml
#
# Exit codes:
#   0 — PASS  (merged config is structurally valid; all referenced files exist or are null)
#   1 — FAIL  (one or more issues; findings on stderr)
#   2 — config file not found
#   3 — usage error
#
# Output:
#   - One finding per line on stderr, each prefixed with `FAIL:` or `WARN:`.
#   - Findings sourced from config-local.yml are prefixed with `config-local.yml: `.
#   - Final summary line on stdout: `validate-config: PASS` or `validate-config: FAIL (N issues)`.
#
# Used by:
#   - project-bootstrap/ss-bs-bootstrapping-project (Step 6 fix-and-retry loop)
#   - spec-driven-development/ss-sdd-preflight (Stage 0; Step 1 of its Checklist; HALT-on-fail)
#   - future audit skill
#
# Implementation notes:
#   - Prefers python3+pyyaml when available for proper YAML parsing + overlay merge.
#   - Falls back to an awk-based scanner that catches the most common shape issues
#     when python3 is missing. The fallback validates base config only and emits a
#     WARN if config-local.yml exists (overlay validation requires the python path).

set -u

usage() {
  echo "Usage: $0 [config-path]" >&2
  exit 3
}

if [ $# -gt 1 ]; then
  usage
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="${1:-$REPO_ROOT/.sublime-skills/config.yml}"

if [ ! -f "$CONFIG" ]; then
  echo "FAIL: config file not found at $CONFIG" >&2
  echo "validate-config: FAIL (config file not found)"
  exit 2
fi

ISSUE_COUNT=0
record_fail() {
  echo "FAIL: $1" >&2
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

record_warn() {
  echo "WARN: $1" >&2
}

# ────────────────────────────────────────────────────────────────────────
# Preferred path: python3 + PyYAML
# ────────────────────────────────────────────────────────────────────────

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  fi
fi

if [ -n "$PYTHON_BIN" ]; then
  # Run the full validation inside python. The python script writes findings
  # on stderr (one per line, FAIL:/WARN: prefixed) and exits 0 if everything
  # passed, 1 if there were any FAIL findings.
  STDERR_FILE="/tmp/.validate-config-stderr-$$"
  "$PYTHON_BIN" - "$CONFIG" "$REPO_ROOT" 2>"$STDERR_FILE" <<'PY'
import sys
import os
import yaml

config_path = sys.argv[1]
repo_root = sys.argv[2]
local_path = os.path.join(os.path.dirname(config_path), "config-local.yml")

fail_count = 0

def fail(msg):
    global fail_count
    sys.stderr.write("FAIL: " + msg + "\n")
    fail_count += 1

def warn(msg):
    sys.stderr.write("WARN: " + msg + "\n")

try:
    with open(config_path, "r") as f:
        data = yaml.safe_load(f)
except yaml.YAMLError as e:
    fail("YAML does not parse: " + str(e).replace("\n", " "))
    sys.exit(1 if fail_count else 0)

if not isinstance(data, dict):
    fail("top-level config must be a mapping (block), got " + type(data).__name__)
    sys.exit(1 if fail_count else 0)

# Known schema — used both for overlay key-recognition and validation.
context_keys = ["constitution_path", "architecture_path", "testing_path", "glossary_path", "domain_path", "design_path"]
known_blocks = {
    "context": set(context_keys),
    "branching": {"branch_pattern"},
    "grill": {"question_cap"},
    "memory_file": {"path", "character_limit"},
    "suggest": {"default"},
}

# Overlay: parse config-local.yml if present, sanity-check its shape and key
# names, then merge per-key into the base data. Validation continues against
# the merged result, so type/enum/path checks apply to whichever value wins.
local_data = None
if os.path.isfile(local_path):
    try:
        with open(local_path, "r") as f:
            local_data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        fail("config-local.yml: YAML does not parse: " + str(e).replace("\n", " "))
        local_data = None

    if local_data is None:
        # Empty file or YAML null — no overrides. Skip.
        pass
    elif not isinstance(local_data, dict):
        fail("config-local.yml: top-level must be a mapping (block) or empty, got " + type(local_data).__name__)
        local_data = None
    else:
        # Sanity-check overlay block + key names before merging
        for block, content in local_data.items():
            if block not in known_blocks:
                fail(f"config-local.yml: unknown top-level block: {block}")
                continue
            if not isinstance(content, dict):
                fail(f"config-local.yml: block `{block}` must be a mapping, got {type(content).__name__}")
                continue
            for key in content.keys():
                if key not in known_blocks[block]:
                    fail(f"config-local.yml: unknown key {block}.{key}")

        # Per-key merge into base data. The base is mutated in place; later
        # validation reads the merged values.
        for block, content in local_data.items():
            if block not in known_blocks or not isinstance(content, dict):
                continue
            existing = data.get(block)
            if not isinstance(existing, dict):
                data[block] = dict(content)
            else:
                merged = dict(existing)
                merged.update(content)
                data[block] = merged

# Reject unknown top-level blocks (catches schema drift like a stale paths: block)
for block in data.keys():
    if block not in known_blocks:
        fail(f"unknown top-level block: {block}")

# Required top-level blocks
required_blocks = ["context", "branching", "grill", "memory_file"]
for block in required_blocks:
    if block not in data:
        fail(f"missing top-level block: {block}")
    elif not isinstance(data[block], dict):
        fail(f"top-level block `{block}` must be a mapping, got {type(data[block]).__name__}")

# Helper: safely get nested key without crashing
def get(block, key):
    b = data.get(block)
    if isinstance(b, dict):
        return b.get(key, "__MISSING__")
    return "__MISSING__"

# ── context block ──────────────────────────────────────────────────
for key in context_keys:
    v = get("context", key)
    if v == "__MISSING__":
        fail(f"context.{key}: missing (use null if this project doesn't have one)")
        continue
    if v is None:
        continue  # null is fine
    if not isinstance(v, str) or not v.strip():
        fail(f"context.{key}: must be null or a non-empty string, got {v!r}")
        continue
    # Verify the file exists. Support ~ expansion and absolute/relative paths.
    candidate = os.path.expanduser(v)
    if not os.path.isabs(candidate):
        candidate = os.path.join(repo_root, candidate)
    if not os.path.isfile(candidate):
        fail(f"context.{key}: orphan path (file does not exist): {v}")

# Reject unexpected keys in context (catches stale schema like context_map_path/context_path)
ctx_block = data.get("context")
if isinstance(ctx_block, dict):
    for extra in sorted(set(ctx_block.keys()) - set(context_keys)):
        fail(f"context.{extra}: unknown key (allowed: {', '.join(context_keys)})")

# ── branching block ────────────────────────────────────────────────
v = get("branching", "branch_pattern")
if v == "__MISSING__":
    fail("branching.branch_pattern: missing")
elif not isinstance(v, str) or not v.strip():
    fail(f"branching.branch_pattern: must be a non-empty string, got {v!r}")
elif "{short-name}" not in v:
    warn(f"branching.branch_pattern does not contain {{short-name}} placeholder: {v!r}")

# ── grill block ────────────────────────────────────────────────────
v = get("grill", "question_cap")
if v == "__MISSING__":
    fail("grill.question_cap: missing")
elif not isinstance(v, int) or isinstance(v, bool):
    fail(f"grill.question_cap: must be an integer, got {type(v).__name__}")
elif v < 1 or v > 20:
    fail(f"grill.question_cap: must be between 1 and 20 (inclusive), got {v}")

# ── memory_file block ──────────────────────────────────────────────
v = get("memory_file", "path")
if v == "__MISSING__":
    fail("memory_file.path: missing (use null to auto-detect)")
elif v is None:
    pass  # null is fine — auto-detect or skipped
elif not isinstance(v, str) or not v.strip():
    fail(f"memory_file.path: must be null or a non-empty string, got {v!r}")
else:
    candidate = os.path.expanduser(v)
    if not os.path.isabs(candidate):
        candidate = os.path.join(repo_root, candidate)
    if not os.path.isfile(candidate):
        fail(f"memory_file.path: orphan path (file does not exist): {v}")

v = get("memory_file", "character_limit")
if v == "__MISSING__":
    fail("memory_file.character_limit: missing")
elif not isinstance(v, int) or isinstance(v, bool):
    fail(f"memory_file.character_limit: must be an integer, got {type(v).__name__}")
elif v < 1000:
    fail(f"memory_file.character_limit: must be at least 1000, got {v}")

# ── suggest block ───────────────────────────────────────────────────
if "suggest" in data:
    sb = data["suggest"]
    if not isinstance(sb, dict):
        fail("suggest must be a mapping")
    else:
        unknown = set(sb.keys()) - {"default"}
        for k in unknown:
            fail(f"suggest.{k} is not a recognized key")
        if "default" in sb and sb["default"] not in ("ask", "on", "off"):
            fail(f"suggest.default must be one of ask|on|off (got: {sb['default']!r})")

sys.exit(1 if fail_count else 0)
PY
  PY_EXIT=$?
  # Forward python's stderr findings to our stderr.
  if [ -f "$STDERR_FILE" ]; then
    cat "$STDERR_FILE" >&2
    ISSUE_COUNT=$(grep -c "^FAIL:" "$STDERR_FILE" 2>/dev/null | tr -d '\n')
    [ -z "$ISSUE_COUNT" ] && ISSUE_COUNT=0
    rm -f "$STDERR_FILE"
  fi
  if [ "$PY_EXIT" -eq 0 ]; then
    echo "validate-config: PASS"
    exit 0
  else
    echo "validate-config: FAIL ($ISSUE_COUNT issues)"
    exit 1
  fi
fi

# ────────────────────────────────────────────────────────────────────────
# Fallback path: awk-based scanner (no python3+yaml available)
# ────────────────────────────────────────────────────────────────────────
#
# Scope: catches the gross shape failures. NOT a full YAML validator.
#   - Required top-level blocks present
#   - Required keys present per block
#   - context.*_path values resolve to existing files (or are null)
#   - Reject unknown context.*_path keys

record_warn "python3+PyYAML unavailable; running shallow fallback validator (some checks skipped)"

# Overlay validation requires the python path. In fallback mode we can't
# safely parse the YAML, so warn if the overlay exists and let the user know
# its contents aren't being checked.
LOCAL_CONFIG="$(dirname "$CONFIG")/config-local.yml"
if [ -f "$LOCAL_CONFIG" ]; then
  record_warn "config-local.yml exists but cannot be validated without python3+PyYAML (overlay merge skipped; install python3 + pyyaml for full validation)"
fi

# Helper — read a scalar key from a block; emits the raw value (no quote
# stripping). Returns empty string if block/key not found.
read_scalar() {
  local block="$1"
  local key="$2"
  awk -v block="$block" -v key="$key" '
    $0 ~ "^" block ":[[:space:]]*$" { in_block=1; next }
    /^[^[:space:]#]/ { in_block=0 }
    in_block && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$CONFIG"
}

# Check that a block exists (line beginning with "<block>:")
block_exists() {
  local block="$1"
  grep -qE "^${block}:[[:space:]]*$" "$CONFIG"
}

# Required blocks
for block in context branching grill memory_file; do
  if ! block_exists "$block"; then
    record_fail "missing top-level block: $block"
  fi
done

# Reject unknown top-level blocks (catches schema drift like a stale paths: block)
unknown_blocks=$(awk '
  /^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ {
    match($0, /^([A-Za-z_][A-Za-z0-9_]*):/, m)
    if (m[1] != "context" && m[1] != "branching" && m[1] != "grill" && m[1] != "memory_file" && m[1] != "suggest") {
      print m[1]
    }
  }
' "$CONFIG" 2>/dev/null)
if [ -n "$unknown_blocks" ]; then
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    record_fail "unknown top-level block: $b"
  done <<< "$unknown_blocks"
fi

# Required scalar keys per block
declare_required() {
  local block="$1"; shift
  for key in "$@"; do
    if ! awk -v block="$block" -v key="$key" '
      $0 ~ "^" block ":[[:space:]]*$" { in_block=1; next }
      /^[^[:space:]#]/ { in_block=0 }
      in_block && $0 ~ "^[[:space:]]+" key ":" { found=1; exit }
      END { exit !found }
    ' "$CONFIG"; then
      record_fail "$block.$key: missing"
    fi
  done
}

declare_required context constitution_path architecture_path testing_path glossary_path domain_path design_path
declare_required branching branch_pattern
declare_required grill question_cap
declare_required memory_file path character_limit

# context.*_path values: must be null or point to an existing file
for key in constitution_path architecture_path testing_path glossary_path domain_path design_path; do
  v="$(read_scalar context "$key")"
  if [ -z "$v" ]; then
    continue  # already reported as missing above (or value is empty — treated as null)
  fi
  if [ "$v" = "null" ] || [ "$v" = "~" ]; then
    continue
  fi
  # Expand tilde
  case "$v" in
    "~/"*) expanded="$HOME/${v#~/}" ;;
    *) expanded="$v" ;;
  esac
  # Make relative paths repo-rooted
  case "$expanded" in
    /*) candidate="$expanded" ;;
    *) candidate="$REPO_ROOT/$expanded" ;;
  esac
  if [ ! -f "$candidate" ]; then
    record_fail "context.$key: orphan path (file does not exist): $v"
  fi
done

# memory_file.path: must be null or point to an existing file (parallel to context check)
v="$(read_scalar memory_file path)"
if [ -n "$v" ] && [ "$v" != "null" ] && [ "$v" != "~" ]; then
  case "$v" in
    "~/"*) expanded="$HOME/${v#~/}" ;;
    *) expanded="$v" ;;
  esac
  case "$expanded" in
    /*) candidate="$expanded" ;;
    *) candidate="$REPO_ROOT/$expanded" ;;
  esac
  if [ ! -f "$candidate" ]; then
    record_fail "memory_file.path: orphan path (file does not exist): $v"
  fi
fi

# Reject unknown context keys (catches stale schema)
unknown_keys=$(awk '
  /^context:[[:space:]]*$/ { in_block=1; next }
  /^[^[:space:]#]/ { in_block=0 }
  in_block && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:/ {
    match($0, /^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*):/, m)
    if (m[1] != "constitution_path" && m[1] != "architecture_path" \
        && m[1] != "testing_path" \
        && m[1] != "glossary_path" && m[1] != "domain_path" \
        && m[1] != "design_path") {
      print m[1]
    }
  }
' "$CONFIG" 2>/dev/null)
if [ -n "$unknown_keys" ]; then
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    record_fail "context.$k: unknown key (allowed: constitution_path, architecture_path, testing_path, glossary_path, domain_path, design_path)"
  done <<< "$unknown_keys"
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "validate-config: PASS"
  exit 0
else
  echo "validate-config: FAIL ($ISSUE_COUNT issues)"
  exit 1
fi
