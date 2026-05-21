#!/usr/bin/env bash
# Validates .sdd/config.yml structurally and semantically.
#
# Usage:
#   ./spec-driven-development/scripts/validate-config.sh [config-path]
#
# Default config-path: <repo-root>/.sdd/config.yml
#
# Exit codes:
#   0 — PASS  (config is structurally valid; all referenced files exist or are null)
#   1 — FAIL  (one or more issues; findings on stderr)
#   2 — config file not found
#   3 — usage error
#
# Output:
#   - One finding per line on stderr, each prefixed with `FAIL:` or `WARN:`.
#   - Final summary line on stdout: `validate-config: PASS` or `validate-config: FAIL (N issues)`.
#
# Used by:
#   - project-bootstrap/bootstrapping-project (fix-and-retry loop)
#   - spec-driven-development/sdd-coordinator (Step 2 halt check)
#   - future audit skill
#
# Implementation notes:
#   - Prefers python3+pyyaml when available for proper YAML parsing.
#   - Falls back to an awk-based scanner that catches the most common shape issues
#     when python3 is missing. The fallback is intentionally strict about
#     undocumented constructs (lists, anchors, multi-line block scalars besides
#     `pr_body_template`'s `|`) — same scope as the rest of the SDD scripts.

set -u

usage() {
  echo "Usage: $0 [config-path]" >&2
  exit 3
}

if [ $# -gt 1 ]; then
  usage
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="${1:-$REPO_ROOT/.sdd/config.yml}"

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

# Required top-level blocks
required_blocks = ["paths", "context", "preflight", "grill", "memory_file", "finishing"]
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

# ── paths block ────────────────────────────────────────────────────
for key in ["spec_dir", "adr_dir", "handoff_dir"]:
    v = get("paths", key)
    if v == "__MISSING__":
        fail(f"paths.{key}: missing")
    elif not isinstance(v, str) or not v.strip():
        fail(f"paths.{key}: must be a non-empty string, got {v!r}")

# ── context block ──────────────────────────────────────────────────
context_keys = ["constitution_path", "architecture_path", "glossary_path", "domain_path"]
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

# ── preflight block ────────────────────────────────────────────────
v = get("preflight", "branch_pattern")
if v == "__MISSING__":
    fail("preflight.branch_pattern: missing")
elif not isinstance(v, str) or not v.strip():
    fail(f"preflight.branch_pattern: must be a non-empty string, got {v!r}")
elif "{short-name}" not in v:
    warn(f"preflight.branch_pattern does not contain {{short-name}} placeholder: {v!r}")

v = get("preflight", "use_worktree")
if v == "__MISSING__":
    fail("preflight.use_worktree: missing")
elif not isinstance(v, bool):
    fail(f"preflight.use_worktree: must be a boolean, got {type(v).__name__}")

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
elif v is not None and (not isinstance(v, str) or not v.strip()):
    fail(f"memory_file.path: must be null or a non-empty string, got {v!r}")

v = get("memory_file", "character_limit")
if v == "__MISSING__":
    fail("memory_file.character_limit: missing")
elif not isinstance(v, int) or isinstance(v, bool):
    fail(f"memory_file.character_limit: must be an integer, got {type(v).__name__}")
elif v < 1000:
    fail(f"memory_file.character_limit: must be at least 1000, got {v}")

# ── finishing block ────────────────────────────────────────────────
v = get("finishing", "mode")
allowed_modes = {"prompt", "leave", "merge-local", "pr", "auto"}
if v == "__MISSING__":
    fail("finishing.mode: missing")
elif v not in allowed_modes:
    fail(f"finishing.mode: must be one of {sorted(allowed_modes)}, got {v!r}")

v = get("finishing", "merge_target")
if v == "__MISSING__":
    fail("finishing.merge_target: missing")
elif not isinstance(v, str) or not v.strip():
    fail(f"finishing.merge_target: must be a non-empty string, got {v!r}")

v = get("finishing", "delete_branch_after_merge")
if v == "__MISSING__":
    fail("finishing.delete_branch_after_merge: missing")
elif not isinstance(v, bool):
    fail(f"finishing.delete_branch_after_merge: must be a boolean, got {type(v).__name__}")

v = get("finishing", "test_command")
if v == "__MISSING__":
    fail("finishing.test_command: missing (use null to auto-detect)")
elif v is not None and (not isinstance(v, str) or not v.strip()):
    fail(f"finishing.test_command: must be null or a non-empty string, got {v!r}")

v = get("finishing", "pr_command")
if v == "__MISSING__":
    fail("finishing.pr_command: missing")
elif not isinstance(v, str) or not v.strip():
    fail(f"finishing.pr_command: must be a non-empty string, got {v!r}")
else:
    if "{title}" not in v:
        warn("finishing.pr_command does not contain {title} placeholder")
    if "{body_file}" not in v:
        warn("finishing.pr_command does not contain {body_file} placeholder")

v = get("finishing", "pr_body_template")
if v == "__MISSING__":
    fail("finishing.pr_body_template: missing")
elif not isinstance(v, str) or not v.strip():
    fail(f"finishing.pr_body_template: must be a non-empty string, got {v!r}")

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
#   - finishing.mode is in the allowed enum
#   - Reject unknown context.*_path keys

record_warn "python3+PyYAML unavailable; running shallow fallback validator (some checks skipped)"

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
for block in paths context preflight grill memory_file finishing; do
  if ! block_exists "$block"; then
    record_fail "missing top-level block: $block"
  fi
done

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

declare_required paths spec_dir adr_dir handoff_dir
declare_required context constitution_path architecture_path glossary_path domain_path
declare_required preflight branch_pattern use_worktree
declare_required grill question_cap
declare_required memory_file path character_limit
declare_required finishing mode merge_target delete_branch_after_merge test_command pr_command pr_body_template

# context.*_path values: must be null or point to an existing file
for key in constitution_path architecture_path glossary_path domain_path; do
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

# finishing.mode enum
v="$(read_scalar finishing mode)"
if [ -n "$v" ]; then
  case "$v" in
    prompt|leave|merge-local|pr|auto) : ;;
    *) record_fail "finishing.mode: must be one of [prompt, leave, merge-local, pr, auto], got '$v'" ;;
  esac
fi

# Reject unknown context keys (catches stale schema)
unknown_keys=$(awk '
  /^context:[[:space:]]*$/ { in_block=1; next }
  /^[^[:space:]#]/ { in_block=0 }
  in_block && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:/ {
    match($0, /^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*):/, m)
    if (m[1] != "constitution_path" && m[1] != "architecture_path" \
        && m[1] != "glossary_path" && m[1] != "domain_path") {
      print m[1]
    }
  }
' "$CONFIG" 2>/dev/null)
if [ -n "$unknown_keys" ]; then
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    record_fail "context.$k: unknown key (allowed: constitution_path, architecture_path, glossary_path, domain_path)"
  done <<< "$unknown_keys"
fi

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "validate-config: PASS"
  exit 0
else
  echo "validate-config: FAIL ($ISSUE_COUNT issues)"
  exit 1
fi
