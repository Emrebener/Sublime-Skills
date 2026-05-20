---
name: preflight-checks
description: Use at the very start of a spec-driven-development pipeline run, before any spec drafting, planning, or implementation work begins. Ensures git state is clean and the working branch is dedicated to the feature.
---

# Preflight Checks

## Overview

Verify the repo is in a fit state to start an SDD pipeline run: clean working tree, on an appropriate branch. **This skill is abort-only for problem states** — it never cleans up dirty files, never auto-switches branches, never modifies user data. It does take exactly two state-modifying actions when conditions allow: creating a new feature branch from `main`/`master`, and optionally creating a worktree.

**Core principle:** Don't try to clean up the user's mess. Ask them to do it. Failing fast on a dirty state is safer than guessing at user intent.

**Announce at start:** "I'm using the preflight-checks skill to verify the repo state."

## Contract

### What this skill ALWAYS ensures (or aborts trying)

1. The working tree is clean (`git status --porcelain` is empty)
2. The current branch is either the default branch (about to fork) or a recognized SDD feature branch (about to resume)
3. After this skill returns, the coordinator can safely begin spec/plan work

### What this skill aborts on (fail-fast cases)

| Abort case | Reason code | Trigger |
|---|---|---|
| Dirty working tree | `dirty_working_tree` | Any output from `git status --porcelain` |
| Protected branch | `protected_branch` | On `develop`, `release/*`, `hotfix/*` |
| Ambiguous branch | `ambiguous_branch` | On a non-default, non-protected branch with no matching SDD state file |
| Worktree creation failure | `worktree_creation_failed` | `git worktree add` fails (only when `use_worktree: true`) |
| User declined | `user_declined` | User said "no" to branch creation or resume confirmation |

### What this skill does itself (state-modifying actions)

1. **Creates a feature branch** from `main`/`master` when starting fresh, AFTER user confirms the name. Uses `git checkout -b <name>`.
2. **Creates a worktree** only if `.sdd/config.yml → preflight.use_worktree: true`. Uses `git worktree add`.
3. **Adds `.worktrees/` to `.gitignore` and commits** that change, only if worktree was requested and `.worktrees/` wasn't already gitignored.

### What this skill never does

- Never commits, stashes, discards, or restores working tree changes (no `git stash`, `git restore`, `git clean`, `git reset`)
- Never auto-switches branches (no `git checkout <other-branch>` to move away from an unsuitable branch — only `git checkout -b <new>` from a suitable base)
- Never writes to a state file (the state file doesn't exist yet — it's initialized in Stage 2 by `writing-specs`)
- Never modifies user-authored files (only `.gitignore` for the worktree case, and only if worktree config is on)
- Never dispatches subagents (this skill runs inline in the coordinator)
- Never guesses at the user's intent when state is ambiguous — aborts and lets the user clarify

## How This Skill Relates to inspecting-state

The coordinator runs `inspecting-state` BEFORE invoking this skill, then passes its report into this skill via the dispatch.

- If `inspecting-state` reported an active state file matching the current branch → coordinator told you "this is a resume of feature X on branch Y"
- If `inspecting-state` reported no active state files → coordinator told you "this is a fresh start"
- If on a non-default branch with no matching state file → coordinator already asked the user (per the resume protocol) and routed accordingly; if user picked "start fresh" or "resume," the coordinator passes that decision in

This skill enforces the branch contract regardless of which case the coordinator routed; it doesn't second-guess the resume decision.

## Checklist

The coordinator MUST track each of these as a todo item and complete them in order:

