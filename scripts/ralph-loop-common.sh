#!/usr/bin/env bash
#
# Shared loop machinery for Ralph wrappers.
#
# The wrapper that sources this file must define:
#   RALPH_RUNNER_NAME   Human-readable runner name.
#   RALPH_COMMAND_DESC  Human-readable command description.
#   ralph_invoke_agent  Function that runs one agent invocation.

RALPH_PROMPT="${RALPH_PROMPT:-/ss-agile-advance-milestones}"
MAX_ITER="${MAX_ITER:-20}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"
RALPH_TUI="${RALPH_TUI:-0}"
RALPH_TUI_CMD="${RALPH_TUI_CMD:-/home/emre/Projeler/Ralph-Loop-TUI/ralph-loop-tui}"

i=0
final_state=""
HEARTBEAT_PID=""
TUI_PID=""
ITER_START=""
TOTAL_START=""
OUTPUT_FILE=""
EVENT_FILE=""

ralph_validate_common() {
  if [ ! -d ".git" ]; then
    echo "Error: not in a git repo. Run this from your project root." >&2
    echo "Current dir: $(pwd)" >&2
    exit 1
  fi

  if ! [[ "$MAX_ITER" =~ ^[0-9]+$ ]] || [ "$MAX_ITER" -lt 1 ]; then
    echo "Error: --iter must be a positive integer (got: $MAX_ITER)." >&2
    exit 1
  fi
}

ralph_ts_prefix() {
  awk -v start="$ITER_START" '{
    elapsed = systime() - start;
    mins = int(elapsed / 60);
    secs = elapsed % 60;
    printf "[%s | +%dm%02ds] %s\n", strftime("%H:%M:%S"), mins, secs, $0;
    fflush();
  }'
}

ralph_b64() {
  base64 -w0
}

ralph_emit() {
  if [ "$RALPH_TUI" != "1" ] || [ -z "$EVENT_FILE" ]; then
    return 0
  fi
  printf '%s\n' "$*" >> "$EVENT_FILE"
}

ralph_tui_alive() {
  [ "$RALPH_TUI" = "1" ] && [ -n "$TUI_PID" ] && kill -0 "$TUI_PID" 2>/dev/null
}

ralph_emit_text() {
  local type="$1"
  local text="$2"
  local encoded
  encoded=$(printf '%s' "$text" | ralph_b64)
  ralph_emit "$type	$(date +%s)	$encoded"
}

ralph_print() {
  if ralph_tui_alive; then
    ralph_emit_text message "$*"
  else
    echo "$*"
  fi
}

ralph_blank() {
  if ralph_tui_alive; then
    ralph_emit_text message ""
  else
    echo
  fi
}

ralph_capture_output() {
  local line
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$OUTPUT_FILE"
    if ralph_tui_alive; then
      ralph_emit_text log "$line"
      if [[ "$line" == *"▶ Step "* ]]; then
        ralph_emit_text step "$line"
      fi
      if [[ "$line" =~ RALPH_EXIT:\ ([a-z-]+) ]]; then
        ralph_emit "marker	$(date +%s)	${BASH_REMATCH[1]}"
      fi
    else
      printf '%s\n' "$line"
    fi
  done
}

