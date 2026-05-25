---
name: ss-sdd-preflight-checks
description: Use at the very start of a spec-driven-development pipeline run, before any spec drafting, planning, or implementation work begins. A permissive validation gate — confirms config is valid, the repo is a git repo, the user is on a named branch, warns (does not abort) on a dirty working tree, and creates the SDD state file shell once everything checks out.
---

# Preflight Checks

## Overview

Verify the repo is in a workable state for an SDD pipeline run: `.sublime-skills/config.yml` is present and valid, we're inside a git repo, and HEAD is attached (named branch, not detached). A dirty working tree is allowed — SDD commits are path-scoped to its own artifacts, so the user's pre-existing dirty files stay untouched. Once every check passes, preflight creates `.sublime-skills/state.json` as a minimal shell, removing any orphan state file from a previous dead pipeline first.

This skill **does NOT** create branches. Branch policy is decided much later, at Stage 12 (`ss-sdd-choosing-feature-branch`), right before implementation starts.

**Core principle:** Permissive by default. Only abort on conditions that genuinely make SDD impossible to run (no git, no config, no branch).

**Announce at start:** "I'm using the ss-sdd-preflight-checks skill to verify the repo state."

## Contract

### What this skill ALWAYS ensures (or aborts trying)

1. `.sublime-skills/config.yml` is present and passes `validate-config.sh`
2. The current directory is inside a git repository
3. HEAD is attached (a named branch, not detached)
4. `.sublime-skills/state.json` exists as a fresh shell (any pre-existing state file is treated as an orphan from a dead prior pipeline and removed first)
5. After this skill returns, the coordinator can safely begin spec/plan work and trust every path in `.sublime-skills/config.yml`

### What this skill aborts on (fail-fast cases)

| Abort case | Reason code | Trigger |
|---|---|---|
| Config missing | `config_missing` | `.sublime-skills/config.yml` doesn't exist (`validate-config.sh` exit 2) |
| Config invalid | `config_invalid` | `validate-config.sh` exit 1 (malformed YAML, orphan path, unknown key, etc.) |
| Not a git repo | `not_a_git_repo` | `git rev-parse --git-dir` exits non-zero |
| Detached HEAD | `detached_head` | `git branch --show-current` returns empty (no branch to commit to) |
| User declined | `user_declined` | User said "no" to the dirty-tree confirmation prompt |

State creation is the LAST step — if any check above aborts, no state file is written, so an aborted preflight leaves no trace. Preflight runs inline (no subagents).

## Hard Gates

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.

## Checklist

The coordinator MUST track each of these as a todo item and complete them in order:

1. Run `validate-config.sh`. If exit code is non-zero: **ABORT** per the Config Validation Protocol below.
2. Run `git rev-parse --git-dir`. If exit code is non-zero: **ABORT** per the Git Repo Protocol below.
3. Run `git branch --show-current`. If it returns empty: **ABORT** per the Detached HEAD Protocol below.
4. Run `git status --porcelain`. If it returns any output: **WARN** per the Dirty Tree Protocol below (proceed-or-abort, not automatic abort).
5. Create the state file shell per the State Shell Protocol below.
6. Report ready — return preflight outcomes (current branch) to the coordinator.

## Config Validation Protocol

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/validate-config.sh
```

| Exit code | Meaning | Action |
|---|---|---|
| `0` | PASS | Continue to Step 2 |
| `1` | FAIL — config has issues | **ABORT** with `config_invalid`. Show the validator's stderr verbatim. |
| `2` | Config file missing | **ABORT** with `config_missing`. The project hasn't been bootstrapped for SDD. |

**Halt message template:**

```
ABORTING preflight: `.sublime-skills/config.yml` is missing or invalid.

<validator output verbatim>

Run the `ss-bs-bootstrapping-project` skill (in the `skills/project-bootstrap/` family)
to scaffold or fix the config, then re-invoke the SDD coordinator.
```

Do not attempt to repair config inline. Returning the user to bootstrap is the correct outcome.

## Git Repo Protocol

```bash
git rev-parse --git-dir > /dev/null 2>&1
```

If non-zero, the current directory isn't a git repo (or isn't inside one). SDD requires git — every stage commits artifacts at some point.

**Halt message template:**

```
ABORTING preflight: not a git repository.

SDD requires a git repository to commit pipeline artifacts (spec, plan,
ADRs, code) to. Initialize one and re-invoke:

    git init
    git commit --allow-empty -m "Initial commit"
```

Don't auto-`git init` — that's the user's call.

## Detached HEAD Protocol

If `git branch --show-current` returns an empty string, HEAD is detached.

**ABORT** with `detached_head` unconditionally. Reason: SDD's later stages (especially Stage 12 batch-commit and per-task implementer commits) require a named branch.

**Halt message template:**

```
ABORTING preflight: detached HEAD.

SDD requires a named branch to commit to. You're currently on a detached HEAD.

Please switch to a branch:

    git checkout <branch-name>

