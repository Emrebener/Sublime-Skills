---
name: sdd-coordinator
description: Use as the entry point for spec-driven feature development. Drives the full pipeline from preflight through finishing — discovery, spec, reviews, ADRs, plan, reviews, per-task implementation, optional feature testing, finishing. Resumable across sessions via a per-feature state file.
---

# SDD Coordinator

## Overview

You are the coordinator for a spec-driven development run. You hold the workflow's shape; you delegate the work. Each stage either runs inline (via a phase-skill loaded with the Skill tool) or is dispatched to a subagent (via the Task / Agent tool).

**Core principle:** You are a thin state machine + dispatcher. All real work happens in phase-skills or subagents. Your job is to know what stage we're in, dispatch the right thing, update state, advance.

**Announce at start (every invocation):** "I'm using the sdd-coordinator skill to drive this SDD run."

## Hard Gates

- ALWAYS read state first on every invocation (Step 1 below)
- Do NOT perform halt checks (config validation, git workspace, branch state, detached HEAD) inline — that's `preflight-checks`'s job. Stage 0 owns every pre-pipeline halt.
- Do NOT skip mandatory stages (everything in the pipeline table except those marked optional)
- Optional stages are user-gated — always ask, default per the table
- ALWAYS use the harness's interactive question tool (`AskUserQuestion` in Claude Code, or any harness equivalent) when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool (`TodoWrite` in Claude Code's older harness, `TaskCreate` / `TaskUpdate` in newer harnesses, `todo` in Codex, or any harness equivalent) to track progress through the pipeline. Build the initial list right after the resume-check (Step 2 below), in Step 3: one todo per stage you'll actually run (mandatory stages always; optional stages added when the user opts in). Mark a todo `in_progress` when you start the stage and `completed` immediately after it finishes — don't batch updates. The user uses this list to see where you are in a multi-hour run; running without it leaves them blind.
- Do NOT do work that belongs to phase-skills inline. If a stage has a phase-skill, load it and follow it.
- Do NOT attempt to test the feature yourself if `testing-implementation` reports MCP_UNAVAILABLE. Surface to user.
- Do NOT proceed past a user-approval gate without explicit approval

## The Pipeline

| # | Stage | Mechanism | Optional? |
|---|---|---|---|
| 0 | Preflight | Inline via `preflight-checks` | No |
| 1 | Discovering requirements | Inline via `discovering-requirements` | No |
| 2 | Writing the spec | Inline via `writing-specs` | No |
| 3 | Auto spec-review | Subagent uses `reviewing-specs`; findings via `receiving-review-findings` | No |
| 4 | Optional 2nd spec-review | Subagent uses `reviewing-specs`; findings via `receiving-review-findings` | **Yes — ask user, default no** |
| 5 | Optional grill | Inline via `grilling-specs` | **Yes — ask user, default no** |
| 6 | ADR maintenance | Subagent uses `maintaining-adrs` | No |
| 7 | User spec approval + commit | Inline | No |
| 8 | Writing the plan | Inline via `writing-plans` | No |
| 9 | Auto plan-review | Subagent uses `reviewing-plans`; findings via `receiving-review-findings` | No |
| 10 | Optional 2nd plan-review | Subagent uses `reviewing-plans`; findings via `receiving-review-findings` | **Yes — ask user, default no** |
| 11 | User plan approval + commit | Inline | No |
| 12 | Implementation | Inline via `implementing-plans` (dispatches per-task subagents) | No |
| 13 | Optional feature testing | Inline via `testing-implementation` (dispatches tester subagent) | **Yes — ask user, default yes** |
| 14 | Generate handoff | Subagent uses `generating-handoff` | **Yes — ask user, default yes** |
| 15 | Maintain memory file | Subagent uses `maintaining-memory-file` | **Yes — ask user, default yes** (auto-skipped if no memory file is configured/detected) |
| 16 | Finishing + cleanup | Inline via `finishing-sdd` | No |

## On Every Invocation: Resume Check (BEFORE anything else)

