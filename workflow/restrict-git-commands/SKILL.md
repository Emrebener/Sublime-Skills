---
name: restrict-git-commands
description: Establishes a policy that destructive git operations (push, reset --hard, clean -f, branch -D, checkout . / restore .) require explicit user authorization before execution. Use at session start to commit to the policy, or whenever about to run a git command. Tool-agnostic via instruction; a Claude Code `PreToolUse` hook script is bundled at scripts/block-dangerous-git.sh as an optional drop-in for users who want deterministic harness-level enforcement.
---

# Restrict Git Commands

## Overview

Some git operations are unrecoverable: a force-push rewrites remote history, a `reset --hard` discards uncommitted work, `clean -f` deletes untracked files irrevocably. When you run these without asking, the user discovers the loss minutes or hours later — usually after recovery isn't possible.

This skill commits you to a baseline policy: **destructive git operations require explicit user authorization before you run them.** When in doubt, ask. A five-second confirmation always beats a thirty-minute recovery.

**Core principle:** Reversibility matters more than convenience. Anything that loses work, rewrites shared history, or affects a remote needs the user's explicit "yes" — every time, every command, no exceptions for "this one's obviously safe."

**Announce at start:** "I'm using the restrict-git-commands skill — destructive git operations require your explicit authorization."

## Hard Gates

- Do NOT run any command in the table below without first asking the user and receiving a clear "yes" for THIS specific invocation
- Do NOT treat a prior session-level "yes" as authorization for a new invocation — each destructive command is a fresh ask
- Do NOT rationalize past this policy ("the user is busy", "it's a small one", "I made these commits myself" — all wrong; see Common Mistakes below)
- Do NOT bundle multiple destructive commands into a single ask — one ask per command, so the user sees each one
- If you encounter a git command you suspect is destructive but it isn't on the list, ask before running it AND flag it for the user as a candidate addition

## The Policy: Commands That Require Authorization

| Command pattern | Why it's dangerous |
|---|---|
| `git push` (including `--force`, `-f`, `--force-with-lease`) | Affects shared state; force variants rewrite remote history |
| `git reset --hard` | Discards uncommitted changes; recovery requires reflog and luck |
| `git clean -f` (and variants like `-fd`, `-fdx`) | Permanently deletes untracked files (and with `-x`, ignored files like `.env`) |
| `git branch -D` and `git branch --delete --force` | Force-deletes branches even if unmerged — work is lost |
| `git checkout .` / `git restore .` | Discards all unstaged changes in the working tree |

This list is **not exhaustive.** If you're about to run a git command and can't immediately answer "is this reversible without the reflog?", treat it as requiring authorization.

## How to Ask

Name the exact command and its consequence. Don't ask vague questions.

- ✗ "Should I push?"
- ✓ "About to run `git push --force-with-lease origin main`. This overwrites the remote `main`'s current head with your local one. Proceed? (yes/no)"

- ✗ "Want me to clean up?"
- ✓ "About to run `git reset --hard HEAD` — this discards your uncommitted changes in `src/auth.ts` and `tests/auth.test.ts`. Proceed? (yes/no)"

If the harness has an interactive yes/no question tool, use it. Otherwise a plain prompt works — the key is naming the command and consequence.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Running a destructive command because the user said yes earlier in the session | Authorization is per-command, never session-wide |
| Force-pushing because "the branch is local" | Push always affects remote; the user may have a fork or PR open |
| `git reset --hard` to "clean up" before a fresh attempt | The user may have stashed work or in-progress edits you don't know about |
| `git clean -fdx` to "start clean" | Ignored files often include `.env`, local config, build state |
| `git checkout .` because tests are failing | Revert specific files, not the whole tree |
| Skipping the ask because "obviously safe" | If it's obviously safe, the ask is also obviously fast — do it |
| Bundling multiple destructive ops into one ask | One ask per command; the user needs to see each one separately |

## Red Flags

- About to type `--force` or `-f` on any git command → STOP; ask first
- About to `git reset --hard` to "clean up" the working tree → STOP; specific file reverts are almost always what you want
- About to `git clean -fdx` to clear state → STOP; ignored files might be load-bearing
- About to delete a branch with `-D` → STOP; check `git log <branch>` first, then ask
- About to phrase an ask as "should I push?" → STOP; rewrite with the exact command and the specific consequence

## Optional: Hard Enforcement (Claude Code only)

This skill works via instruction — it commits you to a policy and trusts you to follow it. For users on Claude Code who want deterministic enforcement that doesn't rely on your compliance, this directory also ships a `PreToolUse` hook script at [`scripts/block-dangerous-git.sh`](scripts/block-dangerous-git.sh) that intercepts and blocks the same commands at the harness level.

The hook and the skill are independent. Install both for belt-and-suspenders; install just the skill on harnesses that don't support hooks; install just the hook if you prefer hard enforcement without loading the skill.

**Install (Claude Code only):**

1. Copy `scripts/block-dangerous-git.sh` to `.claude/hooks/block-dangerous-git.sh` (project-scoped) or `~/.claude/hooks/block-dangerous-git.sh` (global).
2. Make it executable: `chmod +x <path>`.
3. Add the hook to the matching `settings.json`:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "<absolute path to the hook>"
             }
           ]
         }
       ]
     }
   }
   ```

   For project-scoped installs, use `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"`.

4. Verify it blocks: `echo '{"tool_input":{"command":"git push origin main"}}' | <path>` should exit 2 and print a BLOCKED message to stderr.

The hook depends on `jq` being on the system path; if it's missing, the hook exits with a clear error rather than silently allowing the command.

The patterns in the hook script's `DANGEROUS_PATTERNS` array mirror this skill's policy table. Keep them in sync if you customize either side.
