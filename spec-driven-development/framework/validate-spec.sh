#!/usr/bin/env bash
# Validates a spec.md against the SDD spec schema.
# Usage: validate-spec.sh <path-to-spec.md>
# Output: prints issues, one per line, prefixed with severity.
# Exit codes: 0 = pass (no critical issues), 1 = fail (at least one critical issue)

set -u

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-spec.md>" >&2
  exit 2
fi

SPEC="$1"

if [ ! -f "$SPEC" ]; then
  echo "ERROR: file not found: $SPEC" >&2
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
  "^# Spec:"
  "^## Goal"
  "^## User Stories"
  "^## Functional Requirements"
  "^## Success Criteria"
  "^## Edge Cases"
  "^## Assumptions"
  "^## Out-of-Scope"
)

for pattern in "${REQUIRED_SECTIONS[@]}"; do
  if ! grep -qE "$pattern" "$SPEC"; then
    section_name="${pattern//^## /}"
    section_name="${section_name//^# /}"
    report_critical "missing required section matching: $pattern"
  fi
done

# 2. At least one Functional Requirement (FR-NNN) and one Success Criterion (SC-NNN)
if ! grep -qE "FR-[0-9]{3}" "$SPEC"; then
  report_critical "no FR-### functional requirement IDs found"
fi
if ! grep -qE "SC-[0-9]{3}" "$SPEC"; then
  report_critical "no SC-### success criterion IDs found"
fi

# 2b. Each FR-### and SC-### ID must be unique when used as a definition.
# A definition is the FIRST appearance of the ID at the start of a line item:
# either "- **FR-NNN:**" (the canonical pattern from writing-specs) or "**FR-NNN:**"
# at the start of a paragraph. Cross-references in body text are OK and don't count.
check_duplicate_ids() {
  local prefix="$1"
  local label="$2"
  # Extract IDs from lines that look like definitions: "- **FR-001:**" or "**FR-001:**"
  local dupes
  dupes=$(grep -oE "\*\*${prefix}-[0-9]{3}:?\*\*" "$SPEC" \
    | sed 's/\*\*//g; s/://g' \
    | sort \
    | uniq -d)
  if [ -n "$dupes" ]; then
    while IFS= read -r dup_id; do
      [ -z "$dup_id" ] && continue
      lines=$(grep -nE "\*\*${dup_id}:?\*\*" "$SPEC" | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
      report_critical "duplicate $label ID '$dup_id' defined at lines: $lines"
    done <<< "$dupes"
  fi
}
check_duplicate_ids "FR" "functional requirement"
check_duplicate_ids "SC" "success criterion"

# 3. At least one User Story with priority (P1/P2/P3 etc.)
if ! grep -qE "\(P[0-9]+\)" "$SPEC"; then
  report_critical "no user story priorities (P1/P2/...) found"
fi

# 4. Each story should have at least one acceptance scenario or EARS criterion
# Look for "Acceptance scenarios" or "Acceptance criteria (EARS)" near story headings
STORY_COUNT=$(grep -cE "^### Story [0-9]+" "$SPEC" || true)
ACCEPT_COUNT=$(grep -cE "\*\*Acceptance (scenarios|criteria \(EARS\))\*\*" "$SPEC" || true)
if [ "$STORY_COUNT" -gt 0 ] && [ "$ACCEPT_COUNT" -lt "$STORY_COUNT" ]; then
  report_warning "found $STORY_COUNT stories but only $ACCEPT_COUNT acceptance sections — some stories may be missing acceptance criteria"
fi

# 5. Placeholder scan
PLACEHOLDER_PATTERNS=(
  "TBD"
  "TODO"
  "TKTK"
  "\[placeholder\]"
  "\[fill in"
  "\[your-"
  "<your-"
  "FIXME"
)
for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
  if grep -qiE "$pat" "$SPEC"; then
    lines=$(grep -niE "$pat" "$SPEC" | head -3 | tr '\n' ';' | sed 's/;$//')
    report_critical "placeholder pattern '$pat' found at: $lines"
  fi
done

# 6. Forbidden diagram syntaxes
FORBIDDEN_DIAGRAMS=(
  '^\`\`\`mermaid'
  '^\`\`\`plantuml'
  '^\`\`\`puml'
  '^@startuml'
  '\\bC4Container\\b'
  '\\bC4Component\\b'
)
for pat in "${FORBIDDEN_DIAGRAMS[@]}"; do
  if grep -qE "$pat" "$SPEC"; then
    line=$(grep -nE "$pat" "$SPEC" | head -1 | cut -d: -f1)
    report_critical "forbidden diagram syntax matching '$pat' at line $line"
  fi
done

# 7. Soft check: line count guard (warn if very long — likely too big for one spec)
LINES=$(wc -l < "$SPEC")
if [ "$LINES" -gt 800 ]; then
  report_warning "spec is $LINES lines long; may need decomposition (soft threshold: 800)"
fi

# Final report
echo ""
echo "----"
if [ "$CRITICAL" -eq 0 ]; then
  echo "PASS — $WARNINGS warning(s), 0 critical issues"
  exit 0
else
  echo "FAIL — $CRITICAL critical issue(s), $WARNINGS warning(s)"
  exit 1
fi
