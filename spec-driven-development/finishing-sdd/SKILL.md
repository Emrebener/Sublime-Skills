---
name: finishing-sdd
description: Use during the finishing stage of an SDD pipeline run, after implementation (and optional testing and handoff generation) are complete. Closes the run — merge, PR, keep, or discard — honoring any user config, then cleans up the state file and removes worktrees we created.
---

# Finishing SDD

## Overview

Close out an SDD run. Default is interactive (4 options); config can short-circuit to a single mode. After the chosen action: clean up worktree (if preflight created one), delete the state file (work is done).

**Core principle:** Verify before integrating. Confirm destructive actions explicitly. Restore what we displaced.

**Announce at start:** "I'm using the finishing-sdd skill to wrap up this SDD run."

## Hard Gates

- Do NOT proceed if implementation (or testing, if it was run) is in an unresolved failing state
- Do NOT discard work without typed confirmation
- Do NOT force-push, drop branches the user didn't ask to drop, or rewrite history
- Do NOT clean up a worktree we didn't create (provenance check via state file)
- Do NOT silently ignore worktree cleanup if `preflight.worktree_path` is non-null

## Checklist

1. Verify pre-finish state (tests pass, no unresolved failures)
2. Detect environment (normal repo, worktree, detached HEAD)
3. Determine mode (config override OR interactive prompt)
4. Execute chosen action
5. Clean up worktree if we created one
6. Delete state file
7. Report

## Step 1: Verify Pre-Finish State

Read the state file. Confirm:

- `stages_completed` includes implementation_complete
- If testing was run, `test_status` is `passed` or `passed_after_fixes`
- If testing was skipped (`testing_skipped`), confirm with user before proceeding: "Testing was skipped. Finish anyway?"
- If `test_status` is `failed_escalated`, do NOT proceed without user explicit confirmation — they may want to investigate first

Run the project's primary test command one more time as a sanity check.

**Resolution order for the test command:**

1. **Config override** (preferred): if `.sdd/config.yml` has `finishing.test_command` set, use exactly that command. This is the right answer for Makefile-driven projects, `nox`/`tox` setups, Maven/Gradle, monorepos with custom test runners, or any project that doesn't fit the auto-detect patterns.

   ```yaml
   finishing:
     test_command: "make test"
   ```

2. **Auto-detect** (fallback): if no config override, try in priority order and use the **first match only**:

   | If present | Run | Notes |
   |---|---|---|
   | `Makefile` (with a `test` target) | `make test` | Highest priority — projects with a Makefile usually treat that as the canonical entry point |
   | `package.json` | `npm test` | Node/JS projects |
   | `Cargo.toml` | `cargo test` | Rust |
   | `pyproject.toml` | `pytest` | Python (modern) |
   | `setup.py` | `pytest` or `python -m unittest discover` (whichever fits) | Python (legacy) |
   | `go.mod` | `go test ./...` | Go |
   | `pom.xml` | `mvn test` | Java/Maven |
   | `build.gradle` or `build.gradle.kts` | `gradle test` | Java/Gradle |

   Use `grep -q "^test:" Makefile 2>/dev/null` to verify a `test` target exists before picking `make test`.

3. **None match**: ask the user what command to run. Offer to save their answer as `.sdd/config.yml → finishing.test_command` for future runs.

**Do NOT run multiple test commands** even in polyglot repos. The config override is the right answer when one repo needs more than one runner (a Makefile target that fans out is typical).

If the chosen command fails, halt and report failures. Don't offer finishing options until tests pass (or user explicitly says "I know, finish anyway").

## Step 2: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR == GIT_COMMON` → normal repo
- `GIT_DIR != GIT_COMMON`, on a named branch → linked worktree (named)
- `GIT_DIR != GIT_COMMON`, detached HEAD → linked worktree (detached) — uncommon

Determine `BASE_BRANCH` (the merge target). Default `main`; check `.sdd/config.yml` → `finishing.merge_target`. Confirm with user if uncertain.

## Step 3: Determine Mode

Read `.sdd/config.yml` → `finishing.mode`. Use the scalar helper for convenience:

```bash
MODE=$(./spec-driven-development/scripts/get-config-value.sh finishing mode)
MODE="${MODE:-prompt}"   # default if not set
```

Possible values:

| Mode | Behavior |
|---|---|
| `prompt` (default) | Show the 4-option menu below |
| `leave` | Skip interactive menu; leave branch as-is. Equivalent to option 3. |
| `merge-local` | Skip menu; merge into `merge_target`. Equivalent to option 1. |
| `pr` | Skip menu; push and create PR. Equivalent to option 2. |
| `auto` | Pick automatically: PR if remote exists and PR command is configured; merge-local otherwise; leave if neither |

For modes other than `prompt`, still confirm with user once: "Finishing mode is `<mode>`. Proceed with that, or pick interactively? (proceed/interactive)".

## Step 4: Execute Chosen Action