This is the very first thing to do, every time the coordinator is invoked. Skipping it is the worst failure mode this skill has.

### Step 1: Run inspecting-state

Load `inspecting-state` via the Skill tool. It runs `scripts/discover-context.sh`, reads every active state file, validates against `scripts/state-schema.json`, and reports current branch + per-state branch match + pre-state interruption signals. **You do not perform state detection inline.**

### Step 2: Decide Based on the Report

Resume vs fresh-start routing — purely interactive decisions, no halts. Halts on bad config / dirty workspace / detached HEAD / etc. happen later, inside Stage 0 (`preflight-checks`).

| Report says | Coordinator action |
|---|---|
| 0 runs + no pre-state signals + on default branch | Fresh start. Confirm: "No active SDD run found. Start a new feature?" |
| 0 runs + pre-state signals | Preflight ran but spec wasn't written. Ask: resume from Stage 1 / start fresh / abandon. |
| 1 run, current branch matches `state.branch` | Confirm: "Resuming `<feature_id>` at `<current_stage>`. Resume? (yes/no)". |
| 1 run, current branch does NOT match `state.branch` | **Do NOT silently resume.** Offer: (1) switch to `<state.branch>` and resume; (2) start new feature on current branch (state stays); (3) abort. |
| 2+ runs, current branch matches exactly one | Offer to resume the match, pick a different one, or start fresh on current branch. |
| 2+ runs, current branch matches none | List them; ask which to resume or start fresh on current. |
| Malformed state | Show issues. Offer: repair (user-guided), discard, or abort. Never silently overwrite. |

**Routing rules:**
- The coordinator NEVER `git checkout`s to switch branches on its own. If user picks "switch and resume," instruct them to switch and re-invoke (or with explicit consent run the checkout this session).
- "Match" = exact string equality between `git branch --show-current` and `state.branch`.
- Detached HEAD with active state is handled by `preflight-checks` — don't second-guess it here.

After routing, pass the inspecting-state report to `preflight-checks` (Stage 0) so it can apply its own checks against the decision (e.g., confirming the resume branch matches).

### Step 3: Build the Todo List

After the resume routing decision and BEFORE running any stage, build the progress todo list using the harness's todo/task tool. One todo per stage you're about to run:

- **Fresh start:** create todos for all mandatory stages (0, 1, 2, 3, 6, 7, 8, 9, 11, 12, 16) up front. Add optional stages (4, 5, 10, 13, 14, 15) as you reach them and the user opts in — don't pre-create todos for stages that may not run.
- **Resume:** rebuild the list from `state.stages_completed` + `state.stages_skipped` (mark those `completed`) and the remaining pipeline. The harness's todo state may or may not persist across sessions; rebuild explicitly either way.

Update discipline:
- Mark the current stage's todo `in_progress` as you begin it
- Mark it `completed` the moment the stage advances (after `stages_completed` is updated)
- Never batch updates; the user is watching this list during the run

This is non-negotiable. A 17-stage pipeline is invisible to the user without it.

### When the State File Exists

Created in **Stage 2** (`writing-specs`). Stages 0-1 run before it exists; their outputs are held by the coordinator in-memory and persisted into the state file by `writing-specs`. An interruption between Stage 0 and Stage 2 has no state file — the "pre-state signals" routing handles it.

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
| 4 | `spec_second_review` | `spec_second_reviewed` |
| 5 | `spec_grill` | `spec_grilled` |
| 6 | `adr_maintenance` | `adrs_maintained` |
| 7 | `spec_approval` | `spec_approved` |
| 8 | `plan_writing` | `plan_written` |
| 9 | `plan_auto_review` | `plan_auto_reviewed` |
| 10 | `plan_second_review` | `plan_second_reviewed` |
| 11 | `plan_approval` | `plan_approved` |
| 12 | `implementing` | `implementation_complete` |
| 13 | `testing` | `testing_complete` |
| 14 | `handoff` | `handoff_generated` |
| 15 | `memory_file` | `memory_file_maintained` |
| 16 | `finishing` | `finished` |

