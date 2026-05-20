---
name: restrict-git-commands
description: Set up Claude Code hooks to block destructive git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code.
---

# Restrict Git Commands

Sets up a PreToolUse hook that intercepts and blocks destructive git commands before Claude executes them.

## What Gets Blocked

- `git push` (all variants including `--force`, `-f`, `--force-with-lease`)
- `git reset --hard`
- `git clean -f` (and any flag combination containing `f`, e.g. `-fd`, `-fdx`)
- `git branch -D` and `git branch --delete --force`
- `git checkout .` / `git restore .`

Matching is whitespace-flexible (`git  push`, `git\tpush` both match) but substring-based, so the patterns also trigger if a blocked phrase appears inside a longer command (e.g. `echo hi && git push`).

When blocked, Claude sees a stderr message and the hook exits with code 2, which prevents the Bash call.

## Steps

### 1. Ask scope and customization

Ask the user two things up front:

1. Install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`)?
2. Any patterns to add or remove from the default blocked list?

### 2. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to the target location based on scope:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 3. Add hook to settings

Add to the appropriate settings file:

**Project** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into existing `hooks.PreToolUse` array — don't overwrite other settings.

### 4. Apply customizations

If the user requested pattern changes in step 1, edit the copied script's `DANGEROUS_PATTERNS` array accordingly. Patterns are extended regex (`grep -E`).

### 5. Verify

Run a quick test:

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | <path-to-script>
```

Should exit with code 2 and print a BLOCKED message to stderr.
