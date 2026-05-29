# SDD State File Schema (Canonical)

**Location:** `.sublime-skills/state.json` (a single global file; one active SDD run at a time).

This is the **single source of truth** for the state file schema. The coordinator and any other skill that touches the state file MUST match this definition. Drift between this file and a skill's local schema is a bug; fix this file first, then the skill.

## Git policy (CRITICAL)

`.sublime-skills/state.json` is permanently gitignored via `.sublime-skills/.gitignore`. It MUST NEVER be committed at any stage.

Forbidden, even when "just this once":

- `git add -f .sublime-skills/state.json` (force-add bypasses gitignore)
- `git add --force ...` (same)
- `git update-index --add .sublime-skills/state.json` (low-level bypass)
- `git commit -- .sublime-skills/state.json` (any direct path-add)
- Editing `.sublime-skills/.gitignore` to remove the entry

The state file is local-only orchestration metadata. It exists from Stage 0 (ss-sdd-preflight creates the shell after validation passes) until Stage 11 (ss-sdd-finishing deletes it via plain `rm`, NOT `git rm`). Across every stage between, it lives uncommitted in the working tree.

Recovery if accidentally committed:

```bash
git rm --cached .sublime-skills/state.json
git commit -m "fix: untrack accidentally-tracked SDD state"
```

A machine-readable JSON Schema version lives alongside this file at `state-schema.json` for objective validation.

## Lifecycle in one paragraph

The state file is **created** by `ss-sdd-preflight` at Stage 0, after all validation passes, as a minimal shell containing only the always-required fields. It is **updated** at every stage boundary by either the coordinator or the active phase skill (per the Field Ownership table below) — feature-identifying fields (`feature_id`, `short_name`, `work_type`, `spec_path`) are filled in at Stage 2 by `ss-sdd-writing-specs`, with later fields appended as their owning stages run. It is **never committed at any stage** — the file lives only in the working tree and is gitignored throughout. It is **deleted** at Stage 11 by `ss-sdd-finishing` via plain `rm` (no commit; nothing to untrack from git).

## Always-required fields

These MUST be present from the moment preflight (Stage 0) writes the shell:

| Field | Type | Description |
|---|---|---|
| `started_at` | string (ISO-8601 UTC) | When preflight first wrote the shell. |
| `updated_at` | string (ISO-8601 UTC) | Last write timestamp. Updated on every atomic write. |
| `current_stage` | string | One of the enum values in the Stage Name Mapping table below. Starts as `preflight`; coordinator advances at every stage boundary. |
| `stages_completed` | array of strings | Stages finished successfully, in chronological order. Initialized as `[]`; each value from the Stage Name Mapping table's "stages_completed entry" column. |
| `stages_skipped` | array of strings | Stages user opted to skip (only the two optional stages can appear here). Initialized as `[]`. |
| `tasks` | object | `{ "T###": "pending" | "in_progress" | "completed" }`. Initialized as `{}` by preflight; populated with per-task entries by `ss-sdd-implementing-plans` at Stage 8. |

## Required-by-Stage-2 fields

These are absent from the preflight shell and become required once `ss-sdd-writing-specs` (Stage 2) has run. Every skill that reads them runs at Stage 3 or later, so consumers can safely assume presence:

| Field | Type | Description |
|---|---|---|
| `feature_id` | string | Format: `NNN-<short-name>`, e.g., `003-user-auth`. Sequential within the project. |
| `short_name` | string | Kebab-case, 2-4 words. Used in branch names and ADR refs. |
| `work_type` | string | `"feature"` or `"fix"`. Captured at Stage 1 by `ss-sdd-discovering-requirements`; persisted at Stage 2; used by `ss-sdd-choosing-feature-branch` (Stage 7) to derive the suggested branch prefix. |
| `spec_path` | string | Repo-relative path to `spec.md`. Default: `docs/specs/<feature_id>/spec.md`. |

## Optional fields (present after specific stages advance)

| Field | Type | Present after | Description |
|---|---|---|---|
| `plan_path` | string | Stage 6 | Repo-relative path to `plan.md`. |
| `adr_results` | array of objects | Stage 4 | `[{ "id": "ADR-NNNN", "title": string, "status": "Proposed"|"Accepted"|..., "path": string }, ...]`. Empty array if no ADRs created. |
| `branch_name` | string | Stage 7 | The branch the user committed to at Stage 7. Read by Stage 11 (`ss-sdd-finishing`) to know which branch to merge into `main` and delete. |
| `test_status` | string | Stage 9 | One of: `passed`, `passed_after_fixes`, `skipped_mcp_unavailable`, `skipped_user_choice`, `failed_escalated`, or `null` if Stage 9 hasn't run. |
| `fix_iterations` | integer | Stage 9 | How many test-fix iterations ran (0-3). |
| `final_review_completed` | boolean | After Stage 8 final review | Set `true` by `ss-sdd-implementing-plans` when the cross-cutting final code-quality review passes. |
| `memory_file_updated` | boolean | Stage 10 | `true` if the memory file was updated this run; `false` if no update was needed or the stage was skipped. |
| `memory_file_path` | string | Stage 10 (only if updated) | Path to the memory file that was updated. May be repo-relative or absolute. |
| `reviewer_pushbacks` | array of objects | Any stage where the coordinator pushed back | `[{ "stage": string, "finding": string, "reason": string }, ...]`. Empty array `[]` is the initial value. |
| `spec_auto_review_iterations` | integer | Stage 3 | Fix-loop iterations consumed (0-2). Hard cap at 2. |