When resuming, advance to the stage one beyond the last `stages_completed` entry. If the last completed stage exists in `stages_skipped` instead, advance to the next mandatory or asked-and-confirmed stage. State updates happen at stage boundaries only — never mid-stage. State file commits ride along with the relevant spec/plan/code commit (no standalone state-update commits).

## Per-Stage Driving Instructions

For every stage:

1. Update state: `current_stage: "<stage_name>"` (atomic write)
2. Run the stage (load skill, or dispatch subagent, per the pipeline table)
3. On success: add stage name to `stages_completed`, write state, commit if appropriate
4. Advance

If a stage fails (subagent returns Issues Found, validator fails, etc.): handle the loop per that stage's protocol. Do not advance until the stage is genuinely complete.

### Stage 0 — Preflight

Load `preflight-checks`. Pass it the `inspecting-state` report from Step 1. It validates `.sdd/config.yml` first (HALT-on-fail with reason `config_missing` or `config_invalid`), then runs all remaining pre-pipeline halt checks (dirty workspace, detached HEAD with state, protected/ambiguous branch), then handles branch creation and optional worktree. State file does NOT yet exist; hold preflight outcomes (branch, worktree path, original branch) in-memory for `writing-specs` to persist in Stage 2.

After preflight returns ready, the config is known-valid and you can use `scripts/get-config-value.sh <block> <key>` (exit 0 + value on stdout, or exit 2 if missing) for scalar lookups throughout the run. For lists / multi-line strings, parse YAML directly.

On any abort (`config_missing` / `config_invalid` / `dirty_working_tree` / `detached_head_with_state` / `protected_branch` / `ambiguous_branch` / `worktree_creation_failed` / `user_declined`): surface preflight's message verbatim and exit. Do not advance.

### Stage 1 — Discovering Requirements

Load `discovering-requirements`. Follow it. State file still doesn't exist; hold discovery outputs (short name, approved sections, ADR-candidate decisions) in-memory.

### Stage 2 — Writing the Spec

Load `writing-specs`. Pass it the in-memory preflight + discovery outputs — it initializes the state file.

**Validator enforcement:** `writing-specs` must return the validator's PASS line verbatim. Re-run yourself:

```bash
./spec-driven-development/scripts/validate-spec.sh docs/specs/NNN-<short-name>/spec.md
```

If the fresh run disagrees with the writer's report, halt and surface (writer drift or lie). After PASS, advance `current_stage` to `spec_auto_review`, append `spec_written`. Commit:

```
git add docs/specs/NNN-<short-name>/spec.md docs/specs/NNN-<short-name>/state.json
git commit -m "spec(NNN-short-name): initial draft"
```

### Stage 3 — Auto Spec-Review

Dispatch a `general-purpose` subagent. Prompt includes: `SPEC_PATH`, `CONTEXT_FILES` (constitution + ADRs + architecture + glossary paths that exist), `REVIEW_FOCUS: first-pass`, and "Use the `reviewing-specs` skill."

Process findings via `receiving-review-findings` (load it inline). It handles evaluate/fix/push-back/escalate, including the cap-2 fix-loop escalation protocol.

### Stage 4 — Optional 2nd Spec-Review (User-Gated)

Ask: "Spec auto-review passed. Want a second-pass review for extra rigor? (yes/no, default no)"

If no: add `spec_second_review` to `stages_skipped`. If yes: dispatch with `REVIEW_FOCUS: second-pass — focus on <user-specified topic or "independent angle">`. Process via `receiving-review-findings`.

### Stage 5 — Optional Grill (User-Gated)

Ask: "Want a grill session to stress-test the spec? (yes/no, default no)"

If yes: load `grilling-specs`. Follow it. Commit after:

```
git add docs/specs/NNN-<short-name>/spec.md
git commit -m "spec(NNN-short-name): grill session updates"
```

### Stage 6 — ADR Maintenance

