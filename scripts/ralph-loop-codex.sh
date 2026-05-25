#!/usr/bin/env bash
#
# Ralph loop wrapper for Codex CLI.
#
# Repeatedly invokes a user-supplied Codex command until the agile coordinator
# skill emits a non-continue RALPH_EXIT marker.
#
# Usage:
#   ./scripts/ralph-loop-codex.sh [options] --command "codex exec [your args]"
#
# Options:
#   -n, --iter N           Max iterations (default: 20)
#   -c, --command COMMAND  Codex command to run each iteration
#   --prompt PROMPT        Prompt to append to the command
#                          (default: $ss-agile-advancing-milestones)
#   --tui                  Show a minimal terminal UI instead of raw streaming logs
#   --tui-cmd PATH         TUI renderer path
#   -h, --help             Show this help
#
# Examples:
#   ./scripts/ralph-loop-codex.sh -c "codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c model_reasoning_effort='high'"
#   ./scripts/ralph-loop-codex.sh --iter 50 --command "codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5"
#
#   $SUBLIME_SKILLS_HOME/scripts/ralph-loop-codex.sh --iter 50 --command "codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c model_reasoning_effort='medium'" --prompt '$ss-agile-advancing-milestones'
#
# The command string is evaluated by bash so normal shell quoting works. Pass
# only commands you trust. A bare positional command string is still accepted
# for compatibility, but wrapper options must come before it.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

MAX_ITER=20
RALPH_PROMPT='$ss-agile-advancing-milestones'
RALPH_TUI=0
RALPH_TUI_CMD="${RALPH_TUI_CMD:-${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}/scripts/ralph-loop-tui}"
CODEX_COMMAND=""

usage() {
  sed -n '2,/^$/ p' "$0" | sed 's/^#\s\?//'
}

if [[ $# -gt 0 && "${1}" =~ ^[0-9]+$ ]]; then
  MAX_ITER="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --iter | --max-iter)
    MAX_ITER="${2:-}"
    shift 2
    ;;
  -c | --command)
    CODEX_COMMAND="${2:-}"
    shift 2
    ;;
  --prompt)
    RALPH_PROMPT="${2:-}"
    shift 2
    ;;
  --tui)
    RALPH_TUI=1
    shift
    ;;
  --tui-cmd)
    RALPH_TUI_CMD="${2:-}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    CODEX_COMMAND="${1:-}"
    shift || true
    break
    ;;
  *)
    CODEX_COMMAND="$1"
    shift
    break
    ;;
  esac
done

if [ $# -gt 0 ]; then
  echo "Error: unexpected extra arguments after command string: $*" >&2
  echo "Pass the Codex command as one quoted string." >&2
  exit 1
fi

if [ -z "$CODEX_COMMAND" ]; then
  echo "Error: missing Codex command string." >&2
  echo "Example: $0 -c \"codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c model_reasoning_effort='high'\"" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: 'codex' CLI not found in PATH." >&2
  exit 1
fi

if [[ "$CODEX_COMMAND" != *"--dangerously-bypass-approvals-and-sandbox"* && "$CODEX_COMMAND" != *"-s danger-full-access"* && "$CODEX_COMMAND" != *"--sandbox danger-full-access"* ]]; then
  echo "Warning: Codex command does not appear to disable sandboxing." >&2
  echo "Ralph usually needs GitHub/network/git write access. Consider adding:" >&2
  echo "  --dangerously-bypass-approvals-and-sandbox" >&2
  echo >&2
fi

RALPH_RUNNER_NAME="Codex CLI"
RALPH_COMMAND_DESC="$CODEX_COMMAND"

ralph_invoke_agent() {
  bash -lc "exec ${CODEX_COMMAND} \"\$@\"" ralph-loop "$RALPH_PROMPT"
}

# shellcheck source=scripts/ralph-loop-common.sh
source "$SCRIPT_DIR/ralph-loop-common.sh"
ralph_run_loop
