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

- ALWAYS read the state file first on every invocation, before doing anything else
- Do NOT skip mandatory stages (preflight, discovering, writing-specs, auto spec-review, ADR maintenance, user spec approval, writing-plans, auto plan-review, user plan approval, implementation, finishing)
- Optional stages (2nd spec-review, grill, 2nd plan-review, feature testing) are user-gated — always ask, default no
- Do NOT do work that belongs to phase-skills inline. If a stage has a phase-skill, load it and follow it.
- Do NOT attempt to test the feature yourself, even if `testing-implementation` reports MCP_UNAVAILABLE. Surface to user.
- Do NOT proceed past a user-approval gate without explicit approval

## The Pipeline

| # | Stage | Mechanism | Optional? |
|---|---|---|---|
| 0 | Preflight | Inline via `preflight-checks` | No |
| 1 | Discovering requirements | Inline via `discovering-requirements` | No |
| 2 | Writing the spec | Inline via `writing-specs` | No |
| 3 | Auto spec-review | Subagent uses `reviewing-specs`; findings processed via `receiving-review-findings` | No |
| 4 | Optional 2nd spec-review | Subagent uses `reviewing-specs`; findings processed via `receiving-review-findings` | **Yes — ask user** |
| 5 | Optional grill | Inline via `grilling-specs` | **Yes — ask user** |
| 6 | ADR maintenance | Subagent uses `maintaining-adrs` | No |
| 7 | User spec approval + commit | Inline | No |
| 8 | Writing the plan | Inline via `writing-plans` | No |
| 9 | Auto plan-review | Subagent uses `reviewing-plans`; findings processed via `receiving-review-findings` | No |
| 10 | Optional 2nd plan-review | Subagent uses `reviewing-plans`; findings processed via `receiving-review-findings` | **Yes — ask user** |
| 11 | User plan approval + commit | Inline | No |
| 12 | Implementation | Inline via `implementing-plans` (dispatches per-task subagents) | No |
| 13 | Optional feature testing | Inline via `testing-implementation` (dispatches tester subagent) | **Yes — ask user** |
| 14 | Generate handoff | Subagent uses `generating-handoff` | Default yes; skippable via `.sdd/config.yml` → `handoff.enabled: false` |
| 15 | Finishing + cleanup | Inline via `finishing-sdd` | No |

## On Every Invocation: Resume Check (BEFORE anything else)

This is the very first thing to do, every time the coordinator is invoked. Skipping it is the worst failure mode this skill has.

### Step 1: Run the inspecting-state Skill

Load `inspecting-state` via the Skill tool and let it produce the report. **You do not perform state detection inline** — `inspecting-state` is the single source of truth for "what state exists right now". It runs `scripts/discover-context.sh`, reads every active state file, validates schemas, and reports pre-state-file interruption signals.

### Step 2: Load Config

Read `.sdd/config.yml` if present. Cache the values for later stages (paths, preflight options, grill cap, handoff toggle, finishing mode and test command, etc.).

**For scalar config values**, prefer the helper:

```bash
./spec-driven-development/scripts/get-config-value.sh <block> <key>
```

Returns the value on stdout (exit 0), or exit 2 if the config file is missing or the key isn't set. Examples:
- `get-config-value.sh handoff enabled` → returns `"true"` / `"false"` / empty
- `get-config-value.sh paths handoff_dir` → returns the path
- `get-config-value.sh finishing mode` → returns `prompt|leave|merge-local|pr|auto`

For non-scalar values (lists like `context.constitution_paths`, multi-line strings like `pr_body_template`), parse `.sdd/config.yml` directly. See `scripts/README.md` for the helper's limits.

### Step 3: Decide Based on the Report

The report includes both the active state files AND the current branch. Routing depends on both: a state file alone is not enough — the current branch determines whether resuming that state is the right next action.

