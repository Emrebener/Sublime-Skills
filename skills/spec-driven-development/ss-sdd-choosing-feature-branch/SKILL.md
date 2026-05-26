---
name: ss-sdd-choosing-feature-branch
description: Use after plan approval (Stage 11) and before implementation (Stage 13). Auto-decides where the SDD planning commits land — silent when on `main` (creates and switches to the derived feature branch) or when already on the derived branch (build-on-top of a partial implementation). Falls back to an inline prompt only when the current branch is neither. Then batch-commits the planning artifacts in two thematic, path-scoped commits and persists the chosen branch into state for Stage 17 to merge.
---

# Choosing Feature Branch

## Overview

Stage 12 of the SDD pipeline. By this point the spec, plan, and ADRs have all been written and approved, but **nothing has been committed yet** — they sit uncommitted in the working tree. This skill:

1. Decides where the work will live, using an opinionated rule keyed off the current branch (see Step 2). The common cases (on `main` / already on the derived branch) auto-decide silently; only genuinely ambiguous starts prompt.
2. Runs `git checkout -b` (or `git checkout`) only when a branch change is required.
3. Batch-commits the SDD planning artifacts in two thematic, path-scoped commits.
4. Persists `branch_name` into the state file so Stage 17 (`ss-sdd-finishing`) can merge and delete it.

After this skill, the pipeline returns to normal per-stage commits in Stage 13 (implementation) and beyond. At Stage 17, the branch chosen here will be merged into `main` (no-ff) and deleted.

**Core principle:** One opinionated workflow, not a buffet. Auto-decide whenever the situation is unambiguous; prompt only when it isn't.

**Announce at start:** "I'm using the ss-sdd-choosing-feature-branch skill to settle the feature branch and commit the planning artifacts."

## Inputs (passed by the coordinator)

- `FEATURE_ID` — e.g., `003-user-auth`
- `SHORT_NAME` — kebab-case, e.g., `user-auth`

The skill reads `.sublime-skills/config.yml → branching.branch_pattern`, `state.work_type`, and the current branch (`git branch --show-current`) directly. The coordinator no longer pre-fetches the current branch — the decision rule depends on it, so the skill queries at runtime.

## Contract

### What this skill ALWAYS does (or aborts trying)

1. Derives the suggested branch name from `branch_pattern` (with `feat/` → `fix/` swap when `work_type == "fix"`)
2. Resolves the branch decision per the rule in Step 2 — silently when possible, with a prompt only when ambiguous
3. Runs `git checkout -b <name>` (or `git checkout <name>` on collision) only when a change is required
4. Batch-commits the SDD planning artifacts in two thematic commits, using path-scoped `git add` (never `git add .` / `git add -A`)
5. Updates `.sublime-skills/state.json` on disk (`current_stage: implementing`, append `branch_chosen` to `stages_completed`, set `branch_name`); this state write is never committed
6. Returns the chosen branch name to the coordinator

### What this skill aborts on

| Abort case | Reason code | Trigger |
|---|---|---|
| Branch creation failed | `branch_creation_failed` | `git checkout -b` fails (invalid name, sandbox refused) |
| Checkout failed | `checkout_failed` | `git checkout <existing>` fails (working tree conflict, sandbox refused) |
| User declined | `user_declined` | User picked Abort at an ambiguity prompt |
| Commit failed | `commit_failed` | Either commit fails (hook rejection, signing failure, missing identity). Per the Commit Failure Protocol in `ss-sdd-coordinator`. |

