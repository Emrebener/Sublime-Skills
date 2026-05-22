---
name: sdd-coordinator
description: Use as the entry point for spec-driven feature development. Drives the full pipeline from preflight through finishing — discovery, spec, reviews, ADRs, plan, reviews, per-task implementation, optional feature testing, finishing. Tracks progress in a per-feature state file so an interrupted run can be resumed from the same conversation.
---

# SDD Coordinator

## Overview

You are the coordinator for a spec-driven development run. You hold the workflow's shape; you delegate the work. Each stage either runs inline (via a phase-skill loaded by your harness) or is dispatched to a subagent.

**Core principle:** You are a thin state machine + dispatcher. All real work happens in phase-skills or subagents. Your job is to know what stage we're in, dispatch the right thing, update state, advance.

**Announce at start (every invocation):** "I'm using the sdd-coordinator skill to drive this SDD run."

## Hard Gates

- Do a quick resume check on every invocation (Step 1 below) before doing anything else
- Do NOT perform halt checks (config validation, git workspace, detached HEAD) inline — that's `preflight-checks`'s job. Stage 0 owns every pre-pipeline halt.
- Do NOT skip mandatory stages (everything in the pipeline table except those marked optional)
- Optional stages are user-gated — always ask, default per the table
- ALWAYS use the harness's interactive question tool when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool to track progress through the pipeline. Build the initial list in Step 2: one todo per stage you'll actually run (mandatory stages always; optional stages added when the user opts in). Mark a todo `in_progress` when you start the stage and `completed` immediately after it finishes — don't batch updates. The user uses this list to see where you are in a multi-hour run; running without it leaves them blind.
- Do NOT do work that belongs to phase-skills inline. If a stage has a phase-skill, load it and follow it.
- Do NOT attempt to test the feature yourself if `testing-implementation` reports MCP_UNAVAILABLE. Surface to user.
- Do NOT proceed past a user-approval gate without explicit approval
- ALWAYS use path-scoped `git add` (list specific paths) for any commit you make directly. Never `git add .` or `git add -A`. SDD allows dirty working trees (preflight warns but doesn't abort); path-scoping is what keeps the user's pre-existing dirty files from being swept into SDD commits.
- During Stages 2–11, SDD artifacts (spec, plan, ADRs, state.json) are uncommitted. Do NOT instruct the user (or run yourself) `git stash`, `git restore`, or `git checkout <other-branch>` mid-pipeline — uncommitted artifacts will be displaced and the run is unrecoverable. If git operations become necessary mid-pipeline, halt and surface to the user with the risk explicit.

## The Pipeline

| # | Stage | Mechanism | Optional? |
|---|---|---|---|
| 0 | Preflight | Inline via `preflight-checks` | No |
| 1 | Discovering requirements | Inline via `discovering-requirements` | No |
| 2 | Writing the spec | Inline via `writing-specs` | No |
| 3 | Auto spec-review | Subagent uses `reviewing-specs`; findings via `receiving-review-findings` | No |
| 4 | Optional grill | Inline via `grilling-specs` | **Yes — ask user, default no** |
| 5 | Optional 2nd spec-review | Subagent uses `reviewing-specs`; findings via `receiving-review-findings` | **Yes — ask user, default no** |
| 6 | ADR maintenance | Subagent uses `maintaining-adrs` | No |
| 7 | User spec approval + commit | Inline | No |
| 8 | Writing the plan | Inline via `writing-plans` | No |
| 9 | Auto plan-review | Subagent uses `reviewing-plans`; findings via `receiving-review-findings` | No |
| 10 | Optional 2nd plan-review | Subagent uses `reviewing-plans`; findings via `receiving-review-findings` | **Yes — ask user, default no** |
| 11 | User plan approval | Inline | No |
| 12 | Choosing feature branch + batch commit | Inline via `choosing-feature-branch` | No |
| 13 | Implementation (sub-pipeline) | Inline via `implementing-plans` (dispatches per-task subagents) | No |
| 14 | Optional feature testing | Inline via `testing-implementation` (dispatches tester subagent) | **Yes — ask user, default yes** |
| 15 | Generate handoff | Subagent uses `generating-handoff` | **Yes — ask user, default yes** |
| 16 | Maintain memory file | Subagent uses `maintaining-memory-file` | **Yes — ask user, default yes** (auto-skipped if no memory file is configured/detected) |
| 17 | Finishing + cleanup | Inline via `finishing-sdd` | No |

## On Every Invocation: Resume Check (BEFORE anything else)

Do this first, every time the coordinator is invoked.

### Step 1: Resume or Fresh Start

Glob for active state files under the configured spec directory:

```bash
SPEC_DIR=$(./spec-driven-development/scripts/get-config-value.sh paths spec_dir)
SPEC_DIR="${SPEC_DIR:-docs/specs}"
ls "$SPEC_DIR"/*/state.json 2>/dev/null
```

- **No state files found** → fresh start. Confirm intent with the user ("Start a new feature?") and proceed to Step 2.
- **One state file found** → ask the user: "Resume `<feature_id>` at `<current_stage>`?". On yes, jump to the appropriate stage based on `current_stage` (see the Stage Name Mapping below). On no, ask whether to start a fresh feature (leaves the existing state file alone) or abort.
- **Multiple state files found** → list them and ask which to resume, or to start fresh. Multiple active runs is an unusual situation; let the user pick.

Halts on bad config / not-a-repo / detached HEAD happen later inside Stage 0 (`preflight-checks`) — not here.

### Step 2: Build the Todo List

Before running any stage, build the progress todo list using the harness's todo/task tool. One todo per stage you're about to run:

- **Fresh start:** create todos for all mandatory stages (0, 1, 2, 3, 6, 7, 8, 9, 11, 12, 13, 17) up front. Add optional stages (4, 5, 10, 14, 15, 16) as you reach them and the user opts in — don't pre-create todos for stages that may not run.
- **Resume:** rebuild the list from `state.stages_completed` + `state.stages_skipped` (mark those `completed`) and the remaining pipeline.

Update discipline:
- Mark the current stage's todo `in_progress` as you begin it
- Mark it `completed` the moment the stage advances (after `stages_completed` is updated)
- Never batch updates; the user is watching this list during the run

An 18-stage pipeline is invisible to the user without it.

### When the State File Exists

Created in **Stage 2** (`writing-specs`). Stages 0-1 run before it exists; their outputs are held by the coordinator in-memory and persisted into the state file by `writing-specs`.

### State File Schema

Canonical at `scripts/state-schema.md` (human) and `scripts/state-schema.json` (JSON Schema). If your behavior conflicts with those files, the canonical wins.

**You write to** `current_stage`, `stages_completed`, `stages_skipped`, `updated_at`, `adr_results`, `handoff_path` at stage boundaries (atomic: write `.tmp`, then `mv`). Other fields are owned by their respective skills — don't touch them.

Stage name mapping (lookup for `current_stage` advance and `stages_completed` append):

| # | `current_stage` | `stages_completed` |
|---|---|---|
| 0 | `preflight` | `preflight` |
| 1 | `discovering` | `discovering` |
| 2 | `spec_writing` | `spec_written` |
| 3 | `spec_auto_review` | `spec_auto_reviewed` |
| 4 | `spec_grill` | `spec_grilled` |
| 5 | `spec_second_review` | `spec_second_reviewed` |
| 6 | `adr_maintenance` | `adrs_maintained` |
| 7 | `spec_approval` | `spec_approved` |
| 8 | `plan_writing` | `plan_written` |
| 9 | `plan_auto_review` | `plan_auto_reviewed` |
| 10 | `plan_second_review` | `plan_second_reviewed` |
| 11 | `plan_approval` | `plan_approved` |
| 12 | `choosing_branch` | `branch_chosen` |
| 13 | `implementing` | `implementation_complete` |
| 14 | `testing` | `testing_complete` |
| 15 | `handoff` | `handoff_generated` |
| 16 | `memory_file` | `memory_file_maintained` |
| 17 | `finishing` | `finished` |

When resuming, advance to the stage one beyond the last `stages_completed` entry. If the last completed stage exists in `stages_skipped` instead, advance to the next mandatory or asked-and-confirmed stage. State updates happen at stage boundaries only — never mid-stage.

**Commit timing.** Through Stages 2–11, SDD writes files (spec, plan, ADRs, state.json) but does NOT commit them — they sit uncommitted in the working tree. The `choosing-feature-branch` skill at Stage 12 batch-commits all of these on the user's chosen branch in three thematic commits. From Stage 13 onward, commits happen per stage by the active skill, alongside its artifacts. The state file deletion at Stage 17 is its own `chore` commit.

## Per-Stage Driving Instructions

For every stage:

1. Update state: `current_stage: "<stage_name>"` (atomic write)
2. Run the stage (load skill, or dispatch subagent, per the pipeline table)
3. On success: add stage name to `stages_completed`, write state. Commit only if the stage is at or past Stage 12 (`choosing-feature-branch`) — Stages 2–11 defer commits per the Commit Timing note above.
4. Advance

If a stage fails (subagent returns Issues Found, validator fails, etc.): handle the loop per that stage's protocol. Do not advance until the stage is genuinely complete.

### Stage 0 — Preflight

Load `preflight-checks`. It validates `.sublime-skills/config.yml`, checks the repo is a git repo, refuses to proceed on detached HEAD, and warns (does not abort) on a dirty working tree. **It does NOT create branches** — branch decision happens at Stage 12 (`choosing-feature-branch`). State file does NOT yet exist.

After preflight returns ready, the config is known-valid and you can use `scripts/get-config-value.sh <block> <key>` (exit 0 + value on stdout, or exit 2 if missing) for scalar lookups throughout the run. For lists / multi-line strings, parse YAML directly.

On any abort (`config_missing` / `config_invalid` / `not_a_git_repo` / `detached_head` / `user_declined`): surface preflight's message verbatim and exit. Do not advance.

### Stage 1 — Discovering Requirements

Load `discovering-requirements`. Follow it. State file still doesn't exist; hold discovery outputs (short name, work type, approved sections, ADR-candidate decisions) in-memory. The `work_type` (`feature` or `fix`) gets persisted into state.json at Stage 2 and is later read by `choosing-feature-branch` at Stage 12 to derive the suggested branch prefix.

### Stage 2 — Writing the Spec

Load `writing-specs`. Pass it the in-memory discovery outputs (including `work_type`) — it initializes the state file.

**Validator enforcement:** `writing-specs` must return the validator's PASS line verbatim. Re-run yourself:

```bash
./spec-driven-development/scripts/validate-spec.sh docs/specs/NNN-<short-name>/spec.md
```

If the fresh run disagrees with the writer's report, halt and surface (writer drift or lie). After PASS, advance `current_stage` to `spec_auto_review`, append `spec_written`. **Do NOT commit** — the spec and state file stay uncommitted; `choosing-feature-branch` (Stage 12) will batch-commit them.

### Stage 3 — Auto Spec-Review

Dispatch a fresh subagent. Prompt includes: `SPEC_PATH`, `CONTEXT_FILES` (constitution + ADRs + architecture + glossary paths that exist), `REVIEW_FOCUS: first-pass`, and "Use the `reviewing-specs` skill."

Process findings via `receiving-review-findings` (load it inline). It handles evaluate/fix/push-back/escalate, including the cap-2 fix-loop escalation protocol.

### Stage 4 — Optional Grill (User-Gated)

Ask: "Want a grill session to stress-test the spec? (yes/no, default no)"

If yes: load `grilling-specs`. Follow it. **Do NOT commit** — spec edits accumulate uncommitted until `choosing-feature-branch` (Stage 12) batch-commits them.

### Stage 5 — Optional 2nd Spec-Review (User-Gated)

Ask: "Want a second-pass review for extra rigor? (yes/no, default no)"

If no: add `spec_second_review` to `stages_skipped`. If yes: dispatch with `REVIEW_FOCUS: second-pass — focus on <user-specified topic or "independent angle">`. Process via `receiving-review-findings`.

### Stage 6 — ADR Maintenance

Dispatch a fresh subagent. Prompt includes: `SPEC_PATH`, `ADR_DIR` (from config `paths.adr_dir` or default), `EXISTING_ADRS` (list), `DECISIONS_CAPTURED` (in-memory from discovery + grill), and "Use the `maintaining-adrs` skill."

If ADRs were created or superseded, record `adr_results` in state. Zero ADRs is a valid outcome. **Do NOT commit** the new ADR files — `choosing-feature-branch` (Stage 12) will batch-commit them.

### Stage 7 — User Spec Approval

Tell user:

> "Spec and ADRs ready:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list]
>
> One of:
> - **Approve** — flip ADRs Proposed → Accepted (in your working tree; commits happen at Stage 12), proceed (default)
> - **Approve, keep ADRs as Proposed** — proceed but leave ADRs untouched (no edits to working tree)
> - **Request changes** — what to change"

**On Approve:** edit each ADR's `Status: Proposed` → `Status: Accepted` (file edits only — do NOT commit). Advance.

**On Approve, keep ADRs as Proposed:** Advance. (No commit; state.json stays uncommitted.)

**On Request changes:** classify before applying.

| Change type | Examples | Handling |
|---|---|---|
| **Light-touch** | Typo, wording, tightening an FR, adding an edge case, ADR text adjustment | Apply inline via `receiving-review-findings` discipline. Re-validate. Re-ask for approval. |
| **Substantive — re-discovery** | Decomposition needed, fundamental requirement change, whole story added/removed | Do NOT edit inline. Reset `current_stage` to `discovering`; re-invoke `discovering-requirements`. |
| **Substantive — ADR overhaul** | An ADR needs replacing, new ADR-worthy decisions emerge | Re-dispatch `maintaining-adrs` after any spec changes. |

If unsure, default to light-touch; if it grows substantive mid-edit, stop and reclassify.

### Stage 8 — Writing the Plan

Load `writing-plans`. Follow it. Same validator-enforcement pattern as Stage 2 — re-run `validate-plan.sh`; halt on disagreement. **Do NOT commit** — the plan and state.json stay uncommitted; `choosing-feature-branch` (Stage 12) will batch-commit them.

### Stage 9 — Auto Plan-Review

Dispatch with: `PLAN_PATH`, `SPEC_PATH`, `CONTEXT_FILES`, `REVIEW_FOCUS: first-pass`, "Use the `reviewing-plans` skill." Process findings via `receiving-review-findings`.

### Stage 10 — Optional 2nd Plan-Review (User-Gated)

Same pattern as Stage 5.

### Stage 11 — User Plan Approval

Tell user: "Plan ready: docs/specs/NNN-<short-name>/plan.md. Approve to choose a feature branch and start implementation, or request changes." Wait for explicit approval. (No commit — artifacts remain uncommitted through Stage 11.)

### Stage 12 — Choosing Feature Branch + Batch Commit

Load `choosing-feature-branch`. Pass it: `feature_id`, `short_name`, the current branch (`git branch --show-current`), and the set of uncommitted artifact paths (spec.md, plan.md, ADRs, state.json).

The skill asks the user a 3-way prompt (create suggested branch / different name / stay on current), optionally runs `git checkout -b`, then path-scope batch-commits the SDD artifacts in three thematic commits (spec / ADRs / plan + state).

On abort (`branch_creation_failed` / `user_declined` / `commit_failed`): surface and halt. The user resolves and re-invokes the coordinator.

After success: append `branch_chosen` to `stages_completed`. Advance to Stage 13.

### Stage 13 — Implementation (sub-pipeline)

Load `implementing-plans`. It orchestrates the per-task loop (implementer + 2 reviewers, then final review). State's `tasks` map is initialized/synced and updated per task.

After all tasks complete and final review passes:

```
git add docs/specs/NNN-<short-name>/state.json
git commit -m "chore(NNN-short-name): mark implementation complete"
```

### Stage 14 — Optional Feature Testing (User-Gated)

Ask: "Implementation complete. Run feature-level tests now? (yes/no, default yes)"

If yes: load `testing-implementation`. It dispatches the tester subagent and handles the FAIL → fixer loop. **If the tester reports `MCP_UNAVAILABLE`, do NOT pick up Bash/Playwright/curl to test it yourself — surface the manual test plan to user.**

### Stage 15 — Generate Handoff (User-Gated)

Ask: "Generate a handoff document for this run? (yes/no, default yes — recommended when someone else may pick this up, or you'll iterate on it later in a fresh session)"

If no: add `handoff` to `stages_skipped`. Advance to Stage 16.

If yes, resolve `HANDOFF_DIR`: read `paths.handoff_dir` from config. If it starts with `/` or `~`, treat as absolute (expand `~`); set `OUTSIDE_REPO=true` if the resolved path falls outside `git rev-parse --show-toplevel`. Otherwise repo-relative, `OUTSIDE_REPO=false`.

Dispatch a fresh subagent with: `STATE_PATH`, `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `BRANCH`, `BASE_SHA` (`git merge-base HEAD <base>`), `HEAD_SHA`, `HANDOFF_DIR`, `OUTSIDE_REPO`, and "Use the `generating-handoff` skill."

After return: re-run `validate-handoff.sh <handoff-path>`. If FAIL — especially "potential unredacted secret" — halt; do NOT commit. Otherwise:

- **`OUTSIDE_REPO=false`:** commit `<handoff-path>` + state.json (`docs(NNN-short-name): handoff document`)
- **`OUTSIDE_REPO=true`:** commit state.json only (`chore(NNN-short-name): record external handoff path`); tell user where the external handoff was written.

Record `handoff_path` in state file.

### Stage 16 — Maintain Memory File (User-Gated)

Resolve `MEMORY_FILE_PATH` BEFORE asking:
1. `memory_file.path` in config — if set, use it (absolute or repo-relative; both OK)
2. Otherwise auto-detect by checking for these in order at repo root: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`. First match wins.
3. If neither config nor auto-detect finds a path: auto-skip (no memory file to maintain). Add `memory_file` to `stages_skipped`. Do NOT prompt — there's nothing to maintain.

If a path was resolved, ask: "Check memory file `<MEMORY_FILE_PATH>` for updates from this run? (yes/no, default yes — most runs result in 'no update needed', so this is cheap to say yes to)"

If no: add `memory_file` to `stages_skipped`. Advance to Stage 17.

If yes, resolve `CHARACTER_LIMIT` from `memory_file.character_limit` (default 40000).

Read `EXISTING_CONTENT` from `MEMORY_FILE_PATH` (empty string if file doesn't exist yet but a path is configured).

Dispatch a fresh subagent with: `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `MEMORY_FILE_PATH`, `CHARACTER_LIMIT`, `EXISTING_CONTENT`, and "Use the `maintaining-memory-file` skill."

The subagent returns one of:
- **updated** — memory file was written. Commit it:
  ```
  git add <MEMORY_FILE_PATH> docs/specs/NNN-<short-name>/state.json
  git commit -m "docs(memory): update from NNN-short-name"
  ```
  (If `MEMORY_FILE_PATH` resolves outside the repo, commit only state.json and inform the user where the external file was written.)
- **no update needed** — the most common outcome. No commit needed for the memory file; advance.
- **skipped** — no memory file configured or detected. Add `memory_file` to `stages_skipped`; advance.

Record outcome in state: `memory_file_updated: true | false`. If updated, also record `memory_file_path` in state for the handoff doc / debugging.

### Stage 17 — Finishing

Load `finishing-sdd`. Follow it. After finishing: SDD run is done.

## Loading Skills

Load each phase-skill via your harness's skill mechanism, using the skill's name. If installed under a namespace (e.g., `spec-driven-development:writing-specs`), use the namespaced name. Load phase-skills only when their stage is active — don't pre-load.

## Subagent Dispatch

Dispatch fresh subagents (no inherited context) via your harness's subagent dispatch mechanism. Always:

- Pass content inline (don't make subagents re-read large files unless necessary)
- Tell the subagent which skill to use
- Specify the return format expected
- Never run multiple implementation subagents in parallel — sequential only

## Failure Protocols

The two failure modes coordinators must handle are documented in full in `docs/sdd/operations.md`:

- **Commit Failure Protocol** — what to do when `git commit` returns non-zero (hook rejection, missing identity, GPG failure, nothing to commit, missing file, merge conflict). The absolute rules: never `--no-verify`, never `--no-gpg-sign`, never `--force`, never amend a published commit. Retry at most once when the cause is clear and auto-fixable (e.g., formatter modified files). Otherwise halt and surface.

- **Subagent Failure Protocol** — what to do when a dispatch times out, crashes, returns malformed output, or skips required fields. Max one retry per failure mode. Never substitute the coordinator's own work for the failed subagent's. Never run retries in parallel. Surface to user with four options: retry / skip (non-mandatory only) / abort / provide-result-manually.

Both protocols list the exact handling for each common failure mode. When in doubt, follow operations.md.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the resume check at session start | Always do the glob-and-ask check first |
| Updating state mid-stage | Updates happen at stage boundaries (atomic) |
| Letting state file get committed in its own noisy commits | Ride-along with relevant code/doc commits |
| Skipping user-approval gates | Mandatory; never auto-proceed |
| Auto-skipping an optional stage | Always ask user; never auto-skip or auto-include |
| Doing phase-skill work inline | Load the phase-skill or dispatch the subagent |
| Coordinator running feature tests when MCP_UNAVAILABLE | NEVER — surface to user with manual test plan |
| Silently picking one of multiple active state files | Always ask user which to resume |

## Red Flags

- About to do work without the resume check first → STOP; glob-and-ask is first
- About to advance past a user-approval gate without typed approval → STOP
- About to auto-skip an optional stage → STOP; user decides
- About to start two implementer subagents in parallel → STOP
- About to test the feature yourself after MCP_UNAVAILABLE → STOP; not your job

## Sibling Skills

- `bootstrapping-project` (in the `project-bootstrap` family) — one-time per-project bootstrap (constitution, conventions, config). User-invoked directly, not by this coordinator.
