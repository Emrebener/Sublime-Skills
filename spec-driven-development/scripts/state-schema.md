# SDD State File Schema (Canonical)

**Location:** `<spec_dir>/<feature_id>/state.json` (default `<spec_dir>` is `docs/specs`).

This is the **single source of truth** for the state file schema. The coordinator, `inspecting-state`, and any other skill that touches the state file MUST match this definition. Drift between this file and a skill's local schema is a bug; fix this file first, then the skill.

A machine-readable JSON Schema version lives alongside this file at `state-schema.json` for objective validation.

## Lifecycle in one paragraph

The state file is **created** by `writing-specs` at Stage 2 (it doesn't exist during Stages 0-1; preflight outcomes are held in coordinator memory). It is **updated** at every stage boundary by either the coordinator or the active phase skill (per the Field Ownership table below). It is **committed alongside** the relevant artifact commits (no standalone "update state" commits). It is **deleted** at Stage 15 by `finishing-sdd` on completion (Options 1, 2, 4) or **kept** when the user chooses Option 3 (keep as-is for future iteration).

## Required fields

These MUST be present in any valid state file (i.e., from Stage 2 onward):

| Field | Type | Description |
|---|---|---|
| `feature_id` | string | Format: `NNN-<short-name>`, e.g., `003-user-auth`. Sequential within the project. |
| `short_name` | string | Kebab-case, 2-4 words. Used in branch names, ADR refs, handoff filenames. |
| `started_at` | string (ISO-8601 UTC) | When Stage 2 first initialized this state file. |
| `updated_at` | string (ISO-8601 UTC) | Last write timestamp. Updated on every atomic write. |
| `branch` | string | The feature branch this run lives on. Set by `writing-specs` from the coordinator's in-memory preflight outcomes. |
| `spec_path` | string | Repo-relative path to `spec.md`. Default: `<spec_dir>/<feature_id>/spec.md`. |
| `current_stage` | string | One of the enum values in the Stage Name Mapping table below. |
| `stages_completed` | array of strings | Stages finished successfully, in chronological order. Each value from the Stage Name Mapping table's "stages_completed entry" column. |
| `stages_skipped` | array of strings | Stages user opted to skip (only the four optional stages can appear here). |
| `preflight` | object | `{ "worktree_path": string|null, "original_branch": string }`. Captured from Stage 0 outputs. |
| `tasks` | object | `{ "T###": "pending" | "in_progress" | "completed" }`. Empty `{}` before Stage 12 initializes it. |

## Optional fields (present after specific stages advance)

| Field | Type | Present after | Description |
|---|---|---|---|
| `plan_path` | string | Stage 8 | Repo-relative path to `plan.md`. |
| `adr_results` | array of objects | Stage 6 | `[{ "id": "ADR-NNNN", "title": string, "status": "Proposed"|"Accepted"|..., "path": string }, ...]`. Empty array if no ADRs created. |
| `test_status` | string | Stage 13 | One of: `passed`, `passed_after_fixes`, `skipped_mcp_unavailable`, `skipped_user_choice`, `failed_escalated`, or `null` if Stage 13 hasn't run. |
| `fix_iterations` | integer | Stage 13 | How many test-fix iterations ran (0-3). |
| `final_review_completed` | boolean | After Stage 12 final review | Set `true` by `implementing-plans` when the cross-cutting final code-quality review passes. |
| `handoff_path` | string | Stage 14 | Path to the generated handoff doc. Repo-relative if inside the repo, absolute if `paths.handoff_dir` resolves outside. |
| `memory_file_updated` | boolean | Stage 15 | `true` if the memory file was updated this run; `false` if no update was needed or the stage was skipped. |
| `memory_file_path` | string | Stage 15 (only if updated) | Path to the memory file that was updated. May be repo-relative or absolute. |
| `reviewer_pushbacks` | array of objects | Any stage where the coordinator pushed back | `[{ "stage": string, "finding": string, "reason": string }, ...]`. Empty array `[]` is the initial value. |
| `spec_auto_review_iterations` | integer | Stage 3 (and 4 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |
| `plan_auto_review_iterations` | integer | Stage 9 (and 10 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |

## Field Ownership (who writes what)

Each field is owned by exactly one skill or the coordinator. Multiple writers = bugs.

| Field | Owner | Notes |
|---|---|---|
| `feature_id`, `short_name`, `started_at`, `branch`, `spec_path`, `preflight.*` | `writing-specs` (Stage 2 init) | Set once at Stage 2; never updated after. |
| `updated_at` | Every writer | Touched on each atomic write. |
| `current_stage` | Coordinator | Advanced at every stage boundary. |
| `stages_completed` | Coordinator | Appended to after each stage succeeds. |
| `stages_skipped` | Coordinator | Appended when user declines an optional stage. |
| `tasks` (init) | `implementing-plans` Step 2 | Merge with existing on resume; never overwrite completed tasks. |
| `tasks` (per-task transitions) | `implementing-plans` Step 3 | `pending` → `in_progress` at task start; `in_progress` → `completed` at task finish. |
| `plan_path` | `writing-plans` (Stage 8 init) | Set once. |
| `adr_results` | Coordinator | Populated from `maintaining-adrs`' return value at Stage 6. |
| `test_status`, `fix_iterations` | `testing-implementation` | Written when Stage 13 completes. |
| `final_review_completed` | `implementing-plans` | Set to `true` after Stage 12's final review approves. |
| `handoff_path` | Coordinator | Set after Stage 14 from the `generating-handoff` subagent's report. |
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
| 4 | `spec_second_review` | `spec_second_reviewed` | `spec_second_review` |
| 5 | `spec_grill` | `spec_grilled` | `spec_grill` |
| 6 | `adr_maintenance` | `adrs_maintained` | — |
| 7 | `spec_approval` | `spec_approved` | — |
| 8 | `plan_writing` | `plan_written` | — |
| 9 | `plan_auto_review` | `plan_auto_reviewed` | — |
| 10 | `plan_second_review` | `plan_second_reviewed` | `plan_second_review` |
| 11 | `plan_approval` | `plan_approved` | — |
| 12 | `implementing` | `implementation_complete` | — |
| 13 | `testing` | `testing_complete` | `testing` |
| 14 | `handoff` | `handoff_generated` | `handoff` |
| 15 | `memory_file` | `memory_file_maintained` | `memory_file` |
| 16 | `finishing` | `finished` | — |

## Atomic write pattern (required)

Every state write follows:

```bash
# Compose the new state JSON
... > state.json.tmp
mv state.json.tmp state.json
```

Atomicity matters: a half-written `state.json` is unrecoverable. The `mv` is atomic on POSIX filesystems (within the same filesystem); the `.tmp` file ensures partial writes never replace the previous state.

## Reference example (mid-implementation, resume case)

This is a typical state during Stage 12 with 3 tasks done, 1 in progress, 3 pending:

```json
{
  "feature_id": "003-user-auth",
  "short_name": "user-auth",
  "started_at": "2026-05-20T14:32:00Z",
  "updated_at": "2026-05-20T16:45:00Z",
  "branch": "feat/user-auth",
  "spec_path": "docs/specs/003-user-auth/spec.md",
  "plan_path": "docs/specs/003-user-auth/plan.md",
  "current_stage": "implementing",
  "stages_completed": [
    "preflight", "discovering", "spec_written",
    "spec_auto_reviewed", "adrs_maintained", "spec_approved",
    "plan_written", "plan_auto_reviewed", "plan_approved"
  ],
  "stages_skipped": ["spec_second_review", "spec_grill", "plan_second_review"],
  "preflight": {
    "worktree_path": null,
    "original_branch": "main"
  },
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

`inspecting-state` validates each state file it finds against this schema and reports:
- **Unparseable JSON** → reports the parse error
- **Missing required fields** → reports which are missing
- **Invalid enum values** — e.g., `current_stage` not in the Stage Name Mapping; `tasks.T###` not in `pending|in_progress|completed`; `test_status` not in the documented set
- **Inconsistent state** — e.g., `tasks` is non-empty but `plan_path` is null (plan stage should have come first); `current_stage` says `implementing` but `stages_completed` doesn't include `plan_approved`

For machine-readable validation, see `state-schema.json` (JSON Schema Draft 2020-12).
