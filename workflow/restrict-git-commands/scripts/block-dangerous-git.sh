#!/bin/bash

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq is required by block-dangerous-git.sh but not installed." >&2
  exit 2
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

DANGEROUS_PATTERNS=(
  "git\s+push"
  "git\s+reset\s+--hard"
  "git\s+clean\s+-[A-Za-z]*f"
  "git\s+branch\s+-D"
  "git\s+branch\s+(-d\s+)?--delete\s+--force"
  "git\s+checkout\s+\."
  "git\s+restore\s+\."
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0