| inspecting-state report says | Coordinator action |
|---|---|
| 0 active runs + no pre-state signals + on default branch | Fresh start. Confirm with user: "No active SDD run found. Start a new feature?" |
| 0 active runs + pre-state signals (non-default branch) | Preflight likely ran but spec was never written. Ask user: "Looks like preflight ran on `<branch>` but discovery wasn't completed. Options: (1) resume from Stage 1; (2) start fresh; (3) abandon (you'll clean up)." Respect user's choice; never silently pick. |
| 1 active run, **current branch matches the run's `state.branch`** | Confirm with user: "Resuming SDD run for `<feature_id>` at stage `<current_stage>`. Resume? (yes/no)". If no, ask what they want instead. |
| 1 active run, **current branch does NOT match the run's `state.branch`** | **DO NOT silently resume.** Ask user: "Active SDD run found for `<feature_id>` on branch `<state.branch>`, but you're currently on `<current_branch>`. Options: (1) Switch to `<state.branch>` and resume that run; (2) Start a new feature on `<current_branch>` (the existing run's state file stays put for later); (3) Abort — clarify what you intended." Never auto-switch branches; never auto-resume across branches. |
| 2+ active runs, **current branch matches exactly one** | Tell user: "Found N active runs. Your current branch `<current_branch>` matches `<feature_id>`. Resume that one, or pick a different one? (resume/pick/fresh-on-this-branch)". |
| 2+ active runs, **current branch matches none** | List them with their branches. Ask: "Which to resume, or start fresh on `<current_branch>`?" Never silently pick. |
| Malformed state file | Show the user what's wrong (from the report). Offer: (a) attempt repair (ask user for guidance), (b) discard state and start fresh, (c) abort. Never silently overwrite. |

**Rules that apply across all routing:**

- The coordinator NEVER runs `git checkout` to switch branches on its own. If the user picks "switch and resume," the coordinator instructs the user to switch and re-invoke, OR (with explicit user consent in this session) runs the checkout. Default is "instruct user."
- "Match" means exact string equality between `git branch --show-current` output and the state file's `branch` field.
- If `current_branch` is empty (detached HEAD) and any active state exists: ABORT — detached HEAD is too ambiguous to route from.

### When Does the State File Exist?

The state file is **created in Stage 2** (`writing-specs`), once the spec directory is set up. Preflight (Stage 0) and discovering-requirements (Stage 1) run BEFORE the state file exists:

- Stage 0 outputs (branch, worktree path, original branch) are held by the coordinator in-memory
- Stage 1 outputs (short name, decisions, approved sections) are held in-memory
- Stage 2 (`writing-specs`) initializes the state file with all of the above

This means an interruption between Stage 0 and Stage 2 has NO state file — the "non-default branch + no state" resume case above handles this.

### State File Schema

Path: `<spec_dir>/<feature_id>/state.json` (default `<spec_dir>` is `docs/specs`; honors `paths.spec_dir` config override).

**The canonical schema lives at `spec-driven-development/scripts/state-schema.md`** (human-readable) and `state-schema.json` (machine-readable JSON Schema Draft 2020-12). Both define the complete field set, types, enums, ownership, and stage-name mapping. **This skill must match that schema; if they disagree, the canonical wins and this section needs updating.**

Quick reference (full details in the canonical):

- **Required fields:** `feature_id`, `short_name`, `started_at`, `updated_at`, `branch`, `spec_path`, `current_stage`, `stages_completed`, `stages_skipped`, `preflight`, `tasks`
- **Optional fields (present after specific stages):** `plan_path`, `adr_results`, `test_status`, `fix_iterations`, `final_review_completed`, `handoff_path`, `reviewer_pushbacks`, `spec_auto_review_iterations`, `plan_auto_review_iterations`

**Field ownership (summary):**

- Coordinator owns: `current_stage`, `stages_completed`, `stages_skipped`, `updated_at`, `adr_results`, `handoff_path`
- `writing-specs` owns: `feature_id`, `short_name`, `started_at`, `branch`, `spec_path`, `preflight.*` (init only)
- `writing-plans` owns: `plan_path` (init only)
- `implementing-plans` owns: `tasks` map transitions, `final_review_completed`
- `testing-implementation` owns: `test_status`, `fix_iterations`
- `receiving-review-findings` owns: `reviewer_pushbacks`, `spec_auto_review_iterations`, `plan_auto_review_iterations`

**Atomic update pattern:** write to `state.json.tmp`, then `mv state.json.tmp state.json`. State updates happen **at stage boundaries** — never mid-stage. State file gets committed alongside relevant spec/plan/code commits (no standalone "update state" commits).

### Stage Name Mapping (summary)

See `scripts/state-schema.md` for the full table with `stages_skipped` entries. Quick reference:

| Stage # | `current_stage` value | `stages_completed` entry |
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
| 15 | `finishing` | `finished` |

When resuming, set `current_stage` to the stage that needs to run next (i.e., one beyond `stages_completed`'s last entry). If the last completed stage exists in `stages_skipped` rather than `stages_completed`, advance to the next mandatory or asked-and-confirmed stage.

## Per-Stage Driving Instructions

For every stage:

1. Update state: `current_stage: "<stage_name>"` (atomic write)
2. Run the stage (load skill, or dispatch subagent, per the pipeline table)
3. On success: add the stage name to `stages_completed`, write state, commit if appropriate
4. Advance to next stage

If a stage fails (e.g., a subagent returns "Issues Found"): handle the loop per that stage's protocol. Do not advance until the stage is genuinely complete.

### Stage 0 — Preflight

Load `preflight-checks`. Follow it.

**State file does NOT exist yet.** Preflight runs against a working branch name that may be temporary. Track preflight outcomes (branch, worktree path, original branch) in a temporary in-memory dict. The state file is initialized in Stage 2 (`writing-specs`) using these in-memory values.

`preflight` is NOT added to `stages_completed` here (no state file). It's added by `writing-specs` when the file is initialized.

### Stage 1 — Discovering Requirements

Load `discovering-requirements`. Follow it.

**State file still does NOT exist.** Track the discovery outputs (short name, approved sections, decisions captured as ADR candidates) in-memory. They're persisted into the state file in Stage 2.

On success: in-memory shared understanding ready for spec writing.

### Stage 2 — Writing the Spec

Load `writing-specs`. Pass it the in-memory preflight outcomes and discovery outputs — it initializes the state file (`docs/specs/NNN-<short-name>/state.json`) with these.

**Verify the validator passed before committing.** `writing-specs` is required to include the validator's PASS line in its report. Re-run the validator yourself as a check:

```bash
./spec-driven-development/scripts/validate-spec.sh docs/specs/NNN-<short-name>/spec.md
```

- If the fresh run also returns PASS (exit code 0): proceed to commit
- If the fresh run returns FAIL (exit code 1) but the writer's report claimed PASS: **the writer lied or the spec drifted.** Halt the stage; show the user the validator output; ask whether to re-run writing-specs or abort.
- If the writer's report did NOT include a PASS line: halt the stage; the writer claims it skipped validation. Surface the writer's full report to the user.

After validation passes, update the state file: set `current_stage` to `"spec_auto_review"` and append `"spec_written"` to `stages_completed`.

Commit spec.md + state.json:

```
git add docs/specs/NNN-<short-name>/spec.md docs/specs/NNN-<short-name>/state.json
git commit -m "spec(NNN-short-name): initial draft"
```

### Stage 3 — Auto Spec-Review

Dispatch a `general-purpose` subagent with this prompt:

```
You are reviewing a spec for the SDD pipeline.

Use the `reviewing-specs` skill (via the Skill tool) to perform the review.

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
CONTEXT_FILES:
  - <list constitution path if exists>
  - <list ADR paths>
  - <list architecture/glossary/etc paths>
REVIEW_FOCUS: first-pass

Return your findings report.
```

Process the findings via `receiving-review-findings` (load it inline). That skill tells you how to evaluate, fix, push back, or escalate. Cap at 2 fix iterations before escalating to user.

When the stage settles to Approved (or all findings resolved per `receiving-review-findings`'s protocol): advance to Stage 4 query.

### Stage 4 — Optional 2nd Spec-Review (User-Gated)

Ask the user:

> "Spec auto-review passed. Want a second-pass review for extra rigor? (yes/no, default no)"

If no: add `spec_second_review` to `stages_skipped`, advance to Stage 5 query.

If yes: dispatch a fresh `reviewing-specs` subagent with `REVIEW_FOCUS: second-pass — focus on <user-specified focus, e.g., security implications>` (if user gave a focus) or `second-pass — independent angle`. Process findings via `receiving-review-findings`, same as Stage 3.

### Stage 5 — Optional Grill (User-Gated)

Ask the user:

> "Want a grill session to stress-test the spec? It'll ask scoped questions and update the spec inline. (yes/no, default no)"

If no: add `spec_grill` to `stages_skipped`, advance to Stage 6.

If yes: load `grilling-specs`. Follow it. After the grill, commit the changes:

```
git add docs/specs/NNN-<short-name>/spec.md
git commit -m "spec(NNN-short-name): grill session updates"
```

### Stage 6 — ADR Maintenance

Dispatch a `general-purpose` subagent:

```
You are maintaining ADRs for the SDD pipeline.

Use the `maintaining-adrs` skill (via the Skill tool).

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
ADR_DIR: docs/adr (or config override)
EXISTING_ADRS:
  - <list>
DECISIONS_CAPTURED:
  - <list from in-memory record of major decisions from discovery + grill>

Return the result.
```

Handle:
- ADRs created → commit them:
  ```
  git add docs/adr/<new files> [docs/adr/<modified superseded files>]
  git commit -m "docs(adr): NNN-NNNN from spec NNN-short-name"
  ```
- Record ADR results in state file under `adr_results`
- 0 ADRs created → note in state file, no commit, advance

### Stage 7 — User Spec Approval

Tell the user:

> "Spec and ADRs are ready for your review:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list with paths]
>
> Please read them and let me know one of:
> - **Approve** — I'll flip ADRs from Proposed to Accepted and proceed to plan-writing (this is the default for spec approval)
> - **Approve, keep ADRs as Proposed** — proceed to plan-writing but leave ADR statuses untouched (use this when ADRs need more deliberation but the spec is fine)
> - **Request changes** — tell me what to change (spec text, ADR text, or both)"

Wait for explicit approval. Three response paths:

**On "Approve":**
1. For each ADR in the run's `adr_results`: edit its file's status line from `Status: Proposed` to `Status: Accepted`
2. Commit:
   ```
   git add docs/adr/*.md docs/specs/NNN-<short-name>/state.json
   git commit -m "spec(NNN-short-name): approve + accept ADRs"
   ```
3. Advance to Stage 8

**On "Approve, keep ADRs as Proposed":**
1. Do NOT edit ADR files
2. Commit only the state.json (advancing `current_stage`):
   ```
   git add docs/specs/NNN-<short-name>/state.json
   git commit -m "spec(NNN-short-name): approve (ADRs kept as Proposed)"
   ```
3. Advance to Stage 8

**On "Request changes":**

Classify the change before applying. Ask the user (if not already clear) which kind:

| Change type | Examples | Handling |
|---|---|---|
| **Light-touch edit** | Typo, wording, tightening a vague FR, adding a missing edge case, ADR text adjustment, splitting a story's acceptance scenarios, adjusting an SC's threshold | Apply inline. Use the `receiving-review-findings` discipline — verify against context first, then edit. Re-run `validate-spec.sh` if spec was touched. Commit the changes. Re-ask for approval. |
| **Substantive — re-discovery needed** | Spec needs decomposition into multiple features; fundamental requirement change; whole user story added or removed; goal/users/scope substantially redefined; constitution conflict the user wants to revisit | Do NOT edit inline. Confirm with user: "This needs to go back to discovery. I'll keep the spec file (and any ADRs) for reference, reset `current_stage` to `discovering`, and re-enter Stage 1. Proceed?" On yes: update state file (`current_stage: "discovering"`, append `"spec_approval_returned"` to a new `notes` field if useful), re-invoke `discovering-requirements`. The new discovery may produce a revised spec that supersedes the current one. |
| **Substantive — ADR overhaul** | An ADR needs to be replaced (not just edited), or new ADR-worthy decisions emerge that weren't captured | Re-dispatch `maintaining-adrs` after applying any necessary spec changes. The subagent handles supersession of old ADRs and writing new ones. Re-ask for approval. |

If the user is unsure which category, default to "light-touch" and apply inline. If during inline editing it becomes clear the change is substantive, stop and reclassify — don't try to force a substantive change through inline edits.

**Why the routing matters:** light-touch changes don't need a fresh review; substantive changes need to go back through earlier stages or the artifact becomes inconsistent.

The default approval option flips ADRs because leaving them indefinitely `Proposed` after a shipped feature is the more confusing outcome — users typically forget and ship with stale statuses.

### Stage 8 — Writing the Plan

Load `writing-plans`. Follow it.

**Verify the validator passed before committing.** Same enforcement pattern as Stage 2 — `writing-plans` must include the validator's PASS line in its report. Re-run yourself:

```bash
./spec-driven-development/scripts/validate-plan.sh docs/specs/NNN-<short-name>/plan.md
```

If fresh run disagrees with the writer's reported result, halt and surface.

After validation passes, commit plan.md + state.json:

```
git add docs/specs/NNN-<short-name>/plan.md docs/specs/NNN-<short-name>/state.json
git commit -m "plan(NNN-short-name): initial draft"
```

### Stage 9 — Auto Plan-Review

Dispatch a `general-purpose` subagent:

```
You are reviewing a plan for the SDD pipeline.

Use the `reviewing-plans` skill (via the Skill tool).

PLAN_PATH: docs/specs/NNN-<short-name>/plan.md
SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
CONTEXT_FILES: [list]
REVIEW_FOCUS: first-pass

Return findings.
```

Process findings via `receiving-review-findings`, same protocol as Stage 3 (cap 2 fix iterations).

### Stage 10 — Optional 2nd Plan-Review (User-Gated)

Same pattern as Stage 4. Process findings via `receiving-review-findings`.

### Stage 11 — User Plan Approval

Tell user:

> "Plan ready for review: docs/specs/NNN-<short-name>/plan.md
> Approve to start implementation, or request changes."

Wait for explicit approval.

### Stage 12 — Implementation

Load `implementing-plans`. Follow it. State file's `tasks` map is initialized and updated throughout.

After all tasks complete and final review passes, commit state updates:

```
git add docs/specs/NNN-<short-name>/state.json
git commit -m "chore(NNN-short-name): mark implementation complete"
```

(Per-task commits already happened inside the loop.)

### Stage 13 — Optional Feature Testing (User-Gated)

Ask:

> "Implementation complete. Run feature-level tests now? (yes/no, default yes — recommended for any feature with observable behavior)"

If no: add `testing` to `stages_skipped`. Advance to Stage 14.

If yes: load `testing-implementation`. Follow it. Handle the result protocols described in that skill — including the **critical rule that the coordinator does not test on its own** if `MCP_UNAVAILABLE`.

### Stage 14 — Generate Handoff

Check config: `.sdd/config.yml` → `handoff.enabled`. Default is `true`. If false, add `handoff` to `stages_skipped` and advance to Stage 15.

Otherwise, resolve `HANDOFF_DIR`:

- Default: `docs/handoff` (relative to repo root)
- Override: `.sdd/config.yml → paths.handoff_dir`
- If the override starts with `/` or `~`, treat it as an absolute path (expand `~` to `$HOME`) and set `OUTSIDE_REPO=true`. Otherwise treat as repo-relative and set `OUTSIDE_REPO=false`.
- Sanity check: after expansion, if the resolved path is NOT under `git rev-parse --show-toplevel`, set `OUTSIDE_REPO=true`.

Dispatch a `general-purpose` subagent:

```
You are generating the handoff document for the SDD pipeline.

Use the `generating-handoff` skill (via the Skill tool).

STATE_PATH: docs/specs/NNN-<short-name>/state.json
SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
PLAN_PATH: docs/specs/NNN-<short-name>/plan.md
ADR_PATHS:
  - <list ADR paths created or modified in this run, from state.adr_results>
BRANCH: <branch name>
BASE_SHA: <first commit on this branch — git merge-base HEAD <base-branch>>
HEAD_SHA: <current HEAD — git rev-parse HEAD>
HANDOFF_DIR: <resolved path — repo-relative or absolute>
OUTSIDE_REPO: <true | false>

Return the path to the generated handoff and a report.
```

**Verify the validator passed before committing.** The `generating-handoff` subagent's report includes a "Validation: passed" line. Re-run yourself against the now-final file to confirm:

```bash
./spec-driven-development/scripts/validate-handoff.sh <handoff-path>
```

If FAIL (especially "potential unredacted secret matching pattern"): halt and surface to the user immediately. Do NOT commit a handoff that may contain secrets. Offer to re-dispatch the handoff subagent or have the user inspect manually.

After validation passes:

**If `OUTSIDE_REPO=false`:**

```bash
git add <handoff-path> docs/specs/NNN-<short-name>/state.json
git commit -m "docs(NNN-short-name): handoff document"
```

**If `OUTSIDE_REPO=true`:** the handoff file is outside the repo and is NOT staged. Only the state file gets a commit:

```bash
git add docs/specs/NNN-<short-name>/state.json
git commit -m "chore(NNN-short-name): record external handoff path"
```

Inform the user where the external handoff was written: `Handoff written to <absolute-path> (outside repo — not committed).`

Record the handoff path in state file (always — absolute or relative):

```json
{ "handoff_path": "<path>" }
```

### Stage 15 — Finishing

Load `finishing-sdd`. Follow it.

After finishing: SDD run is done.

## Loading Skills

Use the Skill tool with the skill name. Example: `Skill(skill="writing-specs")`. If the skills are installed under a namespace (e.g., `spec-driven-development:writing-specs`), use the namespaced name.

Phase-skills should be loaded only when their stage is active. Don't pre-load. The coordinator stays slim.

## Subagent Dispatch

Use the Task / Agent tool with `subagent_type=general-purpose`. The prompt for each dispatch is described per stage above. Always:

- Pass full content inline (file paths + relevant text), don't make subagents re-read files unless necessary
- Tell the subagent which skill to use (via Skill tool)
- Specify the return format expected
- Never run multiple implementation subagents in parallel (use sequential)

## Subagent Failure Protocol

Subagent dispatches can fail in ways the dispatch contract doesn't cover — the subagent times out, crashes, returns malformed output, or returns nothing. Every stage that dispatches a subagent (Stages 3, 4, 6, 9, 10, 12 per task, 13, 14) must handle these.

### Failure modes and handling

| Failure | Detection | Handling |
|---|---|---|
| Subagent timed out (harness-dependent) | The dispatch returns a timeout error or an empty result | Retry once with the same prompt. If it times out twice, surface to user with the prompt and any partial output. Do NOT keep retrying. |
| Subagent crashed / errored | Dispatch returns a non-result error (platform error, model error, transport failure) | Read the error. If transient (rate limit, network), retry once after a brief pause. If structural (prompt too long, invalid tool use), fix the dispatch and retry. If unclear, surface to user. |
| Subagent returned malformed output | Result doesn't match the expected format (e.g., reviewer didn't return "Approved | Issues Found") | Re-dispatch ONCE with a brief reminder of the expected format appended. If the second attempt is also malformed, surface to user with both outputs. |
| Subagent returned empty/whitespace | Length of result < 10 chars or contains no structural markers | Same as malformed — re-dispatch once, then surface. |
| Subagent claimed completion but skipped required work | Result missing required fields (e.g., reviewer omitted Status line; tester omitted Tools used; implementer omitted commits) | Re-dispatch ONCE with the missing-fields callout. Then surface. |

### Hard rules

- **Maximum one retry per failure mode per dispatch point.** No retry loops.
- **Never silently move on from a failed subagent.** A failed dispatch is a stage failure; halt and surface to user.
- **Never substitute the coordinator's own work for the failed subagent's work.** If the spec reviewer subagent crashed, don't review the spec yourself — that's the whole point of dispatching it.
- **Never run two retry attempts in parallel.** Sequential only.

### What to surface to the user

```
Subagent failure at <stage> (<role>): <one-line summary of the failure>.

Attempted: <what was tried and how many retries>.
Last output (if any): <truncated to 500 chars>.

Options:
1. Retry the dispatch manually (I'll re-issue with the same prompt)
2. Skip the dispatch and proceed (only for non-mandatory stages; review/test/handoff if you accept the risk)
3. Abort the SDD run (state file kept; investigate later)
4. Provide the result manually (you paste in what should have been returned; I'll use it as the dispatch result)
```

Default is option 1. Never auto-pick.

## Commit Failure Protocol

Every stage that ends with a commit (Stages 2, 5, 6, 7, 8, 12, 14, 15, plus per-task implementer commits) must handle commit failures. The pipeline has multiple commit points; assuming success leaks bugs.

### Detect

After every `git commit`, check the exit code. If non-zero, capture the stdout/stderr — it tells you what failed.

### Common failure modes and handling

| Failure | Detection | Handling |
|---|---|---|
| Pre-commit hook rejected the commit (lint/format/test) | Hook output in stderr, exit code 1 | Read the hook output. If the hook auto-modified files (e.g., formatter), re-stage and re-commit ONCE. If the hook flagged real issues (lint errors, failing tests), do NOT bypass — fix the underlying issue if it's in scope for the current stage; otherwise halt and surface to user. **Never use `--no-verify`.** |
| Missing `user.name` or `user.email` | Error: "Please tell me who you are" | Halt. Surface to user: "Git identity is not configured. Please run `git config user.name '...'` and `git config user.email '...'`, then re-invoke." Do NOT attempt to set these yourself. |
| GPG signing failure | "gpg failed to sign the data" | Halt. Surface to user with the gpg error. Do NOT bypass with `--no-gpg-sign`. |
| Nothing to commit | "nothing to commit, working tree clean" | Unexpected at a commit point — likely indicates the prior `git add` matched nothing, OR the change was already committed. Investigate: run `git status` and `git log -1`. If the intended files are already in the most recent commit, treat as success and move on. Otherwise halt and report. |
| File not found in `git add` | "pathspec '...' did not match any files" | Investigate: the writer skill may have failed silently. Verify the expected file exists at the expected path. If missing, the previous stage didn't complete properly — halt and re-run that stage. |
| Merge conflict (finishing stage only) | Conflict markers in files; `git status` shows `UU` | Halt the merge. Tell user the merge conflicted on `<files>`. Do NOT attempt to auto-resolve. |

### What never to do

- **Never use `--no-verify`.** If hooks fail, the hook is telling you something. Fix the underlying issue or halt.
- **Never use `--no-gpg-sign`.** If signing is required by repo policy, bypassing it ships unsigned commits.
- **Never use `--force` on push.** If the remote rejects, investigate.
- **Never silently retry the same commit multiple times** hoping it works. Read the error; act on it; retry at most once (only when the cause is clear and the fix is automatic, like formatter auto-fixes).
- **Never amend a published commit** to "fix" a hook failure. Create a new commit.

### When subagent commits fail (implementer / fixer)

Subagents that commit (the implementer subagent, the fixer subagent) follow the same rules. On commit failure, they report status `BLOCKED` to the controller with the commit error output. The controller (the `implementing-plans` or `testing-implementation` skill) decides next action — typically surface to user, since hook failures are usually environment issues the controller can't fix.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the resume check at session start | Always read state file FIRST — non-negotiable |
| Updating state mid-stage | Updates happen at stage boundaries (atomic) |
| Letting state file get committed in its own noisy commits | Ride-along with relevant code/doc commits |
| Bundling multiple stages without state updates | State must be current after each stage |
| Skipping user-approval gates | Mandatory; never auto-proceed past approval stages |
| Letting an optional stage decide itself | Always ask user; never auto-skip or auto-include |
| Doing phase-skill work inline in the coordinator | Load the phase-skill or dispatch the subagent |
| Coordinator running feature tests itself when MCP_UNAVAILABLE | NEVER — surface to user with manual test plan |
| Multiple active state files but coordinator silently picks one | Always ask user which to resume |

## Red Flags

- About to do work without reading state first → STOP; resume check is first
- About to advance past a user-approval gate without typed approval → STOP
- About to auto-skip an optional stage → STOP; user decides
- About to start two implementer subagents in parallel → STOP; sequential
- About to pick up Bash/Playwright/curl to test the feature when MCP_UNAVAILABLE was reported → STOP; that's not the coordinator's job
- About to do "just one more check" between tasks during implementation → STOP; continuous execution is the rule

## Sibling Skills

- `inspecting-state` — read-only state inspection utility. Used by this coordinator as its first action on every invocation. Also directly invokable by the user to check status without entering the pipeline.
- `initializing-project-context` — one-time per-project bootstrap (constitution, conventions, config). Invoked by user directly, not by this coordinator.
