#!/usr/bin/env bash
#
# Ralph loop wrapper for Claude Code.
#
# Repeatedly invokes the agile milestone command until the coordinator skill
# emits a non-continue RALPH_EXIT marker.
#
# Usage:
#   ./scripts/ralph-loop-claude-code.sh [options]
#
# Options:
#   -n, --iter N           Max iterations (default: 20)
#   -m, --model MODEL      Claude model to pass to claude.
#   -e, --effort LEVEL     Effort level: low | medium | high | xhigh | max
#   -p, --prompt PROMPT    Prompt/command to send (default: /ss-agile-advance-milestones)
#   --tui                  Show a minimal terminal UI instead of raw streaming logs
#   --tui-cmd PATH         TUI renderer path
#   -h, --help             Show this help
#
# Examples:
#   ./scripts/ralph-loop-claude-code.sh --iter 50 --model opus --effort high
#   ./scripts/ralph-loop-claude-code.sh --tui --iter 50 --model sonnet --effort high
#
# Backward compatibility: a single positional integer is treated as --iter.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

MAX_ITER=20
MODEL=""
EFFORT=""
RALPH_PROMPT="/ss-agile-advance-milestones"
RALPH_TUI=0
RALPH_TUI_CMD="${RALPH_TUI_CMD:-${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}/scripts/ralph-loop-tui}"

usage() {
  sed -n '2,/^$/ p' "$0" | sed 's/^#\s\?//'
}

if [[ $# -gt 0 && "${1}" =~ ^[0-9]+$ ]]; then
  MAX_ITER="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--iter|--max-iter)
      MAX_ITER="${2:-}"; shift 2 ;;
    -m|--model)
      MODEL="${2:-}"; shift 2 ;;
    -e|--effort)
      EFFORT="${2:-}"; shift 2 ;;
    -p|--prompt)
      RALPH_PROMPT="${2:-}"; shift 2 ;;
    --tui)
      RALPH_TUI=1; shift ;;
    --tui-cmd)
      RALPH_TUI_CMD="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
  esac
done

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: 'claude' CLI not found in PATH." >&2
  exit 1
fi

if [[ -n "$EFFORT" ]] && ! [[ "$EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]]; then
  echo "Error: --effort must be one of: low, medium, high, xhigh, max (got: $EFFORT)." >&2
  exit 1
fi

RALPH_RUNNER_NAME="Claude Code"
RALPH_COMMAND_DESC="claude -p --dangerously-skip-permissions --verbose"
[[ -n "$MODEL" ]] && RALPH_COMMAND_DESC+=" --model $MODEL"
[[ -n "$EFFORT" ]] && RALPH_COMMAND_DESC+=" --effort $EFFORT"

ralph_invoke_agent() {
  local args=(-p --dangerously-skip-permissions --verbose)
  [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
  [[ -n "$EFFORT" ]] && args+=(--effort "$EFFORT")
  args+=("$RALPH_PROMPT")

  claude "${args[@]}"
}

# shellcheck source=scripts/ralph-loop-common.sh
source "$SCRIPT_DIR/ralph-loop-common.sh"
ralph_run_loop