1. Run `git status --porcelain` and `git branch --show-current`
2. If dirty (any output from `git status --porcelain`): **ABORT** per the Dirty Files Protocol below
3. Apply the Branch Protocol below — abort or proceed based on which branch we're on
4. **If `.sdd/config.yml → preflight.use_worktree: true` AND we're on the base branch (fresh start case):** apply the Worktree Pre-Branch Setup below (commit `.worktrees/` to `.gitignore` on the base branch FIRST). This must happen BEFORE creating the feature branch — otherwise the gitignore commit lands on the feature branch and clutters every PR.
5. Create a new feature branch if starting fresh, or reuse the existing one if resuming
6. If `use_worktree: true`, apply the Worktree Protocol below to create the worktree
7. Report ready — return preflight outcomes (branch name, original branch, worktree path) to the coordinator. The coordinator holds these in-memory and persists them when `writing-specs` initializes the state file in Stage 2.

## Dirty Files Protocol

If `git status --porcelain` returns any output, ABORT immediately. Do not offer to commit, stash, or discard. Show the user the dirty files and tell them to handle the working tree manually before re-invoking the coordinator.

```
ABORTING preflight: the working tree has uncommitted changes.

[list of files from git status --porcelain, max 30; if more, summarize the rest]

SDD requires a clean working tree to start. Please:

1. Commit or stash your changes manually, OR
2. Discard them (`git restore .` etc.) if they're disposable

Then re-invoke the SDD coordinator. The pipeline will not start until the working tree is clean.
```

Return status `aborted_at_preflight` with reason `dirty_working_tree` to the coordinator. The coordinator surfaces this and exits.

## Branch Protocol

Detect the current branch. Behavior depends on which branch:

### On `main` / `master` (default branch) + clean tree

- Starting fresh is appropriate.
- Derive a feature branch name. Default pattern: `feat/<short-name>`. The `<short-name>` is the kebab-case working name from the user (or generated). If not yet known, ask the user for a working name now — it can be renamed later if the spec's `short_name` differs.
- Confirm with user: `Starting from \`<current branch>\` (clean). Create and switch to feature branch \`<name>\`? (yes/no)`
- On yes: `git checkout -b <name>`
- On no: ask for an alternative branch name; create that instead. If they decline entirely → ABORT with `user_declined`.

### On a feature-like branch (not `main`/`master`/`develop`/`release/*`/`hotfix/*`)

Use the `inspecting-state` report the coordinator passed you.

