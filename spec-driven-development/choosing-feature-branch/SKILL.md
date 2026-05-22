---
name: choosing-feature-branch
description: Use after plan approval (Stage 11) and before implementation (Stage 13). Asks the user where the feature branch should live, optionally creates a feature branch from current HEAD, then batch-commits all SDD planning artifacts (spec, plan, ADRs, state.json) on the chosen branch in three path-scoped thematic commits.
---

# Choosing Feature Branch

## Overview

Stage 12 of the SDD pipeline. By this point the spec, plan, and ADRs have all been written and approved, but **nothing has been committed yet** — they sit uncommitted in the working tree. This skill:

1. Decides where the work will live (a freshly-created feature branch, or the current branch — the user picks).
2. Optionally runs `git checkout -b` to create and switch to the feature branch (the uncommitted artifacts travel with the working tree).
3. Batch-commits the SDD planning artifacts on the resulting branch in three thematic, path-scoped commits.

After this skill, the pipeline resumes normal per-stage commits in Stage 13 (implementation) and beyond.

**Core principle:** Branch policy is the user's call, not SDD's. We offer a recommended default and an escape hatch. We never auto-pick.

**Announce at start:** "I'm using the choosing-feature-branch skill to decide where the feature branch lives and commit the planning artifacts."

## Inputs (passed by the coordinator)

- `FEATURE_ID` — e.g., `003-user-auth`
- `SHORT_NAME` — kebab-case, e.g., `user-auth`
- `CURRENT_BRANCH` — value of `git branch --show-current` at the time this skill is invoked

The skill reads `.sublime-skills/config.yml → branching.branch_pattern` and `state.work_type` directly (no need for the coordinator to pre-fetch them).

## Contract

### What this skill ALWAYS does (or aborts trying)

1. Asks the user explicitly which branch the SDD planning commits should land on
2. If the user picks "create new branch," runs `git checkout -b <name>` from current HEAD
3. Batch-commits the SDD planning artifacts in three thematic commits, using path-scoped `git add` (never `git add .` / `git add -A`)
4. Updates `state.json` (`current_stage: implementing`, append `branch_chosen` to `stages_completed`)
5. Returns the resulting branch name to the coordinator

### What this skill aborts on

| Abort case | Reason code | Trigger |
|---|---|---|
| Branch creation failed | `branch_creation_failed` | `git checkout -b` fails (branch already exists, invalid name, sandbox refused) |
| User declined | `user_declined` | User said abort at any prompt |
| Commit failed | `commit_failed` | Any of the three commits fails (hook rejection, signing failure, missing identity). Per the Commit Failure Protocol in `sdd-coordinator`. |

### What this skill never does