ralph_heartbeat_loop() {
  while true; do
    sleep "$HEARTBEAT_INTERVAL"
    local elapsed=$(( $(date +%s) - ITER_START ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    if ralph_tui_alive; then
      ralph_emit "heartbeat	$(date +%s)	$elapsed"
    else
      printf "  heartbeat: %dm%02ds elapsed, still running...\n" "$mins" "$secs"
    fi
  done
}

ralph_cleanup_heartbeat() {
  if [ -n "$HEARTBEAT_PID" ] && kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi
  HEARTBEAT_PID=""
}

ralph_cleanup() {
  ralph_cleanup_heartbeat
  if [ -n "$TUI_PID" ] && kill -0 "$TUI_PID" 2>/dev/null; then
    wait "$TUI_PID" 2>/dev/null || true
  fi
  if [ -n "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
  fi
  if [ -n "$EVENT_FILE" ]; then
    rm -f "$EVENT_FILE"
  fi
}

ralph_interrupt() {
  ralph_emit "finish	$(date +%s)	interrupted	$i"
  ralph_cleanup
  echo
  echo "Interrupted at iteration $i. Stopping."
  exit 130
}

ralph_extract_state() {
  grep -oE 'RALPH_EXIT: [a-z-]+' "$OUTPUT_FILE" | tail -1 | awk '{print $2}' || true
}

ralph_print_header() {
  ralph_print "Ralph loop starting."
  ralph_print "Runner: $RALPH_RUNNER_NAME"
  ralph_print "Max iterations: $MAX_ITER"
  ralph_print "Agent command: $RALPH_COMMAND_DESC"
  ralph_print "Prompt: $RALPH_PROMPT"
  ralph_print "Heartbeat every ${HEARTBEAT_INTERVAL}s during each iteration."
  ralph_blank
}

ralph_start_tui() {
  if [ "$RALPH_TUI" != "1" ]; then
    return 0
  fi
  if [ ! -x "$RALPH_TUI_CMD" ]; then
    echo "Warning: TUI requested but renderer is not executable: $RALPH_TUI_CMD" >&2
    echo "Falling back to normal streaming output." >&2
    RALPH_TUI=0
    return 0
  fi

  EVENT_FILE=$(mktemp -t ralph-loop-events.XXXXXX)
  "$RALPH_TUI_CMD" "$EVENT_FILE" &
  TUI_PID=$!
  ralph_emit "start	$(date +%s)	$MAX_ITER	$(printf '%s' "$RALPH_RUNNER_NAME" | ralph_b64)	$(printf '%s' "$RALPH_COMMAND_DESC" | ralph_b64)	$(printf '%s' "$RALPH_PROMPT" | ralph_b64)"
}

ralph_run_loop() {
  ralph_validate_common
  OUTPUT_FILE=$(mktemp -t ralph-loop.XXXXXX)
  TOTAL_START=$(date +%s)

  trap ralph_interrupt INT
  trap ralph_cleanup EXIT

  ralph_start_tui
  ralph_print_header

  while [ "$i" -lt "$MAX_ITER" ]; do
    i=$((i + 1))
    ITER_START=$(date +%s)
    : > "$OUTPUT_FILE"

    ralph_emit "iteration_start	$(date +%s)	$i	$MAX_ITER"

    ralph_print "============================================================"
    ralph_print "  Ralph loop iteration $i / $MAX_ITER  ($(date '+%Y-%m-%d %H:%M:%S'))"
    ralph_print "============================================================"
    ralph_blank

    ralph_heartbeat_loop &
    HEARTBEAT_PID=$!

    set +e
    ralph_invoke_agent 2>&1 | ralph_ts_prefix | ralph_capture_output
    local agent_status=${PIPESTATUS[0]}
    set -e

    ralph_cleanup_heartbeat

    local state
    state=$(ralph_extract_state)

    ralph_blank
    case "$state" in
      continue)
        ralph_print "Iteration $i complete. Continuing to next."
        ;;
      all-done)
        ralph_print "All milestones closed. Ralph loop done."
        final_state="all-done"
        break
        ;;
      stuck)
        ralph_print "Current milestone is stuck. Human attention needed."
        ralph_print "Resolve the dependency graph, then re-run this script."
        final_state="stuck"
        break
        ;;
      error)
        ralph_print "Skill reported an error. Inspect the output above."
        final_state="error"
        break
        ;;
      "")
        ralph_print "No RALPH_EXIT marker found in output. Bailing for safety."
        if [ "$agent_status" -ne 0 ]; then
          ralph_print "Agent command exit status: $agent_status"
        fi
        ralph_print "Inspect the output above and check the skill."
        final_state="no-marker"
        break
        ;;
      *)
        ralph_print "Unknown RALPH_EXIT state: '$state'. Bailing."
        final_state="unknown:$state"
        break
        ;;
    esac
  done

  if [ -z "$final_state" ]; then
    ralph_blank
    ralph_print "Hit max iteration cap ($MAX_ITER) without a terminal marker."
    ralph_print "If real work is still happening, re-run with a higher cap."
    final_state="max-iter-cap"
  fi

  ralph_blank
  ralph_print "============================================================"
  ralph_print "  Ralph loop final state: $final_state ($i iterations)"
  ralph_print "============================================================"
  ralph_emit "finish	$(date +%s)	$final_state	$i"

  case "$final_state" in
    all-done) exit 0 ;;
    *)        exit 1 ;;
  esac
}