Dispatch a `general-purpose` subagent. Prompt includes: `SPEC_PATH`, `ADR_DIR` (from config `paths.adr_dir` or default), `EXISTING_ADRS` (list), `DECISIONS_CAPTURED` (in-memory from discovery + grill), and "Use the `maintaining-adrs` skill."

If ADRs were created or superseded, commit them and record `adr_results` in state. Zero ADRs is a valid outcome.

```
git add docs/adr/<new files> [docs/adr/<modified superseded files>]
git commit -m "docs(adr): NNNN-NNNN from spec NNN-short-name"
```

### Stage 7 — User Spec Approval

Tell user:

> "Spec and ADRs ready:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list]
>
> One of:
> - **Approve** — flip ADRs Proposed → Accepted, proceed (default)
> - **Approve, keep ADRs as Proposed** — proceed but leave ADRs untouched
> - **Request changes** — what to change"

**On Approve:** edit each ADR's `Status: Proposed` → `Status: Accepted`, commit `docs/adr/*.md` + state.json. Advance.

**On Approve, keep ADRs as Proposed:** commit state.json only. Advance.

**On Request changes:** classify before applying.

| Change type | Examples | Handling |
|---|---|---|
| **Light-touch** | Typo, wording, tightening an FR, adding an edge case, ADR text adjustment | Apply inline via `receiving-review-findings` discipline. Re-validate. Re-ask for approval. |
| **Substantive — re-discovery** | Decomposition needed, fundamental requirement change, whole story added/removed | Do NOT edit inline. Reset `current_stage` to `discovering`; re-invoke `discovering-requirements`. |
| **Substantive — ADR overhaul** | An ADR needs replacing, new ADR-worthy decisions emerge | Re-dispatch `maintaining-adrs` after any spec changes. |

If unsure, default to light-touch; if it grows substantive mid-edit, stop and reclassify.

### Stage 8 — Writing the Plan

Load `writing-plans`. Follow it. Same validator-enforcement pattern as Stage 2 — re-run `validate-plan.sh`; halt on disagreement. Commit:

```
git add docs/specs/NNN-<short-name>/plan.md docs/specs/NNN-<short-name>/state.json
git commit -m "plan(NNN-short-name): initial draft"
```

### Stage 9 — Auto Plan-Review

Dispatch with: `PLAN_PATH`, `SPEC_PATH`, `CONTEXT_FILES`, `REVIEW_FOCUS: first-pass`, "Use the `reviewing-plans` skill." Process findings via `receiving-review-findings`.

### Stage 10 — Optional 2nd Plan-Review (User-Gated)

Same pattern as Stage 4.

### Stage 11 — User Plan Approval

Tell user: "Plan ready: docs/specs/NNN-<short-name>/plan.md. Approve to start implementation, or request changes." Wait for explicit approval.

### Stage 12 — Implementation

Load `implementing-plans`. It orchestrates the per-task loop (implementer + 2 reviewers, then final review). State's `tasks` map is initialized/synced and updated per task.

After all tasks complete and final review passes:

```
git add docs/specs/NNN-<short-name>/state.json
git commit -m "chore(NNN-short-name): mark implementation complete"
```

### Stage 13 — Optional Feature Testing (User-Gated)

Ask: "Implementation complete. Run feature-level tests now? (yes/no, default yes)"

If yes: load `testing-implementation`. It dispatches the tester subagent and handles the FAIL → fixer loop. **If the tester reports `MCP_UNAVAILABLE`, do NOT pick up Bash/Playwright/curl to test it yourself — surface the manual test plan to user.**

### Stage 14 — Generate Handoff (User-Gated)

Ask: "Generate a handoff document for this run? (yes/no, default yes — recommended when someone else may pick this up, or you'll iterate on it later in a fresh session)"

If no: add `handoff` to `stages_skipped`. Advance to Stage 15.

If yes, resolve `HANDOFF_DIR`: read `paths.handoff_dir` from config. If it starts with `/` or `~`, treat as absolute (expand `~`); set `OUTSIDE_REPO=true` if the resolved path falls outside `git rev-parse --show-toplevel`. Otherwise repo-relative, `OUTSIDE_REPO=false`.