### Option 1 — Merge Locally

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first; verify before removing anything
git checkout "$BASE_BRANCH"
git pull
git merge "$BRANCH"
```

**If the merge fails with conflicts** (`git status` shows `UU` entries): STOP. Tell the user which files conflicted. Do NOT attempt to auto-resolve. The user resolves and re-invokes finishing.

**If the merge fails for other reasons** (commit-hook failure on merge commit, signing failure, etc.): STOP. Per the Commit Failure Protocol in `sdd-coordinator`. Do NOT bypass with `--no-verify`.

If the merge succeeded, sanity-test on the merged result:

```bash
<project test command>
```

If tests fail on the merged result: STOP. Don't delete anything; let user resolve.

If tests pass: proceed to cleanup (Step 5+). Delete the feature branch only if config says so (`delete_branch_after_merge: true` is the default):

```bash
git branch -d "$BRANCH"
```

### Option 2 — Push & Create PR

```bash
git push -u origin "$BRANCH"

# Use configured pr_command if present, else default
gh pr create --title "<title>" --body-file <body_file>
```

`<title>` defaults to the spec's title; user can override interactively.

`<body_file>` is a temp file with:

```markdown
## Summary
<2-3 bullets pulled from the spec's Goal section>

## Test plan
- [ ] <bulleted manual-verification steps, derived from the spec's acceptance scenarios>

## Spec
docs/specs/NNN-<short-name>/spec.md

## Plan
docs/specs/NNN-<short-name>/plan.md
```

**Do NOT clean up the worktree for Option 2** — user needs it alive for PR iteration. The state file deletion still happens (work is complete from SDD's perspective; further iteration is normal git work).

### Option 3 — Keep As-Is

Report: "Branch `<name>` preserved at `<path>`. State file kept since work continues."

**Do NOT delete the state file for Option 3** — the user may want SDD to resume context later (e.g., they discover a missed requirement and want to iterate within the SDD pipeline).

Skip Step 5+ — branch stays as-is, state file kept.

### Option 4 — Discard

Require typed confirmation: `discard`.

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git checkout "$BASE_BRANCH"
```

Proceed to Step 5+ cleanup, then force-delete branch:

```bash
git branch -D "$BRANCH"
```

## Step 5: Worktree Cleanup

Only runs for Option 1 or Option 4. Read state file's `preflight.worktree_path`.

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree. Skip.

**If worktree path is under `.worktrees/` AND state file's `preflight.worktree_path` matches:** We created it; we own cleanup.

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git worktree remove "$WORKTREE_PATH"
git worktree prune
```

**Otherwise:** The worktree is harness-managed or user-managed. Don't touch it.

## Step 6: Delete State File

For Options 1, 2, and 4 — work is done from SDD's perspective. Delete the state file:

```bash
rm "docs/specs/NNN-<short-name>/state.json"
```

Commit the deletion (matters for Options 1 and 2 — keeps the spec dir clean in history). The deletion is committed as part of the feature's last commit when possible; otherwise as a standalone "chore: clean up SDD state" commit.

For Option 3 — keep state file.

## Step 7: Report

```
SDD run complete.
- Action: merge-local | pr | keep | discard
- Branch: <name>
- PR: <url> (if applicable)
- Worktree cleaned: yes | no
- State file: deleted | kept
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Cleaning up the worktree for Option 2 | User needs it for PR iteration — keep it |
| Cleaning up worktrees we didn't create | Provenance check: only cleanup `.worktrees/<branch>` paths that match state file's `worktree_path` |
| Deleting state file for Option 3 | Option 3 means "work continues" — keep state |
| Trying to restore a preflight stash | Preflight no longer stashes (it aborts on dirty files). If you see `preflight.stash_ref` in an old state file, ignore it — the field is deprecated. |
| Running `git worktree remove` from inside the worktree | `cd` to main repo root first |
| Deleting feature branch before removing worktree | `git branch -d` fails if a worktree references the branch — remove worktree first |
| Force-push to main as part of "merge" | Never; only `git merge` on the base branch, never `git push --force` to the base |

## Red Flags

- About to `git push --force` anywhere → STOP
- About to `git branch -D` without typed `discard` confirmation → STOP
- Tests failing on the merge result → STOP; let user resolve
- About to remove a worktree path not in our state file → STOP
- About to delete the state file while a worktree is still active and being used by something else → STOP; verify worktree cleanup is genuinely complete first

## Config Schema

```yaml
finishing:
  mode: prompt              # prompt | leave | merge-local | pr | auto
  merge_target: main
  delete_branch_after_merge: true
  test_command: null        # explicit command to run for sanity tests; null = auto-detect
  pr_command: "gh pr create --title '{title}' --body-file {body_file}"
  pr_body_template: |
    ## Summary
    {summary}

    ## Test plan
    {test_plan}

    ## Spec
    {spec_link}

    ## Plan
    {plan_link}
```

If `pr_command` is unset, default to `gh pr create --title "{title}" --body-file {body_file}`.

If `test_command` is unset (default), Step 1's auto-detect runs. Set it explicitly for any project that doesn't match the auto-detect priority list (Makefile, Node, Cargo, Python, Go, Maven, Gradle). Examples:

```yaml
finishing:
  test_command: "make test"        # Makefile-driven monorepo
  # or
  test_command: "nox -s tests"     # Python with nox
  # or
  test_command: "pnpm run test:ci" # specific script
```
