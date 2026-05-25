# Ralph-Loop TUI

Minimal terminal UI for the Sublime-Skills Ralph loop wrappers. Ships as
`scripts/ralph-loop-tui` (a standalone Python curses script, stdlib-only)
and is invoked automatically by the loop wrappers when `--tui` is passed.

Override the renderer path with `RALPH_TUI_CMD=/path/to/alt-renderer` or
`--tui-cmd /path/to/alt-renderer` if you want to substitute your own.

The renderer consumes the event file produced by:

```bash
"$SUBLIME_SKILLS_HOME/scripts/ralph-loop-codex.sh" --tui --iter 50 --command "codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c model_reasoning_effort='medium'"
```

It shows total elapsed time, current-iteration elapsed time, current
iteration, last heartbeat, current `RALPH_EXIT` marker, current agile step,
and a scrolling log tail.

Keys:

- `s` toggles "stop after current iteration". The running iteration is not
  interrupted; the Ralph loop stops before launching the next one.
- `q` exits the TUI view. If the loop is still running, it falls back to
  normal streaming logs.

The TUI exits automatically a few seconds after the loop finishes.
