# SDD State File Schema (Canonical)

**Location:** `docs/specs/<feature_id>/state.json`.

This is the **single source of truth** for the state file schema. The coordinator and any other skill that touches the state file MUST match this definition. Drift between this file and a skill's local schema is a bug; fix this file first, then the skill.

A machine-readable JSON Schema version lives alongside this file at `state-schema.json` for objective validation.

## Lifecycle in one paragraph

The state file is **created** by `writing-specs` at Stage 2 (it doesn't exist during Stages 0-1; preflight outcomes are held in coordinator memory). It is **updated** at every stage boundary by either the coordinator or the active phase skill (per the Field Ownership table below). Through Stages 2–11 it lives on disk **uncommitted**; the `choosing-feature-branch` skill at Stage 12 batch-commits it alongside the spec/plan/ADR artifacts on the chosen branch. From Stage 13 onward, updates are committed per stage by the active skill. It is **deleted** at Stage 17 by `finishing-sdd` (with a single `chore` commit).

## Required fields

These MUST be present in any valid state file (i.e., from Stage 2 onward):

| Field | Type | Description |
|---|---|---|
| `feature_id` | string | Format: `NNN-<short-name>`, e.g., `003-user-auth`. Sequential within the project. |
| `short_name` | string | Kebab-case, 2-4 words. Used in branch names, ADR refs, handoff filenames. |
| `work_type` | string | `"feature"` or `"fix"`. Captured at Stage 1 by `discovering-requirements`; used by `choosing-feature-branch` (Stage 12) to derive the suggested branch prefix. |
| `started_at` | string (ISO-8601 UTC) | When Stage 2 first initialized this state file. |
| `updated_at` | string (ISO-8601 UTC) | Last write timestamp. Updated on every atomic write. |
| `spec_path` | string | Repo-relative path to `spec.md`. Default: `docs/specs/<feature_id>/spec.md`. |
| `current_stage` | string | One of the enum values in the Stage Name Mapping table below. |
| `stages_completed` | array of strings | Stages finished successfully, in chronological order. Each value from the Stage Name Mapping table's "stages_completed entry" column. |
| `stages_skipped` | array of strings | Stages user opted to skip (only the four optional stages can appear here). |
| `tasks` | object | `{ "T###": "pending" | "in_progress" | "completed" }`. Empty `{}` before Stage 13 initializes it. |

## Optional fields (present after specific stages advance)

| Field | Type | Present after | Description |
|---|---|---|---|
| `plan_path` | string | Stage 8 | Repo-relative path to `plan.md`. |
| `adr_results` | array of objects | Stage 6 | `[{ "id": "ADR-NNNN", "title": string, "status": "Proposed"|"Accepted"|..., "path": string }, ...]`. Empty array if no ADRs created. |
| `test_status` | string | Stage 13 | One of: `passed`, `passed_after_fixes`, `skipped_mcp_unavailable`, `skipped_user_choice`, `failed_escalated`, or `null` if Stage 13 hasn't run. |
| `fix_iterations` | integer | Stage 13 | How many test-fix iterations ran (0-3). |
| `final_review_completed` | boolean | After Stage 13 final review | Set `true` by `implementing-plans` when the cross-cutting final code-quality review passes. |
| `handoff_path` | string | Stage 15 | Absolute path to the generated handoff doc, located under `$HOME/.sublime-skills/handoffs/<repo-basename>/`. |
| `memory_file_updated` | boolean | Stage 15 | `true` if the memory file was updated this run; `false` if no update was needed or the stage was skipped. |
| `memory_file_path` | string | Stage 15 (only if updated) | Path to the memory file that was updated. May be repo-relative or absolute. |
| `reviewer_pushbacks` | array of objects | Any stage where the coordinator pushed back | `[{ "stage": string, "finding": string, "reason": string }, ...]`. Empty array `[]` is the initial value. |
| `spec_auto_review_iterations` | integer | Stage 3 (and 5 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |
| `plan_auto_review_iterations` | integer | Stage 9 (and 10 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |

## Field Ownership (who writes what)

Each field is owned by exactly one skill or the coordinator. Multiple writers = bugs.

| Field | Owner | Notes |
|---|---|---|
| `feature_id`, `short_name`, `started_at`, `spec_path` | `writing-specs` (Stage 2 init) | Set once at Stage 2; never updated after. |
| `work_type` | `discovering-requirements` (Stage 1; captured in-memory) + persisted by `writing-specs` (Stage 2 init) | Set once; never updated after. |
| `updated_at` | Every writer | Touched on each atomic write. |
| `current_stage` | Coordinator | Advanced at every stage boundary. |
| `stages_completed` | Coordinator | Appended to after each stage succeeds. |
| `stages_skipped` | Coordinator | Appended when user declines an optional stage. |
| `tasks` (init) | `implementing-plans` Step 2 | Merge with existing on resume; never overwrite completed tasks. |
| `tasks` (per-task transitions) | `implementing-plans` Step 3 | `pending` → `in_progress` at task start; `in_progress` → `completed` at task finish. |
| `plan_path` | `writing-plans` (Stage 8 init) | Set once. |
| `adr_results` | Coordinator | Populated from `maintaining-adrs`' return value at Stage 6. |
| `test_status`, `fix_iterations` | `testing-implementation` | Written when Stage 13 completes. |
| `final_review_completed` | `implementing-plans` | Set to `true` after Stage 13's final review approves. |
| `handoff_path` | Coordinator | Set after Stage 15 from the `generating-handoff` subagent's report. |
| `memory_file_updated`, `memory_file_path` | Coordinator | Set after Stage 15 from the `maintaining-memory-file` subagent's report. |
| `reviewer_pushbacks` | `receiving-review-findings` | Appended whenever the coordinator pushes back instead of fixing. |
| `spec_auto_review_iterations`, `plan_auto_review_iterations` | `receiving-review-findings` | Incremented per fix-loop iteration. |

## Stage Name Mapping

| Stage # | `current_stage` value | `stages_completed` entry | `stages_skipped` entry (if applicable) |
|---|---|---|---|
| 0 | `preflight` | `preflight` | — |
| 1 | `discovering` | `discovering` | — |
| 2 | `spec_writing` | `spec_written` | — |
| 3 | `spec_auto_review` | `spec_auto_reviewed` | — |
| 4 | `spec_grill` | `spec_grilled` | `spec_grill` |
| 5 | `spec_second_review` | `spec_second_reviewed` | `spec_second_review` |
| 6 | `adr_maintenance` | `adrs_maintained` | — |
| 7 | `spec_approval` | `spec_approved` | — |
| 8 | `plan_writing` | `plan_written` | — |
| 9 | `plan_auto_review` | `plan_auto_reviewed` | — |
| 10 | `plan_second_review` | `plan_second_reviewed` | `plan_second_review` |
| 11 | `plan_approval` | `plan_approved` | — |
| 12 | `choosing_branch` | `branch_chosen` | — |
| 13 | `implementing` | `implementation_complete` | — |
| 14 | `testing` | `testing_complete` | `testing` |
| 15 | `handoff` | `handoff_generated` | `handoff` |
| 16 | `memory_file` | `memory_file_maintained` | `memory_file` |
| 17 | `finishing` | `finished` | — |

## Atomic write pattern (required)

Every state write follows:

```bash
# Compose the new state JSON
... > state.json.tmp
mv state.json.tmp state.json
```

Atomicity matters: a half-written `state.json` is unrecoverable. The `mv` is atomic on POSIX filesystems (within the same filesystem); the `.tmp` file ensures partial writes never replace the previous state.

## Reference example (mid-implementation, resume case)

This is a typical state during Stage 13 with 3 tasks done, 1 in progress, 3 pending:

```json
{
  "feature_id": "003-user-auth",
  "short_name": "user-auth",
  "work_type": "feature",
  "started_at": "2026-05-20T14:32:00Z",
  "updated_at": "2026-05-20T16:45:00Z",
  "spec_path": "docs/specs/003-user-auth/spec.md",
  "plan_path": "docs/specs/003-user-auth/plan.md",
  "current_stage": "implementing",
  "stages_completed": [
    "preflight", "discovering", "spec_written",
    "spec_auto_reviewed", "adrs_maintained", "spec_approved",
    "plan_written", "plan_auto_reviewed", "plan_approved",
    "branch_chosen"
  ],
  "stages_skipped": ["spec_grill", "spec_second_review", "plan_second_review"],
  "adr_results": [
    {
      "id": "ADR-0003",
      "title": "Use JWT for session tokens",
      "status": "Accepted",
      "path": "docs/adr/0003-use-jwt-for-sessions.md"
    }
  ],
  "tasks": {
    "T001": "completed",
    "T002": "completed",
    "T003": "completed",
    "T004": "in_progress",
    "T005": "pending",
    "T006": "pending",
    "T007": "pending"
  },
  "test_status": null,
  "fix_iterations": 0,
  "final_review_completed": false,
  "handoff_path": null,
  "reviewer_pushbacks": [],
  "spec_auto_review_iterations": 1,
  "plan_auto_review_iterations": 1
}
```

## Validation

This schema is the contract. A consumer that wants to verify a state file should check:
- JSON parses
- All required fields present
- Enum values valid (`current_stage` from the Stage Name Mapping; `tasks.T###` in `pending|in_progress|completed`; `test_status` from the documented set)
- Stage progression is consistent (e.g., `current_stage: implementing` implies `plan_approved` is in `stages_completed`)

For machine-readable validation, see `state-schema.json` (JSON Schema Draft 2020-12).