## Field Ownership (who writes what)

Each field is owned by exactly one skill or the coordinator. Multiple writers = bugs.

| Field | Owner | Notes |
|---|---|---|
| `started_at`, initial `tasks: {}`, `stages_completed: []`, `stages_skipped: []` | `ss-sdd-preflight` (Stage 0 shell creation) | Written once at the end of preflight, after all validation passes. |
| `feature_id`, `short_name`, `spec_path` | `ss-sdd-writing-specs` (Stage 2) | Written into the existing state file; never updated after. |
| `work_type` | `ss-sdd-discovering-requirements` (Stage 1; captured in-memory) + persisted by `ss-sdd-writing-specs` (Stage 2) | Set once; never updated after. |
| `updated_at` | Every writer | Touched on each atomic write. |
| `current_stage` | Coordinator | Initialized as `"preflight"` by the shell; advanced at every stage boundary. |
| `stages_completed` | Coordinator | Appended to after each stage succeeds. |
| `stages_skipped` | Coordinator | Appended when user declines an optional stage. |
| `tasks` (per-task init) | `ss-sdd-implementing-plans` Step 2 | Adds task entries to the existing `{}`; never overwrites completed tasks. |
| `tasks` (per-task transitions) | `ss-sdd-implementing-plans` Step 3 | `pending` → `in_progress` at task start; `in_progress` → `completed` at task finish. |
| `plan_path` | `ss-sdd-writing-plans` (Stage 6 init) | Set once. |
| `adr_results` | Coordinator | Populated from `ss-sdd-maintaining-adrs`' return value at Stage 4. |
| `branch_name` | `ss-sdd-choosing-feature-branch` (Stage 7) | Set once at Stage 7 in the same atomic write that advances `current_stage` and appends `branch_chosen`. Never updated after. |
| `test_status`, `fix_iterations` | `ss-sdd-testing-implementation` | Written when Stage 9 completes. |
| `final_review_completed` | `ss-sdd-implementing-plans` | Set to `true` after Stage 8's final review approves. |
| `memory_file_updated`, `memory_file_path` | Coordinator | Set after Stage 10 from the `ss-sdd-maintaining-memory-file` subagent's report. |
| `reviewer_pushbacks` | `ss-sdd-receiving-review-findings` | Appended whenever the coordinator pushes back instead of fixing. |
| `spec_auto_review_iterations` | `ss-sdd-receiving-review-findings` | Incremented per fix-loop iteration. |

## Stage Name Mapping

| Stage # | `current_stage` value | `stages_completed` entry | `stages_skipped` entry (if applicable) |
|---|---|---|---|
| 0 | `preflight` | `preflight` | — |
| 1 | `discovering` | `discovering` | — |
| 2 | `spec_writing` | `spec_written` | — |
| 3 | `spec_auto_review` | `spec_auto_reviewed` | — |
| 4 | `adr_maintenance` | `adrs_maintained` | — |
| 5 | `spec_approval` | `spec_approved` | — |
| 6 | `plan_writing` | `plan_written` | — |
| 7 | `choosing_branch` | `branch_chosen` | — |
| 8 | `implementing` | `implementation_complete` | — |
| 9 | `testing` | `testing_complete` | `testing` |
| 10 | `memory_file` | `memory_file_maintained` | `memory_file` |
| 11 | `finishing` | `finished` | — |

## Atomic write pattern (required)

Every state write follows:

```bash
# Compose the new state JSON
... > state.json.tmp
mv state.json.tmp state.json
```

Atomicity matters: a half-written `state.json` is unrecoverable. The `mv` is atomic on POSIX filesystems (within the same filesystem); the `.tmp` file ensures partial writes never replace the previous state.

## Reference example (mid-implementation snapshot)

This is a typical state during Stage 8 with 3 tasks done, 1 in progress, 3 pending:

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
    "plan_written", "branch_chosen"
  ],
  "stages_skipped": [],
  "branch_name": "feat/user-auth",
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
  "reviewer_pushbacks": [],
  "spec_auto_review_iterations": 1
}
```

## Validation

This schema is the contract. A consumer that wants to verify a state file should check:
- JSON parses
- All always-required fields present; if `current_stage` is past `spec_writing`, the four required-by-Stage-2 fields are also present
- Enum values valid (`current_stage` from the Stage Name Mapping; `tasks.T###` in `pending|in_progress|completed`; `test_status` from the documented set)
- Stage progression is consistent (e.g., `current_stage: implementing` implies `branch_chosen` is in `stages_completed`)

For machine-readable validation, see `state-schema.json` (JSON Schema Draft 2020-12).
