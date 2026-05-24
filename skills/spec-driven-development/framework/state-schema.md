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

The state file is local-only orchestration metadata. It exists from Stage 2 (ss-sdd-writing-specs creates it) until Stage 17 (ss-sdd-finishing deletes it via plain `rm`, NOT `git rm`). Across every stage between, it lives uncommitted in the working tree.

Recovery if accidentally committed:

```bash
git rm --cached .sublime-skills/state.json
git commit -m "fix: untrack accidentally-tracked SDD state"
```

A machine-readable JSON Schema version lives alongside this file at `state-schema.json` for objective validation.

## Lifecycle in one paragraph

The state file is **created** by `ss-sdd-writing-specs` at Stage 2 (it doesn't exist during Stages 0-1; preflight outcomes are held in coordinator memory). It is **updated** at every stage boundary by either the coordinator or the active phase skill (per the Field Ownership table below). It is **never committed at any stage** — the file lives only in the working tree and is gitignored throughout. It is **deleted** at Stage 17 by `ss-sdd-finishing` via plain `rm` (no commit; nothing to untrack from git).

## Required fields

These MUST be present in any valid state file (i.e., from Stage 2 onward):

| Field | Type | Description |
|---|---|---|
| `feature_id` | string | Format: `NNN-<short-name>`, e.g., `003-user-auth`. Sequential within the project. |
| `short_name` | string | Kebab-case, 2-4 words. Used in branch names, ADR refs, handoff filenames. |
| `work_type` | string | `"feature"` or `"fix"`. Captured at Stage 1 by `ss-sdd-discovering-requirements`; used by `ss-sdd-choosing-feature-branch` (Stage 12) to derive the suggested branch prefix. |
| `started_at` | string (ISO-8601 UTC) | When Stage 2 first initialized this state file. |
| `updated_at` | string (ISO-8601 UTC) | Last write timestamp. Updated on every atomic write. |
| `spec_path` | string | Repo-relative path to `spec.md`. Default: `docs/specs/<feature_id>/spec.md`. |
| `current_stage` | string | One of the enum values in the Stage Name Mapping table below. |
| `stages_completed` | array of strings | Stages finished successfully, in chronological order. Each value from the Stage Name Mapping table's "stages_completed entry" column. |
| `stages_skipped` | array of strings | Stages user opted to skip (only the four optional stages can appear here). |
| `tasks` | object | `{ "T###": "pending" | "in_progress" | "completed" }`. Initialized as `{}` by `ss-sdd-writing-specs` at Stage 2; populated with per-task entries by `ss-sdd-implementing-plans` at Stage 13. |

## Optional fields (present after specific stages advance)

| Field | Type | Present after | Description |
|---|---|---|---|
| `plan_path` | string | Stage 8 | Repo-relative path to `plan.md`. |
| `adr_results` | array of objects | Stage 6 | `[{ "id": "ADR-NNNN", "title": string, "status": "Proposed"|"Accepted"|..., "path": string }, ...]`. Empty array if no ADRs created. |
| `branch_name` | string | Stage 12 | The branch the user committed to at Stage 12. Read by Stage 17 (`ss-sdd-finishing`) to know which branch to merge into `main` and delete. Survives a restart between Stages 12 and 17. |
| `test_status` | string | Stage 14 | One of: `passed`, `passed_after_fixes`, `skipped_mcp_unavailable`, `skipped_user_choice`, `failed_escalated`, or `null` if Stage 14 hasn't run. |
| `fix_iterations` | integer | Stage 14 | How many test-fix iterations ran (0-3). |
| `final_review_completed` | boolean | After Stage 13 final review | Set `true` by `ss-sdd-implementing-plans` when the cross-cutting final code-quality review passes. |
| `handoff_path` | string | Stage 15 | Absolute path to the generated handoff doc, located under `$HOME/.sublime-skills/handoffs/<repo-basename>/`. |
| `memory_file_updated` | boolean | Stage 16 | `true` if the memory file was updated this run; `false` if no update was needed or the stage was skipped. |
| `memory_file_path` | string | Stage 16 (only if updated) | Path to the memory file that was updated. May be repo-relative or absolute. |
| `reviewer_pushbacks` | array of objects | Any stage where the coordinator pushed back | `[{ "stage": string, "finding": string, "reason": string }, ...]`. Empty array `[]` is the initial value. |
| `spec_auto_review_iterations` | integer | Stage 3 (and 5 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |
| `plan_auto_review_iterations` | integer | Stage 9 (and 10 if run) | Fix-loop iterations consumed (0-2). Hard cap at 2. |

## Field Ownership (who writes what)

Each field is owned by exactly one skill or the coordinator. Multiple writers = bugs.

| Field | Owner | Notes |
|---|---|---|
| `feature_id`, `short_name`, `started_at`, `spec_path` | `ss-sdd-writing-specs` (Stage 2 init) | Set once at Stage 2; never updated after. |
| `work_type` | `ss-sdd-discovering-requirements` (Stage 1; captured in-memory) + persisted by `ss-sdd-writing-specs` (Stage 2 init) | Set once; never updated after. |
| `updated_at` | Every writer | Touched on each atomic write. |
| `current_stage` | Coordinator | Advanced at every stage boundary. |
| `stages_completed` | Coordinator | Appended to after each stage succeeds. |
| `stages_skipped` | Coordinator | Appended when user declines an optional stage. |
| `tasks` (init) | `ss-sdd-implementing-plans` Step 2 | Merge with existing on resume; never overwrite completed tasks. |
| `tasks` (per-task transitions) | `ss-sdd-implementing-plans` Step 3 | `pending` → `in_progress` at task start; `in_progress` → `completed` at task finish. |
| `plan_path` | `ss-sdd-writing-plans` (Stage 8 init) | Set once. |
| `adr_results` | Coordinator | Populated from `ss-sdd-maintaining-adrs`' return value at Stage 6. |
| `branch_name` | `ss-sdd-choosing-feature-branch` (Stage 12) | Set once at Stage 12 in the same atomic write that advances `current_stage` and appends `branch_chosen`. Never updated after. |
| `test_status`, `fix_iterations` | `ss-sdd-testing-implementation` | Written when Stage 14 completes. |
| `final_review_completed` | `ss-sdd-implementing-plans` | Set to `true` after Stage 13's final review approves. |
| `handoff_path` | Coordinator | Set after Stage 15 from the `ss-sdd-generating-handoff` subagent's report. |
| `memory_file_updated`, `memory_file_path` | Coordinator | Set after Stage 16 from the `ss-sdd-maintaining-memory-file` subagent's report. |
| `reviewer_pushbacks` | `ss-sdd-receiving-review-findings` | Appended whenever the coordinator pushes back instead of fixing. |
| `spec_auto_review_iterations`, `plan_auto_review_iterations` | `ss-sdd-receiving-review-findings` | Incremented per fix-loop iteration. |

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
