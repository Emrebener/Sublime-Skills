---
name: ss-sdd-coordinator
description: Use as the entry point for spec-driven feature development. Drives the full pipeline from preflight through finishing — discovery, spec, reviews, ADRs, plan, reviews, per-task implementation, optional feature testing, finishing. Tracks progress in a per-feature state file so an interrupted run can be resumed from the same conversation.
---

# SDD Coordinator

## Overview

You are the coordinator for a spec-driven development run. You hold the workflow's shape; you delegate the work. Each stage either runs inline (via a phase-skill loaded by your harness) or is dispatched to a subagent.

**Core principle:** You are a thin state machine + dispatcher. All real work happens in phase-skills or subagents. Your job is to know what stage we're in, dispatch the right thing, update state, advance.

**Announce at start (every invocation):** "I'm using the ss-sdd-coordinator skill to drive this SDD run."

## Hard Gates

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- Do NOT perform halt checks (config validation, git workspace, detached HEAD) inline — that's `ss-sdd-preflight`'s job. Stage 0 owns every pre-pipeline halt, and also creates the state file shell.
- Do NOT skip mandatory stages (everything in the pipeline table except those marked optional)
- Optional stages are user-gated — always ask, default per the table
- ALWAYS use the harness's interactive question tool when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool to track progress. The pipeline uses three sequential todo lists, each one replacing the previous:
  1. **Pre-implementation (Stages 0–12)** — at Stage 0, create one todo per row from Stages 0–12, including the optional ones (4, 5, 10). Do NOT include Stages 13–17 in this list.
  2. **Per-task implementation (Stage 13)** — `ss-sdd-implementing-plans` replaces list 1 with one todo per plan task (T001, T002, ...). By then every entry in list 1 is `completed`.
  3. **Post-implementation (Stages 14–17)** — when `ss-sdd-implementing-plans` returns, replace list 2 with one todo per row from Stages 14–17, including the optional ones (14, 15, 16).

  Mark a todo `in_progress` when you start the stage/task and `completed` immediately after it finishes — don't batch updates. **For optional stages: when the user opts out at the gate, mark the todo `completed` straight away (and add the stage to `stages_skipped` in state.json per the existing convention), then advance.** Optional stages are always pre-listed; opt-outs are just a fast path through them.
