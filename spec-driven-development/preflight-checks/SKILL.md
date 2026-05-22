---
name: preflight-checks
description: Use at the very start of a spec-driven-development pipeline run, before any spec drafting, planning, or implementation work begins. Validates .sublime-skills/config.yml, ensures git state is clean, and confirms the working branch is dedicated to the feature. This skill is the single home for every pre-pipeline halt check.
---

# Preflight Checks

## Overview

Verify the repo is in a fit state to start an SDD pipeline run: the `.sublime-skills/config.yml` is present and valid, the working tree is clean, and we're on an appropriate branch (default branch about to fork, or a recognized SDD feature branch about to resume). **This skill is abort-only for problem states** — it never cleans up dirty files, never auto-switches branches, never modifies user data. It does take exactly one state-modifying action when conditions allow: creating a new feature branch from `main`/`master`.

**Core principle:** Don't try to clean up the user's mess. Ask them to do it. Failing fast on a dirty state is safer than guessing at user intent.

This skill is also **the single home for every pre-pipeline halt check.** The coordinator does NOT run config validation or git-state checks on its own — it runs `inspecting-state` (for the report), then loads this skill, then routes based on the report once this skill returns ready.

**Announce at start:** "I'm using the preflight-checks skill to verify the repo state."

## Contract

### What this skill ALWAYS ensures (or aborts trying)

1. `.sublime-skills/config.yml` is present and passes `validate-config.sh`
2. The working tree is clean (`git status --porcelain` is empty)
3. The current branch is either the default branch (about to fork) or a recognized SDD feature branch (about to resume); not `HEAD` detached with any active state file
4. After this skill returns, the coordinator can safely begin spec/plan work and trust every path in `.sublime-skills/config.yml`

### What this skill aborts on (fail-fast cases)

| Abort case | Reason code | Trigger |
|---|---|---|
| Config missing | `config_missing` | `.sublime-skills/config.yml` doesn't exist (`validate-config.sh` exit 2) |
| Config invalid | `config_invalid` | `validate-config.sh` exit 1 (malformed YAML, orphan path, unknown key, etc.) |
| Dirty working tree | `dirty_working_tree` | Any output from `git status --porcelain` |
| Detached HEAD with active state | `detached_head_with_state` | `git branch --show-current` is empty AND `inspecting-state` reported ≥1 active state file |
| Protected branch | `protected_branch` | On `develop`, `release/*`, `hotfix/*` |
| Ambiguous branch | `ambiguous_branch` | On a non-default, non-protected branch with no matching SDD state file |
| User declined | `user_declined` | User said "no" to branch creation or resume confirmation |

### What this skill does itself (state-modifying actions)

1. **Creates a feature branch** from `main`/`master` when starting fresh, AFTER user confirms the name. Uses `git checkout -b <name>`.

### What this skill never does

- Never commits, stashes, discards, or restores working tree changes (no `git stash`, `git restore`, `git clean`, `git reset`)
- Never auto-switches branches (no `git checkout <other-branch>` to move away from an unsuitable branch — only `git checkout -b <new>` from a suitable base)
- Never writes to a state file (the state file doesn't exist yet — it's initialized in Stage 2 by `writing-specs`)
- Never modifies user-authored files
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

1. Run `validate-config.sh`. If exit code is non-zero: **ABORT** per the Config Validation Protocol below. Config must be valid before any other check — every path the rest of preflight (and the pipeline) reads comes from it.
2. Run `git status --porcelain` and `git branch --show-current`
3. If `git branch --show-current` is empty (detached HEAD) AND the inspecting-state report lists ≥1 active state file: **ABORT** per the Detached HEAD Protocol below
4. If dirty (any output from `git status --porcelain`): **ABORT** per the Dirty Files Protocol below
5. Apply the Branch Protocol below — abort or proceed based on which branch we're on
6. Create a new feature branch if starting fresh, or reuse the existing one if resuming
7. Report ready — return preflight outcomes (branch name, original branch) to the coordinator. The coordinator holds these in-memory and persists them when `writing-specs` initializes the state file in Stage 2.

## Config Validation Protocol

Run the validator first, before any git inspection. The pipeline reads every path (spec_dir, adr_dir, handoff_dir, context files, memory file) from `.sublime-skills/config.yml`; running without a valid config is unsupported, not a degraded mode.

```bash
./spec-driven-development/scripts/validate-config.sh
```

| Exit code | Meaning | Action |
|---|---|---|
| `0` | PASS | Continue to Step 2 (git status / branch check) |
| `1` | FAIL — config has issues | **ABORT** with `config_invalid`. Show the validator's stderr verbatim. |
| `2` | Config file missing | **ABORT** with `config_missing`. The project hasn't been bootstrapped for SDD. |

**Halt message template (any non-zero exit):**

```
ABORTING preflight: `.sublime-skills/config.yml` is missing or invalid.

<validator output verbatim>

Run the `bootstrapping-project` skill (in the `project-bootstrap/` family)
to scaffold or fix the config, then re-invoke the SDD coordinator.
```

Do not attempt to proceed with defaults; do not try to repair config inline. Returning the user to bootstrap is the correct outcome.

Return status `aborted_at_preflight` with the matching reason code (`config_invalid` or `config_missing`). The coordinator surfaces this and exits.

## Detached HEAD Protocol

If `git branch --show-current` returns an empty string, the working tree is in detached-HEAD state.

- **Detached HEAD with NO active state files**: this is too ambiguous to route, but it's not catastrophic — the coordinator's higher-level routing decides whether to bail. Don't abort here unilaterally; just note "detached HEAD, no active states" in your report. The coordinator's routing logic decides.
- **Detached HEAD with ≥1 active state file** (from the `inspecting-state` report the coordinator passed in): **ABORT** with `detached_head_with_state`. The user is in too unclear a state to safely resume — there's no branch to match against `state.branch`, no clean fresh-start path either.

**Halt message template:**

```
ABORTING preflight: detached HEAD with active SDD state file(s) present.

Active state file(s):
  <list of state_path + state.branch from inspecting-state's report>

SDD requires a named branch to route resume vs fresh-start decisions safely.
Please switch to a branch (`git checkout <branch>`) and re-invoke the coordinator.
```

Return status `aborted_at_preflight` with reason `detached_head_with_state`.

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

Overridable via `.sublime-skills/config.yml → preflight.branch_pattern`:
- `feat/<short-name>` for new features (default)
- `fix/<short-name>` if the user describes the work as a bug fix during `discovering-requirements` (renamed at that point if needed)

## Reporting Back

### On success

Return to the coordinator:

```
Preflight complete.
- Branch: feat/user-auth (created from main) | feat/user-auth (resumed)
- Original branch: main
- Working tree: clean
- Status: ready
```

### On abort

Return to the coordinator with one of these reason codes:

```
Preflight aborted.
- Status: aborted_at_preflight
- Reason: config_missing | config_invalid | dirty_working_tree | detached_head_with_state | ambiguous_branch | protected_branch | user_declined
- Message: <the message that was shown to the user>
```

The coordinator surfaces the abort to the user and exits the pipeline.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the config validation step | Mandatory and FIRST — every path the rest of preflight reads comes from `.sublime-skills/config.yml`. |
| Trying to repair `.sublime-skills/config.yml` inline when it fails validation | Don't — abort with `config_invalid` and direct the user to `bootstrapping-project`. |
| Trying to commit/stash/discard dirty files | Don't — abort. The user handles their own mess. |
| Trying to "auto-switch" off an inappropriate branch | Don't — abort. The user picks the right starting branch. |
| Trying to write a state file from this skill | The state file doesn't exist yet — only `writing-specs` initializes it. Return outcomes to the coordinator. |
| Creating a branch without user confirmation | Confirm names; users have naming conventions you can't infer |
| Proceeding past a protected/ambiguous branch case | Abort; don't guess at user intent |
| Running `git checkout main` to "fix" being on the wrong branch | NEVER — that loses work and changes user state silently |
| Second-guessing the `inspecting-state` resume decision | Trust the coordinator's routing; enforce branch contract only |

## Red Flags

- About to skip the config validation step → STOP; it's Step 1 of the Checklist, not optional
- About to edit `.sublime-skills/config.yml` to make the validator pass → STOP; abort and direct user to `bootstrapping-project`
- About to run `git commit`, `git stash`, `git clean`, or `git restore` to "clean up" dirty files → STOP; abort instead
- About to `git checkout <existing branch>` to "fix" an inappropriate starting branch → STOP; abort instead
- About to try `Read`/`Write` on a state.json file → STOP; state file is initialized in Stage 2 (writing-specs), not here
- About to proceed past an ambiguous-branch case "because the user probably meant ..." → STOP; abort and let the user clarify
- About to dispatch a subagent for branch-detection or any other work → STOP; preflight runs entirely inline