Or create one from this commit:

    git checkout -b <new-branch>

Then re-invoke the SDD coordinator.
```

## Dirty Tree Protocol

If `git status --porcelain` returns any output, the working tree has uncommitted changes. **WARN, do not abort.** SDD can run on top of dirty work because all SDD-driven commits are path-scoped to its own artifacts (`docs/specs/...`, `docs/adr/...`, and code files the implementer subagents explicitly touch). Your other dirty files stay untouched.

Show the user the dirty files and ask via the harness's interactive question tool:

```
Working tree has uncommitted changes:

  M  src/some-existing-file.ts
  ?? notes/scratch.md
  ...

SDD will only commit its own artifacts (spec, plan, ADRs, and code from
implementation tasks). The SDD state file at `.sublime-skills/state.json`
is gitignored and is never committed. Your other dirty files stay
untouched throughout the pipeline.

Proceed with the dirty tree? (yes/no)
```

- **Yes:** continue to Step 5.
- **No:** ABORT with `user_declined`. The user can stash/commit/discard their changes manually and re-invoke.

This is the ONLY user prompt in preflight. The other checks are pure validation.

## State Shell Protocol

After every validation check passes, create `.sublime-skills/state.json`. If a state file already exists at this path, it is an orphan from a dead prior pipeline (normal flow at Stage 17 deletes it via `ss-sdd-finishing`); remove it silently and write the fresh shell.

```bash
mkdir -p .sublime-skills
rm -f .sublime-skills/state.json

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > .sublime-skills/state.json.tmp <<JSON
{
  "started_at": "$NOW",
  "updated_at": "$NOW",
  "current_stage": "preflight",
  "stages_completed": [],
  "stages_skipped": [],
  "tasks": {}
}
JSON
mv .sublime-skills/state.json.tmp .sublime-skills/state.json
```

The atomic-write pattern (`.tmp` then `mv`) is mandatory for every state write — see `framework/state-schema.md` "Atomic write pattern (required)".

The shell is intentionally minimal: feature-identifying fields (`feature_id`, `short_name`, `work_type`, `spec_path`) aren't knowable yet — discovery (Stage 1) and writing-specs (Stage 2) fill those in. See `framework/state-schema.md` for the full ownership table.

## Reporting Back

### On success

Return to the coordinator:

```
Preflight complete.
- Branch: <current branch>
- Working tree: clean | dirty (proceeding per user confirmation)
- State file: created (shell) | created (orphan removed first)
- Status: ready
```

### On abort

```
Preflight aborted.
- Status: aborted_at_preflight
- Reason: config_missing | config_invalid | not_a_git_repo | detached_head | user_declined
- Message: <the message that was shown to the user>
```

The coordinator surfaces the abort to the user and exits the pipeline.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the config validation step | Mandatory and FIRST — every path the rest of the pipeline reads comes from `.sublime-skills/config.yml`. |
| Trying to repair `.sublime-skills/config.yml` inline when it fails validation | Don't — abort with `config_invalid` and direct the user to `ss-bs-bootstrapping-project`. |
| Aborting on a dirty working tree | A dirty tree is a WARN, not an abort. Ask the user; default to proceeding if they confirm. |
| Trying to commit/stash/discard dirty files | NEVER — SDD lets the user keep their dirty files; path-scoped commits protect them. |
| Trying to create a feature branch here | NEVER — that's Stage 12's job. Preflight just validates that a branch exists. |
| Auto-`git init`ing a non-repo | NEVER — surface the abort message and let the user run `git init` themselves. |
| Aborting on detached HEAD only when state files exist | Detached HEAD is an UNCONDITIONAL abort. SDD needs a named branch. |
| Dispatching a subagent for any work | NEVER — preflight runs entirely inline. |
| Writing the state shell before all checks pass | NEVER — shell write is the LAST step, so an aborted preflight leaves no trace. |
| Asking the user "discard orphan state?" | NEVER — there's nothing to ask. Orphans are silently removed. Cross-session resume isn't supported; any pre-existing state file at preflight entry is unambiguously dead. |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |

## Red Flags

- About to skip the config validation step → STOP; it's Step 1 of the Checklist, not optional
- About to edit `.sublime-skills/config.yml` to make the validator pass → STOP; abort and direct user to `ss-bs-bootstrapping-project`
- About to run `git init` automatically → STOP; surface abort message
- About to `git commit`, `git stash`, `git clean`, or `git restore` to "clean up" dirty files → STOP; SDD allows dirty files
- About to create a feature branch from here → STOP; that's Stage 12 (`ss-sdd-choosing-feature-branch`)
- About to `git checkout` to switch branches → STOP; not preflight's job
- About to dispatch a subagent for branch-detection or any other work → STOP; preflight runs entirely inline
- About to write the state shell before all checks have passed → STOP; shell write is the LAST step
- About to prompt the user before removing an orphan state.json → STOP; remove silently
- About to type `git add -f .sublime-skills/state.json` → STOP