Dispatch a `general-purpose` subagent with: `STATE_PATH`, `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `BRANCH`, `BASE_SHA` (`git merge-base HEAD <base>`), `HEAD_SHA`, `HANDOFF_DIR`, `OUTSIDE_REPO`, and "Use the `generating-handoff` skill."

After return: re-run `validate-handoff.sh <handoff-path>`. If FAIL — especially "potential unredacted secret" — halt; do NOT commit. Otherwise:

- **`OUTSIDE_REPO=false`:** commit `<handoff-path>` + state.json (`docs(NNN-short-name): handoff document`)
- **`OUTSIDE_REPO=true`:** commit state.json only (`chore(NNN-short-name): record external handoff path`); tell user where the external handoff was written.

Record `handoff_path` in state file.

### Stage 15 — Maintain Memory File (User-Gated)

Resolve `MEMORY_FILE_PATH` BEFORE asking:
1. `memory_file.path` in config — if set, use it (absolute or repo-relative; both OK)
2. Otherwise auto-detect by checking for these in order at repo root: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`. First match wins.
3. If neither config nor auto-detect finds a path: auto-skip (no memory file to maintain). Add `memory_file` to `stages_skipped`. Do NOT prompt — there's nothing to maintain.

If a path was resolved, ask: "Check memory file `<MEMORY_FILE_PATH>` for updates from this run? (yes/no, default yes — most runs result in 'no update needed', so this is cheap to say yes to)"

If no: add `memory_file` to `stages_skipped`. Advance to Stage 16.

If yes, resolve `CHARACTER_LIMIT` from `memory_file.character_limit` (default 40000).

Read `EXISTING_CONTENT` from `MEMORY_FILE_PATH` (empty string if file doesn't exist yet but a path is configured).

Dispatch a `general-purpose` subagent with: `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `MEMORY_FILE_PATH`, `CHARACTER_LIMIT`, `EXISTING_CONTENT`, and "Use the `maintaining-memory-file` skill."

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

### Stage 16 — Finishing

Load `finishing-sdd`. Follow it. After finishing: SDD run is done.

## Loading Skills

Use the Skill tool with the skill name. Example: `Skill(skill="writing-specs")`. If installed under a namespace (e.g., `spec-driven-development:writing-specs`), use the namespaced name. Load phase-skills only when their stage is active — don't pre-load.

## Subagent Dispatch

Use the Task / Agent tool with `subagent_type=general-purpose`. Always:

- Pass content inline (don't make subagents re-read large files unless necessary)
- Tell the subagent which skill to use (via Skill tool)
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
| Skipping the resume check at session start | Always read state file FIRST — non-negotiable |
| Updating state mid-stage | Updates happen at stage boundaries (atomic) |
| Letting state file get committed in its own noisy commits | Ride-along with relevant code/doc commits |
| Skipping user-approval gates | Mandatory; never auto-proceed |
| Auto-skipping an optional stage | Always ask user; never auto-skip or auto-include |
| Doing phase-skill work inline | Load the phase-skill or dispatch the subagent |
| Coordinator running feature tests when MCP_UNAVAILABLE | NEVER — surface to user with manual test plan |
| Silently picking one of multiple active state files | Always ask user which to resume |
| Auto-checking out a branch on resume | Never — instruct user to switch and re-invoke |

## Red Flags

- About to do work without reading state first → STOP; resume check is first
- About to advance past a user-approval gate without typed approval → STOP
- About to auto-skip an optional stage → STOP; user decides
- About to start two implementer subagents in parallel → STOP
- About to test the feature yourself after MCP_UNAVAILABLE → STOP; not your job
- About to `git checkout` to switch branches as part of resume → STOP; ask the user

## Sibling Skills

- `inspecting-state` — read-only state utility. Used as the first action on every invocation. Also user-invokable directly to check status without entering the pipeline.
- `bootstrapping-project` (in the `project-bootstrap` family) — one-time per-project bootstrap (constitution, conventions, config). User-invoked directly, not by this coordinator.