- Never `git add .` or `git add -A` — only explicit paths (the user's pre-existing dirty files must stay untouched)
- Never `git commit --amend`, `--no-verify`, `--force`, or signing bypasses
- Never deletes branches
- Never switches branches except via `git checkout -b <new>` from current HEAD
- Never pushes, pulls, or merges
- Never modifies user-authored files

## Checklist

1. Derive the suggested branch name from `branching.branch_pattern`
2. Present the 3-way prompt
3. Handle the user's choice (collision check + checkout if needed)
4. Batch-commit the SDD planning artifacts
5. Update `state.json` and return to coordinator

## Step 1: Derive Suggested Branch Name

Read `branching.branch_pattern` from config:

```bash
PATTERN=$(./spec-driven-development/scripts/get-config-value.sh branching branch_pattern)
PATTERN="${PATTERN:-feat/{short-name}}"
```

Read `work_type` from `state.json` (this skill runs at Stage 12 by which point Stage 2 has persisted the field). If `work_type == "fix"` and the pattern starts with `feat/`, swap it to `fix/`:

```bash
WORK_TYPE=$(jq -r '.work_type' "docs/specs/$FEATURE_ID/state.json")
if [ "$WORK_TYPE" = "fix" ] && [ "${PATTERN#feat/}" != "$PATTERN" ]; then
  PATTERN="fix/${PATTERN#feat/}"
fi
```

Substitute `{short-name}`:

```bash
SUGGESTED=$(echo "$PATTERN" | sed "s/{short-name}/$SHORT_NAME/g")
```

## Step 2: Three-Way Prompt

Ask the user via the harness's interactive question tool. The prompt:

```
About to start implementation for `<FEATURE_ID>`. The spec, plan, and ADRs are
ready and waiting to be committed. They'll land wherever you tell me.

You're currently on `<CURRENT_BRANCH>`. Choose:

  1. Create and switch to `<SUGGESTED>`  (recommended — keeps SDD commits
     isolated on a feature branch)
  2. Use a different branch name
  3. Stay on `<CURRENT_BRANCH>` — commits will land here
```

This MUST be a structured question, not a plain-text prompt. The three options should be presented as discrete choices.

## Step 3: Handle the Choice

### Option 1 — Create suggested branch

Check for collision first:

```bash
if git rev-parse --verify --quiet "$SUGGESTED" > /dev/null; then
  # Branch already exists
  ...
fi
```

**If the branch doesn't exist:**

```bash
git checkout -b "$SUGGESTED"
```

If this fails (sandbox permissions, invalid name): ABORT with `branch_creation_failed`. Show the git error verbatim.

**If the branch exists:** ask the user:

```
The branch `<SUGGESTED>` already exists. Choose:
  1. Use the existing branch (switch to it; commits will land on top)
  2. Pick a different name
  3. Abort
```

- Use existing: `git checkout "$SUGGESTED"` (note: NOT `-b`). The uncommitted artifacts travel with the working tree.
- Pick a different name: loop back to Option 2 below.
- Abort: ABORT with `user_declined`.

### Option 2 — Different branch name

Prompt the user for a name. Validate it:
- No spaces, no leading `-`, no `..`, no `~` or `^` or `:` or `?` or `*` or `[` or `\`
- Not empty
- Not equal to `main` or `master` (those are reserved as base branches)

If invalid, explain and re-ask. After a valid name, repeat the collision check from Option 1.

### Option 3 — Stay on current branch

No branch op. Proceed to Step 4.

## Step 4: Batch Commit

Execute three thematic commits, in order. Skip any commit whose paths don't exist (e.g., no ADRs were created).

**Path-scoping is mandatory.** Never `git add .` or `git add -A`. The user's pre-existing dirty files (which `preflight-checks` allowed through) must remain untouched.

### Commit 1 — Spec + initial state

```bash
git add "docs/specs/<FEATURE_ID>/spec.md" "docs/specs/<FEATURE_ID>/state.json"
git commit -m "docs(<FEATURE_ID>): spec"
```

### Commit 2 — ADRs (skipped if none created)

Read the ADR paths from `state.adr_results` (an array of objects with a `path` field). If the array is empty, skip this commit.

```bash
# Only the ADRs created during this run, not pre-existing ADRs
git add <paths from state.adr_results>
git commit -m "docs(adr): N decisions for <FEATURE_ID>"
```

Where `N` is the count of ADRs.

### Commit 3 — Plan + state.json update

Before this commit, update `state.json` (`current_stage` stays `plan_approval` for now; mark this commit's existence by NOT including it in `stages_completed` yet — that happens after Step 5).

```bash
git add "docs/specs/<FEATURE_ID>/plan.md" "docs/specs/<FEATURE_ID>/state.json"
git commit -m "docs(<FEATURE_ID>): plan"
```

### Commit failure handling

If any commit fails:
- **Hook rejection / signing failure / missing identity:** ABORT with `commit_failed`. Show the error verbatim. The user fixes the underlying issue and re-invokes the coordinator (which can resume from Stage 12 since the state file is on disk; `stages_completed` does NOT yet include `branch_chosen`).
- **NEVER bypass with `--no-verify`, `--no-gpg-sign`, or amend the previous commit.** Per the Commit Failure Protocol in `sdd-coordinator`.
- **NEVER amend.** If commits 1 and 2 succeed but commit 3 fails, the partial commits stay in git. Fix the underlying issue (hook, identity, signing) and re-invoke the coordinator; it routes back to Stage 12 because `branch_chosen` isn't yet in `stages_completed`. The user investigates the partial state and resolves it manually.

## Step 5: Update State and Return

After all required commits land:

1. Update `state.json` atomically (write `.tmp`, then `mv`):
   - `current_stage: "implementing"`
   - Append `"branch_chosen"` to `stages_completed`
   - Update `updated_at` to current ISO-8601 UTC

2. Commit this final state.json update **separately** as part of the implementation stage's first commit — do NOT make a fourth commit here. (Commit 3 above already includes a state.json snapshot from before this update; the very next commit in Stage 13 will include the updated state.)

   Actually simpler: include this state update in Commit 3 (above) by writing to `state.json` BEFORE running Commit 3's `git add`. That way Commit 3 captures the "branch chosen" state. Adjust the message slightly if desired, but the simple form is fine.

3. Return to the coordinator:

   ```
   choosing-feature-branch complete.
   - Branch: <BRANCH> (created | reused | unchanged)
   - Commits made: <count> (spec | adr | plan; some may be skipped)
   - Status: ready
   ```

## Reporting Back

### On success

```
choosing-feature-branch complete.
- Branch: feat/user-auth (created from main)
- Commits made: 3 (spec, adr, plan)
- Status: ready
```

### On abort

```
choosing-feature-branch aborted.
- Status: aborted_at_choosing_branch
- Reason: branch_creation_failed | user_declined | commit_failed
- Message: <user-facing message>
```

The coordinator surfaces the abort to the user and exits the pipeline. State.json on disk reflects whatever stage Step 5 reached; resuming the coordinator picks up at Stage 12 again.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using `git add .` or `git add -A` | NEVER — only path-scoped adds. The user has pre-existing dirty files that must stay untouched. |
| Bypassing a failing commit with `--no-verify` | NEVER — abort with `commit_failed` and surface the error. The user fixes the hook/signing issue. |
| Amending a previous commit when a later one fails | NEVER — let the partial commits stay; the user investigates. |
| Pushing the new branch automatically | NEVER — V1 doesn't manage remotes. The user pushes when they want. |
| Auto-picking the suggested branch name without asking | NEVER — Step 2's 3-way prompt is mandatory. |
| Forgetting to check for branch collision | Check `git rev-parse --verify --quiet "$NAME"` before `git checkout -b`. |
| Skipping the ADR commit when there are no ADRs | Correct behavior — skip Commit 2 entirely if `state.adr_results` is empty. |

## Red Flags

- About to `git add .` or `git add -A` → STOP; use explicit paths
- About to `git push` → STOP; not this skill's job
- About to delete a branch → STOP; not this skill's job
- About to amend a previous commit → STOP; let partial state stay; surface to user
- About to create a branch named `main` or `master` → STOP; reject and re-ask
- About to skip the user prompt and auto-pick → STOP; the 3-way question is mandatory
