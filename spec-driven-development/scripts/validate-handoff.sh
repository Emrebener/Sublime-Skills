#!/usr/bin/env bash
# Validates a handoff document against the SDD handoff schema.
# Usage: validate-handoff.sh <path-to-handoff.md>
# Exit codes: 0 = pass (no critical issues), 1 = fail

set -u

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-handoff.md>" >&2
  exit 2
fi

HANDOFF="$1"

if [ ! -f "$HANDOFF" ]; then
  echo "ERROR: file not found: $HANDOFF" >&2
  exit 2
fi

CRITICAL=0
WARNINGS=0

report_critical() {
  echo "CRITICAL: $1"
  CRITICAL=$((CRITICAL + 1))
}

report_warning() {
  echo "WARNING: $1"
  WARNINGS=$((WARNINGS + 1))
}

# 1. Filename pattern
# Strip trailing .tmp if present (handoffs are validated as staged .tmp files
# before atomic mv to the final name)
FILENAME=$(basename "$HANDOFF")
FILENAME_FOR_PATTERN="${FILENAME%.tmp}"
if ! echo "$FILENAME_FOR_PATTERN" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]*(-[0-9]+)?\.md$"; then
  report_critical "filename does not match YYYY-MM-DD-<kebab-title>.md pattern: $FILENAME_FOR_PATTERN"
fi

# 2. Required sections
REQUIRED_SECTIONS=(
  "^# Handoff:"
  "^## Quick context"
  "^## Source artifacts"
  "^## What got built"
  "^## Build highlights"
  "^## Test status"
  "^## Open concerns"
  "^## If you're continuing this work"
  "^## Redactions"
)

for pattern in "${REQUIRED_SECTIONS[@]}"; do
  if ! grep -qE "$pattern" "$HANDOFF"; then
    report_critical "missing required section matching: $pattern"
  fi
done

# 3. Secret-like patterns that should have been redacted
# If any of these appear LITERALLY in the doc, redaction failed.
SECRET_PATTERNS=(
  'sk-[A-Za-z0-9]{20,}'                    # OpenAI / Anthropic-style
  'sk-ant-[A-Za-z0-9_-]{20,}'              # Anthropic explicit
  'AKIA[0-9A-Z]{16}'                       # AWS access key
  'ASIA[0-9A-Z]{16}'                       # AWS temp key
  'ghp_[A-Za-z0-9]{20,}'                   # GitHub personal token
  'gho_[A-Za-z0-9]{20,}'                   # GitHub OAuth token
  'ghu_[A-Za-z0-9]{20,}'                   # GitHub user token
  'ghs_[A-Za-z0-9]{20,}'                   # GitHub server token
  'ghr_[A-Za-z0-9]{20,}'                   # GitHub refresh token
  'eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'  # JWT
  '-----BEGIN [A-Z ]+PRIVATE KEY-----'    # SSH/PGP private key
  'https?://[a-zA-Z0-9._~-]+:[^@[:space:]]+@'  # URL with credentials
)

for pat in "${SECRET_PATTERNS[@]}"; do
  if grep -qE "$pat" "$HANDOFF"; then
    line=$(grep -nE "$pat" "$HANDOFF" | head -1 | cut -d: -f1)
    report_critical "potential unredacted secret matching pattern at line $line — redact before committing"
  fi
done

# 4. Sensitive env var value heuristic — look for assignments like *_SECRET = "value" or *_TOKEN = "value"
# We allow the env var NAME to appear; we disallow the value.
if grep -qE '(_SECRET|_PASSWORD|_TOKEN|_API_KEY|_KEY)\s*[:=]\s*["'\'']?[A-Za-z0-9_-]{8,}' "$HANDOFF"; then
  line=$(grep -nE '(_SECRET|_PASSWORD|_TOKEN|_API_KEY|_KEY)\s*[:=]\s*["'\'']?[A-Za-z0-9_-]{8,}' "$HANDOFF" | head -1 | cut -d: -f1)
  report_critical "looks like a sensitive env var value assignment is present at line $line — reference by name only"
fi

# 5. ADR section formatting (if present, ensure it's references not full content)
# Heuristic: if "Source artifacts" section contains a heading deeper than h3, may be duplicating ADR content
SOURCE_END_LINE=$(grep -nE "^## (What got built|Build highlights)" "$HANDOFF" | head -1 | cut -d: -f1 || true)
SOURCE_START_LINE=$(grep -nE "^## Source artifacts" "$HANDOFF" | head -1 | cut -d: -f1 || true)
if [ -n "$SOURCE_START_LINE" ] && [ -n "$SOURCE_END_LINE" ]; then
  if sed -n "${SOURCE_START_LINE},${SOURCE_END_LINE}p" "$HANDOFF" | grep -qE "^####|^### Context|^### Decision|^### Consequences"; then
    report_warning "Source artifacts section may be duplicating ADR content — reference by path + one-line summary only"
  fi
fi

# 6. Placeholder scan (handoffs shouldn't have these — the doc is generated, not drafted)
PLACEHOLDER_PATTERNS=(
  "TBD"
  "TODO"
  "FIXME"
  "<your-"
  "\[your-"
)
for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
  if grep -qiE "$pat" "$HANDOFF"; then
    lines=$(grep -niE "$pat" "$HANDOFF" | head -3 | tr '\n' ';' | sed 's/;$//')
    report_critical "placeholder pattern '$pat' found at: $lines"
  fi
done

# 7. Soft length guard
LINES=$(wc -l < "$HANDOFF")
if [ "$LINES" -gt 800 ]; then
  report_warning "handoff is $LINES lines long; may be duplicating source artifacts (soft threshold: 800)"
fi

echo ""
echo "----"
if [ "$CRITICAL" -eq 0 ]; then
  echo "PASS — $WARNINGS warning(s), 0 critical issues"
  exit 0
else
  echo "FAIL — $CRITICAL critical issue(s), $WARNINGS warning(s)"
  exit 1
fi