- Do NOT do work that belongs to phase-skills inline. If a stage has a phase-skill, load it and follow it.
- Do NOT attempt to test the feature yourself if `ss-sdd-testing-implementation` reports MCP_UNAVAILABLE. Surface to user.
- Do NOT proceed past a user-approval gate without explicit approval
- ALWAYS use path-scoped `git add` (list specific paths) for any commit you make directly. Never `git add .` or `git add -A`. SDD allows dirty working trees (preflight warns but doesn't abort); path-scoping is what keeps the user's pre-existing dirty files from being swept into SDD commits.
- During Stages 2–11, the SDD planning artifacts (spec.md, plan.md, ADRs) are uncommitted in the working tree. Do NOT instruct the user (or run yourself) `git stash`, `git restore`, or `git checkout <other-branch>` mid-pipeline — uncommitted artifacts will be displaced and the run is unrecoverable. The state file at `.sublime-skills/state.json` is gitignored and stays in place across branch operations, but the planning artifacts do not. If git operations become necessary mid-pipeline, halt and surface to the user with the risk explicit.

## The Pipeline

`current_stage` is the value the coordinator writes while in the stage; `stages_completed` is what it appends after the stage finishes. Use these for both forward advance and resume mapping.

| # | Stage | Mechanism | Optional? | `current_stage` | `stages_completed` |
|---|---|---|---|---|---|
| 0 | Preflight | Inline via `ss-sdd-preflight` | No | `preflight` | `preflight` |
| 1 | Discovering requirements | Inline via `ss-sdd-discovering-requirements` | No | `discovering` | `discovering` |
| 2 | Writing the spec | Inline via `ss-sdd-writing-specs` | No | `spec_writing` | `spec_written` |
| 3 | Auto spec-review | Subagent uses `ss-sdd-reviewing-specs`; findings via `ss-sdd-receiving-review-findings` | No | `spec_auto_review` | `spec_auto_reviewed` |
| 4 | Optional grill | Inline via `ss-sdd-grilling-specs` | **Yes — ask, default no** | `spec_grill` | `spec_grilled` |
| 5 | Optional 2nd spec-review | Subagent uses `ss-sdd-reviewing-specs`; findings via `ss-sdd-receiving-review-findings` | **Yes — ask, default no** | `spec_second_review` | `spec_second_reviewed` |
| 6 | ADR maintenance | Subagent uses `ss-sdd-maintaining-adrs` | No | `adr_maintenance` | `adrs_maintained` |
| 7 | User spec approval | Inline | No | `spec_approval` | `spec_approved` |
| 8 | Writing the plan | Inline via `ss-sdd-writing-plans` | No | `plan_writing` | `plan_written` |
| 9 | Auto plan-review | Subagent uses `ss-sdd-reviewing-plans`; findings via `ss-sdd-receiving-review-findings` | No | `plan_auto_review` | `plan_auto_reviewed` |
| 10 | Optional 2nd plan-review | Subagent uses `ss-sdd-reviewing-plans`; findings via `ss-sdd-receiving-review-findings` | **Yes — ask, default no** | `plan_second_review` | `plan_second_reviewed` |
| 11 | User plan approval | Inline | No | `plan_approval` | `plan_approved` |
| 12 | Settle feature branch + batch commit | Inline via `ss-sdd-choosing-feature-branch` (silent when on `main` or already on derived branch; prompts when ambiguous; persists `branch_name`) | No | `choosing_branch` | `branch_chosen` |
| 13 | Implementation (sub-pipeline) | Inline via `ss-sdd-implementing-plans` (dispatches per-task subagents) | No | `implementing` | `implementation_complete` |
| 14 | Optional feature testing | Inline via `ss-sdd-testing-implementation` (dispatches tester subagent) | **Yes — ask, default yes** | `testing` | `testing_complete` |
| 15 | Generate handoff | Subagent uses `ss-sdd-generating-handoff` | **Yes — ask, default yes** | `handoff` | `handoff_generated` |
| 16 | Maintain memory file | Subagent uses `ss-sdd-maintaining-memory-file` | **Yes — ask, default yes** (auto-skipped if no memory file configured/detected) | `memory_file` | `memory_file_maintained` |
| 17 | Merge to `main`, delete branch, cleanup | Inline via `ss-sdd-finishing` (`git merge --no-ff` + safe-delete, then `rm` state) | No | `finishing` | `finished` |

A fresh run starts at Stage 0; on re-entry within the same conversation, continue from `current_stage` (read it from state.json). State updates happen at stage boundaries — never mid-stage.

## State File Schema

Canonical at `framework/state-schema.md` (human) and `framework/state-schema.json` (JSON Schema). If your behavior conflicts with those files, the canonical wins. The state file is created as a minimal shell by `ss-sdd-preflight` at Stage 0 (after all validation passes); it's deleted at Stage 17 by `ss-sdd-finishing`. Any state file found at the top of preflight is treated as an orphan and removed silently.

The coordinator persists these fields at stage boundaries (atomic: write `.tmp`, then `mv`): `current_stage`, `stages_completed`, `stages_skipped`, `adr_results` (transcribed from Stage 6 subagent's report), `handoff_path` (from Stage 15 subagent's report), and `memory_file_updated` / `memory_file_path` (from Stage 16 subagent's report). `updated_at` is touched by every writer on every atomic write — coordinator included. All other fields are owned and written by their respective skills (coordinator reads only): the shell fields (`started_at`, initial `current_stage`, initial empty arrays / `tasks`) by `ss-sdd-preflight`; `feature_id` / `short_name` / `work_type` / `spec_path` by `ss-sdd-writing-specs`; `plan_path` by `ss-sdd-writing-plans`; `branch_name` by `ss-sdd-choosing-feature-branch`; the per-task `tasks` map and `final_review_completed` by `ss-sdd-implementing-plans`; `test_status` / `fix_iterations` by `ss-sdd-testing-implementation`; `reviewer_pushbacks` and `spec_auto_review_iterations` / `plan_auto_review_iterations` by `ss-sdd-receiving-review-findings`. The full authoritative table lives in `framework/state-schema.md` under "Field Ownership".

## Commit timing

Through Stages 2–11, SDD writes the planning artifacts (spec.md, plan.md, ADRs) but does NOT commit them — they sit uncommitted in the working tree. `ss-sdd-choosing-feature-branch` at Stage 12 batch-commits them on the chosen branch in two thematic, path-scoped commits (`docs(<feature_id>): spec and plan` + `docs(adr): N decisions for <feature_id>`). From Stage 13 onward, code commits happen per task (Stage 13) or per stage (Stage 16 when the memory file is updated). Stage 14 commits only via the in-loop fixer subagent on test FAIL; Stage 15 makes no commit (handoff lives outside the repo); Stage 17 produces one commit (the `--no-ff` merge on `main`) and then deletes the state file via plain `rm`. `.sublime-skills/state.json` is gitignored and is never committed at any stage. In stage descriptions below, "**No commit (Stage 12 batches)**" is shorthand for this rule.

## User-Requested Changes Classification

Used at Stages 7 (spec approval) and 11 (plan approval). When the user requests changes instead of approving, classify before applying. Default to light-touch when unsure; if it grows substantive mid-edit, stop and reclassify.

| Change type | Examples | Handling |
|---|---|---|
| **Light-touch** | Typo, wording, tightening an FR, adding an edge case, ADR text adjustment, plan task wording | Apply inline via `ss-sdd-receiving-review-findings` discipline. Re-validate. Re-ask for approval. |
| **Substantive — re-discovery** | Decomposition needed, fundamental requirement change, whole story added/removed | Do NOT edit inline. Reset `current_stage` to `discovering`; re-invoke `ss-sdd-discovering-requirements`. |
| **Substantive — ADR overhaul** | An ADR needs replacing, new ADR-worthy decisions emerge (Stage 7 only) | Re-dispatch `ss-sdd-maintaining-adrs` after any spec changes. |
| **Substantive — plan rework** | Phases need restructuring, big chunks of tasks rewritten (Stage 11 only) | Re-enter Stage 8 (`ss-sdd-writing-plans`); the prior plan is overwritten in place. |

## Per-Stage Driving Instructions

For every stage:

1. Update state: `current_stage: "<stage_name>"` (atomic write)
2. Run the stage (load skill, or dispatch subagent, per the Pipeline table)
3. On success: append the stage's `stages_completed` entry, atomic-write. Commit only per the Commit timing section above.
4. Advance.

If a stage fails (subagent returns Issues Found, validator fails, etc.): handle the loop per that stage's protocol. Do not advance until the stage is genuinely complete.

### Stage 0 — Preflight

Load `ss-sdd-preflight`. It validates `.sublime-skills/config.yml`, checks the repo is a git repo, refuses to proceed on detached HEAD, warns (does not abort) on a dirty working tree, and — once everything passes — creates `.sublime-skills/state.json` as a minimal shell (removing any orphan state file from a dead prior pipeline first). **It does NOT create branches** — branch decision happens at Stage 12.

After preflight returns ready, the config is known-valid and you can use `framework/get-config-value.sh <block> <key>` (exit 0 + value on stdout, or exit 2 if missing) for scalar lookups throughout the run. For lists / multi-line strings, parse YAML directly.

The coordinator carries from Stage 0 in-memory: the current branch name (preflight already read it) and any cached config values used downstream (e.g., `branching.branch_pattern`, grill cap, memory file size budget). The state file shell is on disk; the coordinator's first stage-boundary write (advancing `current_stage` to `discovering`) goes into it normally.

On any abort (`config_missing` / `config_invalid` / `not_a_git_repo` / `detached_head` / `user_declined`): surface preflight's message verbatim and exit. Do not advance. No state file is written on abort.

### Stage 1 — Discovering Requirements

Load `ss-sdd-discovering-requirements`. Follow it. The coordinator carries the discovery outputs in-memory: `short_name`, `work_type` (`feature` or `fix`), the user-approved discovery sections, and ADR-candidate decisions. `ss-sdd-writing-specs` (Stage 2) persists `short_name` / `work_type` / `feature_id` / `spec_path` into state.json; `ss-sdd-choosing-feature-branch` (Stage 12) reads `work_type` back to derive the branch prefix.

### Stage 2 — Writing the Spec

Load `ss-sdd-writing-specs`. Pass it the in-memory discovery outputs (including `work_type`) — it writes the feature-identifying fields into the existing state file shell.

**Validator enforcement:** `ss-sdd-writing-specs` must return the validator's PASS line verbatim. Re-run yourself:

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/validate-spec.sh docs/specs/NNN-<short-name>/spec.md
```

If the fresh run disagrees with the writer's report, halt and surface (writer drift or lie). After PASS, advance `current_stage` to `spec_auto_review`, append `spec_written`. **No commit (Stage 12 batches).**

### Stage 3 — Auto Spec-Review

Dispatch a fresh subagent. Prompt includes: `SPEC_PATH`, `CONTEXT_FILES` (constitution + ADRs + architecture + glossary paths that exist), `REVIEW_FOCUS: first-pass`, and "Use the `ss-sdd-reviewing-specs` skill."

Process findings via `ss-sdd-receiving-review-findings` (load it inline). It handles evaluate/fix/push-back/escalate, including the cap-2 fix-loop escalation protocol.

### Stage 4 — Optional Grill (User-Gated)

Ask: "Want a grill session to stress-test the spec? (yes/no, default no)"

If no: add `spec_grill` to `stages_skipped`. If yes: load `ss-sdd-grilling-specs`. Follow it. **No commit (Stage 12 batches).**

### Stage 5 — Optional 2nd Spec-Review (User-Gated)

Ask: "Want a second-pass review for extra rigor? (yes/no, default no)"

If no: add `spec_second_review` to `stages_skipped`. If yes: dispatch with `REVIEW_FOCUS: second-pass — focus on <user-specified topic or "independent angle">`. Process via `ss-sdd-receiving-review-findings`.

### Stage 6 — ADR Maintenance

Dispatch a fresh subagent. Prompt includes: `SPEC_PATH`, `ADR_DIR` (hardcoded `docs/adr`), `EXISTING_ADRS` (list), `DECISIONS_CAPTURED` (in-memory from discovery + grill), and "Use the `ss-sdd-maintaining-adrs` skill."

If ADRs were created or superseded, record `adr_results` in state (transcribed from the subagent's report). Zero ADRs is a valid outcome. **No commit (Stage 12 batches).**

### Stage 7 — User Spec Approval

Tell user:

> "Spec and ADRs ready:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list]
>
> One of:
> - **Approve** — flip ADRs Proposed → Accepted in your working tree, then proceed (default)
> - **Request changes** — what to change"

**On Approve:** edit each ADR's `Status: Proposed` → `Status: Accepted` (file edits only). Advance. **No commit (Stage 12 batches).**

**On Request changes:** classify per the [User-Requested Changes Classification](#user-requested-changes-classification) subsection above, then apply.

### Stage 8 — Writing the Plan

Load `ss-sdd-writing-plans`. Follow it. Same validator-enforcement pattern as Stage 2 — re-run `validate-plan.sh`; halt on disagreement. **No commit (Stage 12 batches).**

### Stage 9 — Auto Plan-Review

Dispatch with: `PLAN_PATH`, `SPEC_PATH`, `CONTEXT_FILES`, `REVIEW_FOCUS: first-pass`, "Use the `ss-sdd-reviewing-plans` skill." Process findings via `ss-sdd-receiving-review-findings`.

### Stage 10 — Optional 2nd Plan-Review (User-Gated)

Same pattern as Stage 5.

### Stage 11 — User Plan Approval

Tell user: "Plan ready: docs/specs/NNN-<short-name>/plan.md. Approve to choose a feature branch and start implementation, or request changes." Wait for explicit approval.

**On Approve:** advance to Stage 12. **No commit (Stage 12 batches).**

**On Request changes:** classify per the [User-Requested Changes Classification](#user-requested-changes-classification) subsection above, then apply.

### Stage 12 — Settle Feature Branch + Batch Commit

Load `ss-sdd-choosing-feature-branch`. Pass it: `feature_id` and `short_name`. The skill reads the current branch itself (`git branch --show-current`) since the decision rule depends on it; it also reads `state.work_type` and `branching.branch_pattern` from config. The state file at `.sublime-skills/state.json` is read and written by the skill but not committed.

The skill applies an opinionated rule: silent stay when already on the derived branch (resume / build-on-top); silent `git checkout -b` when on `main` and the derived branch is free; collision-prompt when on `main` and the derived branch already exists; ambiguity-prompt (with a mandatory "merged + deleted at Stage 17" warning) when on any other branch. Then it path-scope batch-commits the planning artifacts in two thematic commits (spec + plan / ADRs), and persists `branch_name` into state so Stage 17 knows what to merge.

On abort (`branch_creation_failed` / `checkout_failed` / `user_declined` / `commit_failed`): surface and halt. The user resolves and re-invokes the coordinator.

After success: append `branch_chosen` to `stages_completed`. Advance to Stage 13.

### Stage 13 — Implementation (sub-pipeline)

Load `ss-sdd-implementing-plans`. It orchestrates the per-task loop (implementer + 2 reviewers, then final review). State's `tasks` map is owned by that skill — initialized/synced on entry, updated per task. On resume into Stage 13, `ss-sdd-implementing-plans` handles per-task resumption (continuing an `in_progress` task or picking up the first `pending` one); the coordinator just loads it.

**Continuous execution:** Stage 13 does NOT pause between tasks for human check-in. Only stop when: a task returns BLOCKED that can't be resolved by the coordinator (e.g., needs user input); a review loop hits its 3-iteration cap; the plan itself appears wrong; or all tasks complete. Coordinator-driven pauses between tasks waste run time and break the per-task isolation.

After all tasks complete and final review passes, replace the per-task todo list with the post-implementation list (one todo per row from Stages 14–17, including the optional ones 14, 15, 16). Then advance to Stage 14.

### Stage 14 — Optional Feature Testing (User-Gated)

Ask: "Implementation complete. Run feature-level tests now? (yes/no, default yes)"

If no: add `testing` to `stages_skipped`. Advance to Stage 15.

If yes: load `ss-sdd-testing-implementation`. It dispatches the tester subagent and handles the FAIL → fixer loop. **If the tester reports `MCP_UNAVAILABLE`, do NOT pick up Bash/Playwright/curl to test it yourself — surface the manual test plan to user.**

### Stage 15 — Generate Handoff (User-Gated)

Ask: "Generate a handoff document for this run? (yes/no, default yes — recommended when someone else may pick this up, or you'll iterate on it later in a fresh session)"

If no: add `handoff` to `stages_skipped`. Advance to Stage 16.

If yes, resolve `HANDOFF_DIR` from `$HOME` and the current repo's basename, and ensure the directory exists:

```bash
REPO_BASENAME=$(basename "$(git rev-parse --show-toplevel)")
HANDOFF_DIR="$HOME/.sublime-skills/handoffs/$REPO_BASENAME"
mkdir -p "$HANDOFF_DIR"
```

`HANDOFF_DIR` is always an absolute path outside the repo. If `mkdir -p` fails (no write access to `$HOME`, etc.), surface the OS error verbatim and abort Stage 15. No retry, no fallback location.

Dispatch a fresh subagent with: `STATE_PATH`, `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `BRANCH`, `BASE_SHA` (`git merge-base HEAD <base>`), `HEAD_SHA`, `HANDOFF_DIR`, and "Use the `ss-sdd-generating-handoff` skill."

After return: re-run `validate-handoff.sh <handoff-path>`. If FAIL — especially "potential unredacted secret" — halt; do NOT record `handoff_path`. Otherwise record `handoff_path` in state and tell the user the absolute path. The handoff file lives outside the repo; no commit.

### Stage 16 — Maintain Memory File (User-Gated)

Resolve `MEMORY_FILE_PATH` BEFORE asking:
1. `memory_file.path` in config — if set, use it (absolute or repo-relative; both OK)
2. Otherwise auto-detect by checking for these in order at repo root: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`. First match wins.
3. If neither config nor auto-detect finds a path: auto-skip (no memory file to maintain). Add `memory_file` to `stages_skipped`. Do NOT prompt — there's nothing to maintain.

If a path was resolved, ask: "Check memory file `<MEMORY_FILE_PATH>` for updates from this run? (yes/no, default yes — most runs result in 'no update needed', so this is cheap to say yes to)"

If no: add `memory_file` to `stages_skipped`. Advance to Stage 17.

If yes, resolve `CHARACTER_LIMIT` from `memory_file.character_limit` (default 40000).

Read `EXISTING_CONTENT` from `MEMORY_FILE_PATH`. The file should exist — preflight's `validate-config.sh` halts on a configured-but-missing memory file (orphan path), so by Stage 16 the file is on disk or the path is null. If the file is somehow missing here (e.g., deleted mid-run), the maintainer's pre-check will refuse with `skipped (file missing on disk)` — see outcomes below.

Dispatch a fresh subagent with: `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `MEMORY_FILE_PATH`, `CHARACTER_LIMIT`, `EXISTING_CONTENT`, and "Use the `ss-sdd-maintaining-memory-file` skill."

The subagent returns one of:
- **updated** — memory file was written. If `MEMORY_FILE_PATH` is inside the repo, commit it path-scoped:
  ```
  git add <MEMORY_FILE_PATH>
  git commit -m "docs(memory): update from NNN-short-name"
  ```
  If it resolves outside the repo, skip the commit and inform the user where it was written.
- **no update needed** — most common outcome. Advance.
- **skipped (no path configured)** — no memory file configured or detected. Add `memory_file` to `stages_skipped`; advance.
- **skipped (file missing on disk)** — configured path points to a missing file (mid-run deletion or preflight bypass). Add `memory_file` to `stages_skipped`; surface the maintainer's hint to the user (re-run `ss-bs-bootstrapping-project` or `ss-bs-auditing-project` to re-author the memory file); advance.

Record outcome in state: `memory_file_updated: true | false`. If updated, also record `memory_file_path` in state for the handoff doc / debugging.

### Stage 17 — Merge to `main` and Finish

Load `ss-sdd-finishing`. It validates state, prints the summary, then closes the loop by `git checkout main && git merge --no-ff $branch_name` and `git branch -d $branch_name` on success. Finally it deletes the state file via plain `rm`.

If the merge fails (conflicts, hook rejection, signing failure): the skill halts and surfaces git's output verbatim, leaves the working tree as-is, and leaves the state file in place. The user resolves the conflict (or completes the merge commit themselves) and re-invokes the coordinator — Stage 17 is naturally idempotent (`git merge --no-ff <already-merged>` returns 0 with "Already up to date").

After finishing: SDD run is done. The user is on `main`, the merge commit is in history, the feature branch is gone. No push — that's the user's call.

## Loading Skills

Load each phase-skill via your harness's skill mechanism, using the skill's name. If installed under a namespace (e.g., `spec-driven-development:ss-sdd-writing-specs`), use the namespaced name. Load phase-skills only when their stage is active — don't pre-load.

## Subagent Dispatch

Dispatch fresh subagents (no inherited context) via your harness's subagent dispatch mechanism. Always:

- Pass content inline (don't make subagents re-read large files unless necessary)
- Tell the subagent which skill to use
- Specify the return format expected
- Never run multiple implementation subagents in parallel — sequential only

## Failure Protocols

Compact rule table for the three failure modes. Full per-mode handling lives in `docs/sdd/operations.md`; consult it only when this table doesn't cover the situation.

| Failure | When it fires | Absolute rules | Action |
|---|---|---|---|
| **Commit failure** | `git commit` returns non-zero at Stage 12 batch commits, Stage 13 task commits, or Stage 16 memory commit | Never `--no-verify`, `--no-gpg-sign`, `--force`. Never amend a published commit. | Retry once **only** when the cause is clear and auto-fixable (e.g., formatter modified files; re-stage path-scoped, re-commit). Otherwise halt and surface git's output verbatim. |
| **Merge failure** | `git merge --no-ff <branch_name>` returns non-zero at Stage 17 (conflicts, hook rejection, signing failure) | Never `--no-verify`/`--no-gpg-sign`. Never auto-`git merge --abort`. Never `git branch -D`. Never delete `.sublime-skills/state.json` before the merge succeeds. | Halt and surface git's output verbatim; leave the working tree as-is. User resolves manually and re-invokes — Stage 17 is naturally idempotent (`git merge --no-ff` on an already-merged branch returns 0 with "Already up to date"). |
| **Subagent failure** | Dispatched subagent times out, crashes, returns malformed output, or skips required fields (any of Stages 3, 5, 6, 9, 10, 13 reviewers, 14 tester, 15 handoff, 16 memory) | Max one retry per failure mode. Never substitute the coordinator's own work for the failed subagent's. Never run retries in parallel. | Retry once. If still failing, surface to user with four options: retry again with adjusted prompt / skip (optional stages only) / abort the run / provide-result-manually (user pastes the expected output and coordinator continues). |

When in doubt about edge cases, follow operations.md.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Updating state mid-stage | Updates happen at stage boundaries (atomic) |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |
| Skipping user-approval gates | Mandatory; never auto-proceed |
| Auto-skipping an optional stage | Always ask user; never auto-skip or auto-include |
| Doing phase-skill work inline | Load the phase-skill or dispatch the subagent |
| Coordinator running feature tests when MCP_UNAVAILABLE | NEVER — surface to user with manual test plan |

## Red Flags

- About to advance past a user-approval gate without typed approval → STOP
- About to auto-skip an optional stage → STOP; user decides
- About to start two implementer subagents in parallel → STOP
- About to test the feature yourself after MCP_UNAVAILABLE → STOP; not your job
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP

## Sibling Skills

- `ss-bs-bootstrapping-project` (in the `project-bootstrap` family) — one-time per-project bootstrap (constitution, conventions, config). User-invoked directly, not by this coordinator.
