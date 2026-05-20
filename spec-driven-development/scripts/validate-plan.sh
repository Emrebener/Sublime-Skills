#!/usr/bin/env bash
# Validates a plan.md against the SDD plan schema.
# Usage: validate-plan.sh <path-to-plan.md>
# Exit codes: 0 = pass (no critical issues), 1 = fail

set -u

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-plan.md>" >&2
  exit 2
fi

PLAN="$1"

if [ ! -f "$PLAN" ]; then
  echo "ERROR: file not found: $PLAN" >&2
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

# 1. Required sections
REQUIRED_SECTIONS=(
  "^# Plan:"
  "^## Goal"
  "^## Architecture"
  "^## Tech Stack"
  "^## File Structure"
)

for pattern in "${REQUIRED_SECTIONS[@]}"; do
  if ! grep -qE "$pattern" "$PLAN"; then
    report_critical "missing required section matching: $pattern"
  fi
done

# 2. At least one Phase
if ! grep -qE "^### Phase [0-9]+" "$PLAN" && ! grep -qE "^## Phases" "$PLAN"; then
  report_critical "no Phase sections found (expected '### Phase 1 — ...' style)"
fi

# 3. At least one task with T### ID
if ! grep -qE "T[0-9]{3,}" "$PLAN"; then
  report_critical "no T### task IDs found"
fi

# 3b. T### IDs must be unique when used as task definitions.
# A task definition is "### Task T###" per the writing-plans format.
DUPE_TASKS=$(grep -oE "^### Task T[0-9]{3,}" "$PLAN" \
  | sed 's/^### Task //' \
  | sort \
  | uniq -d)
if [ -n "$DUPE_TASKS" ]; then
  while IFS= read -r dup_id; do
    [ -z "$dup_id" ] && continue
    lines=$(grep -nE "^### Task ${dup_id}\b" "$PLAN" | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    report_critical "duplicate task ID '$dup_id' defined at lines: $lines"
  done <<< "$DUPE_TASKS"
fi

# 4. Each task should reference Requirements
# Count task headers vs. Requirements references
TASK_HEADERS=$(grep -cE "^### Task T[0-9]+" "$PLAN" || true)
REQ_REFS=$(grep -cE "\*\*Requirements:\*\*" "$PLAN" || true)
if [ "$TASK_HEADERS" -gt 0 ] && [ "$REQ_REFS" -lt "$TASK_HEADERS" ]; then
  report_warning "found $TASK_HEADERS task headers but only $REQ_REFS Requirements references — some tasks may be missing traceability"
fi

# 5. [NO-TDD] markers should have a reason on the line after them
# Find all [NO-TDD] lines and check the next non-blank line is a brief reason (not another heading)
if grep -q "\[NO-TDD\]" "$PLAN"; then
  # Get line numbers of [NO-TDD]
  while IFS= read -r line_no; do
    next_line_no=$((line_no + 1))
    next_line=$(sed -n "${next_line_no}p" "$PLAN")
    # The line after should be a reason — not blank, not another markdown heading
    if [ -z "$(echo "$next_line" | tr -d ' \t')" ] || echo "$next_line" | grep -qE "^#"; then
      report_critical "[NO-TDD] marker at line $line_no is not followed by a reason on the next line"
    fi
  done < <(grep -n "\[NO-TDD\]" "$PLAN" | cut -d: -f1)
fi

# 6. Placeholder scan
PLACEHOLDER_PATTERNS=(
  "TBD"
  "TODO"
  "TKTK"
  "FIXME"
  "implement later"
  "fill in details"
  "add appropriate error handling"
  "add validation"
  "similar to Task"
  "<placeholder>"
  "\[your-"
  "<your-"
)
for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
  if grep -qiE "$pat" "$PLAN"; then
    lines=$(grep -niE "$pat" "$PLAN" | head -3 | tr '\n' ';' | sed 's/;$//')
    report_critical "placeholder pattern '$pat' found at: $lines"
  fi
done

# 7. Forbidden diagram syntaxes
FORBIDDEN_DIAGRAMS=(
  '^\`\`\`mermaid'
  '^\`\`\`plantuml'
  '^\`\`\`puml'
  '^@startuml'
  '\\bC4Container\\b'
  '\\bC4Component\\b'
)
for pat in "${FORBIDDEN_DIAGRAMS[@]}"; do
  if grep -qE "$pat" "$PLAN"; then
    line=$(grep -nE "$pat" "$PLAN" | head -1 | cut -d: -f1)
    report_critical "forbidden diagram syntax matching '$pat' at line $line"
  fi
done

# 8. Soft length guard
LINES=$(wc -l < "$PLAN")
if [ "$LINES" -gt 2000 ]; then
  report_warning "plan is $LINES lines long; may indicate spec needed decomposition (soft threshold: 2000)"
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
