---
name: ss-sdd-finishing
description: Use during the finishing stage of an SDD pipeline run (Stage 17), after implementation (and any optional testing, handoff, and memory-file stages) are complete. Validates the state file, prints a summary report, then closes the loop by merging the feature branch into `main` with `--no-ff` and safe-deleting it on success. Deletes `.sublime-skills/state.json` via plain `rm` last (the file is gitignored throughout). Local-only — no push.
---

# Finishing SDD

## Overview

Close out an SDD run by completing the source-control loop:

1. Read and validate the state file — confirm implementation actually completed.
2. Print a summary report of what the pipeline produced.
3. Merge the feature branch into `main` with `git merge --no-ff` and safe-delete the branch on success.
4. Delete `.sublime-skills/state.json` via plain `rm` (gitignored throughout the pipeline).

No push, no PR, no test re-run. Push is the user's call; tests already ran (or were deliberately skipped) at Stage 14.

**Core principle:** SDD closes its own loop. A feature run ends with the work landed on `main` and the feature branch cleaned up — that's the one workflow this pipeline supports.

**Announce at start:** "I'm using the ss-sdd-finishing skill to merge the feature branch into main and wrap up this SDD run."

## Hard Gates

- Do NOT proceed if `state.stages_completed` doesn't contain `implementation_complete`
- Do NOT proceed if the state file is malformed or unreadable
- Do NOT `rm` the state file until the merge succeeds and the branch is safely deleted. If the merge halts, state stays so Stage 17 can be re-run after the user resolves the issue.
- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- NEVER use `git branch -D` (force-delete). Always `git branch -d` (safe-delete) — if it refuses, the branch isn't fully merged and we need to investigate, not destroy.
- NEVER `git push`, `gh pr create`, or any remote operation. Local-only by design.
- NEVER use `--no-verify`, `--no-gpg-sign`, or `--force` on the merge commit. If hooks reject, halt and surface.

## Checklist

1. Validate state file
2. Print summary report
3. Merge the feature branch into `main` (no-ff) and safe-delete it on success
4. Delete state.json (plain `rm`, no commit)

## Step 1: Validate State

Read `.sublime-skills/state.json`. Confirm:

- The file parses as JSON.
- `stages_completed` is an array containing `implementation_complete`.
- `branch_name` is a non-empty string (written by Stage 12; without it, Step 3 has no target).

If any check fails: surface the issue and halt. Common reasons: malformed JSON (rare), or the user invoked finishing prematurely (before implementation finished). A state file missing `branch_name` is also a halt — Stage 12 should have written it, and proceeding without a merge target would either skip the merge silently or guess from `git branch --show-current` and surprise the user.

Additionally, check `test_status`:

- If `test_status` is `passed` or `passed_after_fixes`: fine, proceed.
- If `test_status` is `skipped_user_choice` or `skipped_mcp_unavailable`: fine, proceed (the user knew testing was skipped).
- If `test_status` is `failed_escalated` OR `null` (when `testing` isn't in `stages_skipped`): prompt the user via the harness's interactive question tool: "Tests aren't in a passing state (`<test_status>`). Finish anyway?" Only proceed on explicit yes.

**No test re-run.** Stage 14 (feature testing) was the test gate; if it ran and passed, we trust the result. If it was skipped, the user already made that call.

## Step 2: Print Summary Report

Print a structured block to the user. Pull values from `state.json`:

```
SDD run complete: <feature_id>

  Short name:        <short_name>
  Started:           <started_at>
  Updated:           <updated_at>
  Feature branch:    <branch_name>     ← will be merged to main and deleted in Step 3

  Artifacts:
    Spec:            <spec_path>
    Plan:            <plan_path or "(none)">
    Handoff:         <handoff_path or "(skipped)">
    Memory file:     <memory_file_path if memory_file_updated else "(no update)">

  ADRs created:      <count from adr_results>
    <list of ADR-NNNN — title for each>

  Tasks:             <N completed> / <N total> (from `tasks` map)
  Test status:       <test_status>
  Memory file updated: <memory_file_updated>

  Stages completed:  <count of stages_completed>
  Stages skipped:    <list from stages_skipped>
```

This is informational — the user reads it and now knows what the pipeline did and what's about to happen at the merge step.

## Step 3: Merge to `main` and Delete the Feature Branch

```bash
BRANCH=$(jq -r '.branch_name' .sublime-skills/state.json)
```

`BRANCH` is never `"main"` — Stage 12's rules don't produce that value (on `main` we auto-create the derived branch; the Case C prompt only fires off non-main branches). If it somehow is, halt and surface — that's a bug upstream, not a case to silently work around.

### Merge

```bash
git checkout main
```

If `git checkout main` fails (e.g., working-tree conflicts with the user's dirty files, or `main` doesn't exist locally): halt, surface the error verbatim, leave the state file in place. The user resolves manually and tells the coordinator to continue.

```bash
git merge --no-ff "$BRANCH" -m "Merge branch '$BRANCH'"
```

`--no-ff` is mandatory — every SDD feature lands as a merge commit on `main`, so the per-task history is visibly grouped and easy to find later. The explicit `-m` avoids dropping into an interactive editor in non-interactive environments.

If the merge exits non-zero (conflicts, hook rejection, signing failure):

- **Halt.** Surface git's stdout/stderr verbatim.
- **Do NOT delete the branch.** Do NOT `git merge --abort` automatically — that throws away the user's diagnostic context. Leave the working tree as-is.
- **Do NOT `rm` the state file.** State stays so Stage 17 can be re-run after the user resolves the issue.
- Tell the user: resolve the conflict (or hook failure) and complete the merge commit yourself, then ask the coordinator to continue. Or `git merge --abort` and investigate, then continue.

### Idempotent re-run after a manual fix

Re-running Stage 17 after a manually-completed merge:

- `git merge --no-ff <already-merged-branch>` returns exit 0 with "Already up to date" — no second merge commit, no error.
- `git branch -d <fully-merged-branch>` succeeds — safe.
- Step 4 deletes state.

This is the intended recovery path. No special-case code is needed.

### Branch delete (only on merge success)

```bash
git branch -d "$BRANCH"
```

`-d` (lowercase) is the safe form — git refuses if the branch isn't reachable from HEAD. That's our second safety net: if anything weird happened during the merge that left the branch un-reachable, we'd rather halt than silently lose commits.

If `git branch -d` fails: halt, surface the error, leave the state file. Common cause: the branch was already deleted (rare race) — in which case the next coordinator invocation will see `git branch -d` fail with "not found" and the user can `rm` the state file manually.

## Step 4: Delete State File

State is gitignored and untracked — use plain `rm`, NOT `git rm`:

```bash
rm .sublime-skills/state.json
```

No commit follows. The SDD run is complete; the spec / plan / ADRs / per-task commits / memory file commit are all on `main` now via the merge commit.

**If `git rm` is tempting: don't.** It would fail with "did not match any files" because the file is not tracked. Do NOT fall back to `git rm -f` or `git rm --cached` — there is nothing to untrack.

### If the state file is already deleted

If `.sublime-skills/state.json` doesn't exist when this step runs (rare — e.g., the user removed it manually between Step 3 success and Step 4):

```bash
[ -f .sublime-skills/state.json ] && rm .sublime-skills/state.json || true
```

Report "state file already removed; nothing to do."

After deletion: SDD run is done. You're on `main`, the merge commit is in history, the feature branch is gone. Push when ready — that's the user's call.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `rm`ing the state file before the merge succeeds | NEVER — state stays so Stage 17 can be re-run after a merge failure. |
| Re-running the test suite | NEVER — Stage 14 (feature testing) was the test gate. |
| Asking the user whether to merge / delete / leave | NEVER — the workflow is opinionated; the only prompt is the "tests aren't passing, finish anyway?" gate at Step 1. |
| Using `git branch -D` (force-delete) | NEVER. `-d` (safe) only. If it refuses, halt; don't destroy. |
| Auto-running `git merge --abort` on conflict | NEVER. Surface the conflict, leave the tree, let the user inspect. |
| Pushing to remote | NEVER — local-only by design. |
| Asking the user whether to delete the state file | NEVER — state.json is tool metadata; the user doesn't curate it. Just `rm` it after Step 3 succeeds. |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |
| Using `git rm` instead of plain `rm` for the state deletion | NEVER. The file is untracked; `git rm` would fail. Use plain `rm`. |

## Red Flags

- About to `rm` the state file before confirming the merge succeeded → STOP; state survives merge failures so Stage 17 can be re-run
- About to type `git branch -D` → STOP; use `-d` (safe-delete)
- About to `git merge --abort` automatically → STOP; surface conflict and leave the tree
- About to `git push` or `gh pr create` → STOP; local-only
- About to use `--no-verify` or `--no-gpg-sign` on the merge commit → STOP; halt and surface instead
- About to re-run the test suite → STOP; Stage 14 was the gate
- About to skip the `implementation_complete` check → STOP; the gate is non-negotiable
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP
- About to `git rm` state.json → STOP; it's untracked, use plain `rm`