**If a matching state file exists for this branch** → this is a resume.
- Confirm with user: `Branch \`<name>\` has an active SDD state at stage \`<current_stage>\`. Resume? (yes/no)`
- On yes: return the branch as the resume target (do not run `git checkout`; you're already there)
- On no: ABORT with `user_declined` (do not start a new SDD run on a branch that has an existing one)

**If no matching state file exists for this branch** → ABORT with `ambiguous_branch`.

```
ABORTING preflight: on branch `<name>` but no matching SDD state file found.

This branch is not recognizable as a fresh start (you're not on main/master) or as a resume target (no state file).

Please either:
1. Switch to main/master and re-invoke the SDD coordinator to start a new feature, OR
2. If you have an in-progress SDD run, restore its state file under docs/specs/NNN-name/state.json and re-invoke.
```

### On `develop`, `release/*`, or `hotfix/*` (protected branches)

ABORT with `protected_branch`.

```
ABORTING preflight: on protected branch `<name>`.

SDD shouldn't be initiated from develop/release/hotfix branches. Please switch to main/master first.
```

### On any other branch shape (e.g., `wip/...`, `experiment/...`, random old branch)

Same as the "feature-like branch + no matching state file" case above → ABORT with `ambiguous_branch`.

### Branch naming defaults

Overridable via `.sdd/config.yml → preflight.branch_pattern`:
- `feat/<short-name>` for new features (default)
- `fix/<short-name>` if the user describes the work as a bug fix during `discovering-requirements` (renamed at that point if needed)

## Worktree Protocol

Skip this entire section if `.sdd/config.yml → preflight.use_worktree` is unset or false (the default). Worktrees are opt-in.

Read this value with the helper:

```bash
USE_WORKTREE=$(./spec-driven-development/scripts/get-config-value.sh preflight use_worktree)
```

(Returns `"true"`, `"false"`, or empty. Treat empty / `"false"` as off; only `"true"` enables worktrees.)

### Worktree Pre-Branch Setup (on base branch, BEFORE creating feature branch)

If `.worktrees/` isn't already gitignored on the base branch, add it there. This keeps the gitignore commit on `main`/`master` (where it belongs as project infrastructure) instead of polluting the feature branch:

```bash
mkdir -p .worktrees
if ! grep -q '^\.worktrees/$' .gitignore 2>/dev/null; then
  echo '.worktrees/' >> .gitignore
  git add .gitignore
  git commit -m "chore: gitignore .worktrees/ for SDD worktree support"
fi
```

If the gitignore commit fails (pre-commit hook, signing issue, missing identity): ABORT with `worktree_creation_failed`. Show the user the commit error verbatim. Do NOT bypass with `--no-verify`. Per the Commit Failure Protocol in `sdd-coordinator`.

Once `.worktrees/` is gitignored on the base branch, proceed with feature branch creation, THEN create the worktree (Worktree Protocol below).

### Worktree Protocol (after branch creation)

Compute the worktree path. **Sanitize branch slashes to dashes** so nested directories don't get created — `feat/user-auth` becomes `.worktrees/feat-user-auth/`, not `.worktrees/feat/user-auth/`:

```bash
WORKTREE_NAME=$(echo "<branch-name>" | tr '/' '-')   # feat/user-auth → feat-user-auth
WORKTREE_PATH=".worktrees/$WORKTREE_NAME"
git worktree add "$WORKTREE_PATH" "<branch-name>"
```

If `git worktree add` fails (sandbox permissions, etc.): ABORT with `worktree_creation_failed`. Tell the user the sandbox blocked it and they should either disable the worktree config or run from outside the sandbox.

Return the worktree path in your status report — the coordinator persists it when the state file is initialized in Stage 2.

## Reporting Back

### On success

Return to the coordinator:

```
Preflight complete.
- Branch: feat/user-auth (created from main) | feat/user-auth (resumed)
- Original branch: main
- Worktree: none | .worktrees/feat-user-auth
- Working tree: clean
- Status: ready
```

### On abort

Return to the coordinator with one of these reason codes:

```
Preflight aborted.
- Status: aborted_at_preflight
- Reason: dirty_working_tree | ambiguous_branch | protected_branch | worktree_creation_failed | user_declined
- Message: <the message that was shown to the user>
```

The coordinator surfaces the abort to the user and exits the pipeline.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Trying to commit/stash/discard dirty files | Don't — abort. The user handles their own mess. |
| Trying to "auto-switch" off an inappropriate branch | Don't — abort. The user picks the right starting branch. |
| Trying to write a state file from this skill | The state file doesn't exist yet — only `writing-specs` initializes it. Return outcomes to the coordinator. |
| Creating a branch without user confirmation | Confirm names; users have naming conventions you can't infer |
| Proceeding past a protected/ambiguous branch case | Abort; don't guess at user intent |
| Forcing worktree use | Worktrees are opt-in via config, not default |
| Running `git checkout main` to "fix" being on the wrong branch | NEVER — that loses work and changes user state silently |
| Second-guessing the `inspecting-state` resume decision | Trust the coordinator's routing; enforce branch contract only |

## Red Flags

- About to run `git commit`, `git stash`, `git clean`, or `git restore` to "clean up" dirty files → STOP; abort instead
- About to `git checkout <existing branch>` to "fix" an inappropriate starting branch → STOP; abort instead
- About to try `Read`/`Write` on a state.json file → STOP; state file is initialized in Stage 2 (writing-specs), not here
- About to proceed past an ambiguous-branch case "because the user probably meant ..." → STOP; abort and let the user clarify
- About to dispatch a subagent for branch-detection or any other work → STOP; preflight runs entirely inline