### What this skill never does

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- Never `git add .` or `git add -A` — only explicit paths (the user's pre-existing dirty files must stay untouched)
- Never `git commit --amend`, `--no-verify`, `--force`, or signing bypasses
- Never deletes branches (Stage 17 owns the post-merge delete)
- Never pushes, pulls, or merges (Stage 17 owns the merge to `main`)
- Never modifies user-authored files

## Checklist

1. Derive the suggested branch name from `branching.branch_pattern` and `work_type`
2. Resolve the branch decision (silent when on `main` or already on the derived name; prompt only when ambiguous)
3. Batch-commit the SDD planning artifacts
4. Update `.sublime-skills/state.json` (including `branch_name`) and return to coordinator

## Step 1: Derive Suggested Branch Name

Read `branching.branch_pattern` from config:

```bash
PATTERN=$("${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}/skills/spec-driven-development/framework/get-config-value.sh" branching branch_pattern)
PATTERN="${PATTERN:-feat/{short-name}}"
```

Read `work_type` from `.sublime-skills/state.json` (Stage 2 persisted it). If `work_type == "fix"` and the pattern starts with `feat/`, swap it to `fix/`:

```bash
WORK_TYPE=$(jq -r '.work_type' ".sublime-skills/state.json")
if [ "$WORK_TYPE" = "fix" ] && [ "${PATTERN#feat/}" != "$PATTERN" ]; then
  PATTERN="fix/${PATTERN#feat/}"
fi
```

Substitute `{short-name}`:

```bash
SUGGESTED=$(echo "$PATTERN" | sed "s/{short-name}/$SHORT_NAME/g")
```

Read the current branch:

```bash
CURRENT=$(git branch --show-current)
```

## Step 2: Resolve the Branch Decision

Apply this rule in order:

### Case A — `CURRENT == SUGGESTED` (already on the derived branch)

Stay silently. The user is deliberately building on top of an earlier partial implementation on this branch. No prompt, no checkout. Proceed to Step 3.

### Case B — `CURRENT == "main"` (the happy path)

The user is starting fresh from `main`. Two sub-cases:

**B.1 — `SUGGESTED` does not yet exist locally:**

```bash
git checkout -b "$SUGGESTED"
```

If this fails (sandbox permissions, invalid name): ABORT with `branch_creation_failed`. Show the git error verbatim.

**B.2 — `SUGGESTED` already exists locally** (e.g., a previous run created it, or the user pre-created it):

This is the only ambiguous sub-case under Case B. Ask the user via the harness's interactive question tool:

```
A branch named `<SUGGESTED>` already exists locally. Choose:
  1. Switch to existing `<SUGGESTED>` and commit on top  (default)
  2. Pick a different name
  3. Abort
```

- **Switch:** `git checkout "$SUGGESTED"`. If checkout fails, ABORT with `checkout_failed`.
- **Pick different name:** prompt for a name; validate per the rules in "Branch name validation" below; if it collides too, repeat. After a valid, non-colliding name: `git checkout -b "$NEW_NAME"`. Set `SUGGESTED=$NEW_NAME` for use in Step 4.
- **Abort:** ABORT with `user_declined`.

### Case C — anything else (e.g., on `feat/some-other-feature`, `develop`, etc.)

The current branch is genuinely ambiguous. Ask the user via the harness's interactive question tool:

```
You're on `<CURRENT>`, which is neither `main` nor the derived branch
`<SUGGESTED>`. Choose:

  1. Stay on `<CURRENT>` — commits land here.
     ⚠ At Stage 17 this branch will be merged into `main` and deleted.
  2. Create `<SUGGESTED>` from `<CURRENT>` — branched off here.
     ⚠ At Stage 17 this branch will be merged into `main` and deleted.
  3. Abort — I'll switch to the right branch manually.
```

The warning text on options 1 and 2 is mandatory. It is the only thing standing between the user and accidentally deleting a long-lived integration branch (like `develop`) at Stage 17. Do not paraphrase it away.

- **Stay:** no branch op. The branch for this run is `CURRENT`. Proceed to Step 3 with `SUGGESTED=$CURRENT` (so subsequent code uses the right name).
- **Create from current:** `git checkout -b "$SUGGESTED"`. Failure → ABORT `branch_creation_failed`.
- **Abort:** ABORT with `user_declined`.

### Branch name validation (used by Case B.2 "Pick a different name")

- No spaces, no leading `-`, no `..`, no `~` or `^` or `:` or `?` or `*` or `[` or `\`
- Not empty
- Not equal to `main` or `master` (those are reserved as base branches)

If invalid, explain why and re-prompt.

## Step 3: Batch-commit the SDD Planning Artifacts

Execute two thematic commits, in order. Skip Commit 2 if `state.adr_results` is empty.

The variable `SUGGESTED` from Step 2 holds the branch name the work is landing on (whether silent, newly-created, or user-confirmed-stay). It is the same value that will be persisted as `branch_name` in Step 4.

### Commit 1 — Spec and plan

```bash
git add "docs/specs/<FEATURE_ID>/spec.md" "docs/specs/<FEATURE_ID>/plan.md"
git commit -m "docs(<FEATURE_ID>): spec and plan"
```

### Commit 2 — ADRs (skipped if no ADRs)

Read the ADR paths from `state.adr_results` (an array of objects with a `path` field). If the array is empty, skip this commit.

```bash
git add <each ADR path>...
git commit -m "docs(adr): N decisions for <FEATURE_ID>"
```

**The state file is NOT staged in either commit.** `.sublime-skills/state.json` is permanently gitignored. Do not attempt `git add -f`, `--force`, or any other bypass — see "What this skill never does" above.

### Commit failure handling

If either commit fails:

- **Hook rejection / signing failure / missing identity:** ABORT with `commit_failed`. Show the error verbatim. The user fixes the underlying issue and tells the coordinator to continue — Stage 12 re-runs because `branch_chosen` isn't yet in `stages_completed`.
- **NEVER bypass with `--no-verify`, `--no-gpg-sign`, or amend the previous commit.** Per the Commit Failure Protocol in `ss-sdd-coordinator`.
- **NEVER amend.** If Commit 1 succeeds but Commit 2 fails, the partial commit stays in git. Fix the underlying issue and tell the coordinator to continue; it routes back to Stage 12 because `branch_chosen` isn't yet in `stages_completed`. The user investigates the partial state and resolves it manually.

## Step 4: Update State and Return to Coordinator

After the commits land, update `.sublime-skills/state.json` atomically (write `.tmp`, then `mv`). The write must include `branch_name` — Stage 17 reads it to know which branch to merge into `main`:

```json
{
  "current_stage": "implementing",
  "stages_completed": [..., "branch_chosen"],
  "branch_name": "<SUGGESTED>",
  "updated_at": "<ISO-8601 timestamp>"
}
```

**No commit follows this state update.** `.sublime-skills/state.json` is gitignored; the write is on-disk only.

Return to the coordinator with the chosen branch name and a summary of which commits landed.

## Reporting Back

### On success

```
ss-sdd-choosing-feature-branch complete.
- Branch: feat/user-auth (auto-created from main)
- branch_name persisted to state
- Commits made: 2 (spec+plan, adr)
- Status: ready
```

The "auto-created from main" / "switched to existing" / "stayed (already on derived)" / "stayed (user chose, will be merged + deleted at Stage 17)" detail is worth surfacing so the user has an audit trail of what was decided silently.

### On abort

```
ss-sdd-choosing-feature-branch aborted.
- Status: aborted_at_choosing_branch
- Reason: branch_creation_failed | checkout_failed | user_declined | commit_failed
- Message: <user-facing message>
```

The coordinator surfaces the abort to the user and halts the pipeline. `.sublime-skills/state.json` on disk reflects whatever stage Step 4 reached; continuing the coordinator re-runs Stage 12 (because `branch_chosen` isn't yet in `stages_completed`).

## Common Mistakes

| Mistake | Fix |
|---|---|
| Prompting the user when on `main` and the derived branch doesn't exist | NEVER — that's the silent happy path; just `git checkout -b`. |
| Prompting when already on the derived branch | NEVER — silent stay; that's the build-on-top path. |
| Skipping the merge+delete warning text in the Case C prompt | NEVER — the warning is the only safeguard against deleting `develop` (or similar) at Stage 17. |
| Forgetting to persist `branch_name` to state | Stage 17 reads it; without it, the merge target is unknown. |
| Using `git add .` or `git add -A` | NEVER — only path-scoped adds. The user has pre-existing dirty files that must stay untouched. |
| Bypassing a failing commit with `--no-verify` | NEVER — abort with `commit_failed` and surface the error. The user fixes the hook/signing issue. |
| Amending a previous commit when a later one fails | NEVER — let the partial commits stay; the user investigates. |
| Pushing the new branch automatically | NEVER — push is the user's call. |
| Deleting any branch from here | NEVER — Stage 17 owns the post-merge delete. |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |

## Red Flags

- About to prompt the user when on `main` with no collision → STOP; auto-create silently
- About to prompt when already on the derived branch → STOP; silent stay
- About to issue the Case C prompt without the "merged + deleted" warning → STOP; the warning is mandatory
- About to skip writing `branch_name` to state → STOP; Stage 17 needs it
- About to `git add .` or `git add -A` → STOP; use explicit paths
- About to `git push` → STOP; not this skill's job
- About to `git merge` or `git branch -d` → STOP; Stage 17 owns those
- About to amend a previous commit → STOP; let partial state stay; surface to user
- About to create a branch named `main` or `master` → STOP; reject and re-prompt
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP
