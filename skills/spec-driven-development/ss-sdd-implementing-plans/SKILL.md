---
name: ss-sdd-implementing-plans
description: Use during the implementation stage of an SDD pipeline run, after the plan is committed. Drives the per-task loop — dispatching one fresh implementer subagent per task — followed by a single mandatory final cross-cutting code-quality review on the whole branch diff, with continuous execution between independent tasks.
---

# Implementing Plans

## Overview

Execute the plan task-by-task. Per task: one fresh implementer subagent. After every task is complete, a single mandatory final cross-cutting code-quality reviewer runs on the full branch diff. The loop continues without pausing for human check-in unless a task is BLOCKED or all tasks are complete.

**Core principle:** Fresh subagent per task (no context pollution). The implementer's own TDD + self-review handles per-task discipline; the final cross-cutting review at the end is the safety net for systemic issues (inconsistencies between tasks, integration drift) that no single-task view can see.

**Each subagent loads its guidance:**
- Implementer → `ss-sdd-implementing-task` skill
- Final reviewer → the self-contained `./final-review-prompt.md` template (no skill to load; the prompt carries the full protocol)

`implementer-prompt.md` is a dispatch envelope; its protocol lives in the `ss-sdd-implementing-task` skill. `final-review-prompt.md` is self-contained.

**Announce at start:** "I'm using the ss-sdd-implementing-plans skill to execute the plan task-by-task."

## Hard Gates

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- Do NOT start implementation on `main` or `master` — Stage 7 (`ss-sdd-choosing-feature-branch`) should have settled the work onto a feature branch by the time you run. If `git branch --show-current` returns `main`/`master`, something went wrong upstream; halt and surface.
- The final cross-cutting code-quality review at the end of the stage (Step 4) is MANDATORY — never skip it.
- Do NOT dispatch multiple implementer subagents in parallel — sequential is the rule; conflicts otherwise

## Checklist

1. Read the plan and extract every task with its full text and context
2. Initialize/sync the state file's `tasks` map and replace the coordinator's pre-implementation todo list with one todo per plan task
3. For each task in order:
   - Dispatch implementer subagent
   - Handle status (DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT)
   - Mark task complete in state file and todo tool
4. After all tasks complete: dispatch the final code-reviewer subagent on the full branch diff (mandatory)
5. Update state file with `final_review_completed: true`
6. Hand off to the next stage (testing or finishing)

## Step 1: Read the Plan, Extract Tasks

Read `docs/specs/NNN-<short-name>/plan.md` ONCE. Build an internal list of every task with:
- Task ID (T###)
- Full task text (header, files, requirements traceability, all steps)
- Scene-setting context: which story it serves, what was built in prior tasks that this task depends on, any architectural notes

Do NOT make subagents re-read the plan file. You pass them the full text inline.

## Step 2: Initialize or Sync State and Todos

**Read the current `state.json` first.** Step 2 is idempotent on entry: if `state.tasks` is already populated (e.g., a prior iteration of this skill ran in the same conversation), preserve it; if not, initialize it from the plan.

### 2a. Sync the tasks map

Compare the plan's task list (T001, T002, ...) against `state.tasks`:

- **If `state.tasks` is empty or absent** → initialize every task as `"pending"`.
- **If `state.tasks` has entries** → **do NOT overwrite existing statuses.** Apply this merge:
  - For each task in the plan: if it already has a status in `state.tasks`, keep it. If not, add it as `"pending"`.
  - For any key in `state.tasks` that's no longer in the plan (rare — usually only if the plan was re-rendered with renumbered tasks): leave it alone but log a warning to the controller's report ("orphan task in state").

Resulting tasks map example with mid-stage state preserved:

```json
"tasks": {
  "T001": "completed",
  "T002": "completed",
  "T003": "completed",
  "T004": "in_progress",
  "T005": "pending",
  "T006": "pending"
}
```

Set `current_stage: "implementing"` (unconditionally). Write the state file atomically.

### 2b. Replace the coordinator's todo list with a per-task list

By the time this skill runs, the coordinator's pre-implementation todo list (Stages 0–7) is fully `completed`. Replace it with one new todo per plan task (T001, T002, ...). Pass the harness's todo/task tool the full new list — it overwrites the prior list in place.

Match each new todo's initial status to `state.tasks`: `completed` / `in_progress` / `pending`. The coordinator creates the post-implementation list (Stages 9–11) when this skill returns.

### 2c. Pick the starting task

- If any task is `"in_progress"`: that's the task the previous implementer subagent was working on before it died (returned BLOCKED, was interrupted by the user, etc.). **Re-dispatch from the start of that task** — the implementer is a fresh subagent; partial work is either committed or lost, so re-running from scratch is safe.
- Otherwise: start with the first `"pending"` task in plan order.

## Step 3: Per-Task Loop

Starting from the task identified by Step 2c, iterate forward in plan order. **Skip any task already marked `"completed"`** in `state.tasks` — do not re-run them.

For each task in order:

### 3a. Dispatch Implementer

First, update the state file to mark this task as in progress:

```json
"tasks": { "T###": "in_progress", ... }
```

(Atomic write: write to `.sublime-skills/state.json.tmp`, then `mv` to `.sublime-skills/state.json`.)

Dispatch a fresh subagent with the prompt at `./implementer-prompt.md`. Fill in placeholders:

- `{TASK_ID}`
- `{TASK_TEXT}` — full task text from the plan
- `{CONTEXT}` — scene-setting (story, dependencies, architectural notes)
- `{SPEC_PATH}` — `docs/specs/NNN-<short-name>/spec.md`
- `{PLAN_PATH}` — `docs/specs/NNN-<short-name>/plan.md`
- `{WORKING_DIR}` — repo root

The implementer subagent uses the `ss-sdd-implementing-task` skill for protocol and produces: implementation, tests, commits, self-review, status report.

### 3b. Handle Status

The implementer reports one of:

| Status | Action |
|---|---|
| `DONE` | Proceed to 3c (mark complete). |
| `DONE_WITH_CONCERNS` | Read the concerns. **If concerns are about correctness or scope:** re-dispatch a fresh implementer with the original task PLUS the concerns appended ("address these specific concerns before reporting DONE: [list]"). **If observations only** (e.g., "this file is getting large"), note in your task summary and proceed to 3c. |
| `NEEDS_CONTEXT` | Read the implementer's `NEEDS_CONTEXT` response — it should include "What you need / What you tried / What you'd do if forced to guess". For each missing piece: if you can answer from the plan/spec/your context, append the answer to the task and re-dispatch a fresh implementer. If you can't answer (it requires user judgment), surface to user — don't fabricate context. Never auto-decide on the implementer's "forced guess" without confirming first. |
| `BLOCKED` | Assess: (1) context problem → provide more context, re-dispatch same model; (2) reasoning insufficient → re-dispatch with a more capable model; (3) task too large → break into smaller pieces (update plan, ask user); (4) plan is wrong → escalate to user. Never silently retry the same dispatch. |

Never silently ignore a BLOCKED or NEEDS_CONTEXT.

### 3c. Mark Complete

As soon as the implementer reports DONE (or DONE_WITH_CONCERNS for observations only):

1. Update state file (atomic write): `tasks[T###]: "completed"`, update `updated_at`
2. Update todo tool: mark this task's todo as completed
3. Continue to next task

## Step 4: Final Review

**Mandatory.** This is the safety net and the cross-cutting check (inconsistencies between tasks, integration drift) that per-task work can't see. Never skip it.

After every task is complete, dispatch one fresh subagent with the `./final-review-prompt.md` template, filled with:

- `{BASE_SHA}` = first commit on this feature branch
- `{HEAD_SHA}` = current HEAD

The prompt is self-contained — the subagent follows it directly (it carries the quality dimensions, severity rubric, cross-cutting focus, and output format). It reviews the whole branch diff and returns Approved or Issues Found.

If issues are found, address them (dispatch a fresh implementer with the findings as the task) and re-review. Cap: 3 iterations, then escalate to user.

Once the final review is Approved, update the state file:

```json
{ "final_review_completed": true }
```

## Step 5: Update State

```json
{
  "current_stage": "implementing",
  "final_review_completed": true,
  "updated_at": "<ISO-8601 timestamp>"
}
```

Leave the coordinator to advance `current_stage` after this skill returns (it sets `current_stage` to `"testing"` or `"finishing"` per user choice in the Stage 9 prompt, and adds `"implementation_complete"` to `stages_completed`).

## Step 6: Hand Off

Return to the coordinator with:

```
Implementation complete.
- Tasks completed: <N>/<N>
- Final review: Approved (loops: <iterations>)
- Branch: <branch-name>
```

The coordinator moves to Stage 9 (optional testing) or directly to Stage 11 (finishing) based on user choice.

## Continuous Execution

Do not pause to check in with the user between tasks. The user asked you to execute the plan — execute it. The only reasons to stop:

- BLOCKED status you cannot resolve internally
- The final-review fix loop hit its cap (3 iterations)
- The plan itself appears wrong
- All tasks are complete

"Should I continue?" prompts between completed tasks waste the user's time.

## Model Selection (Cost / Speed)

Use the least capable model that can handle each role.

| Role | Suggested model strength |
|---|---|
| Implementer for mechanical tasks (1-2 files, clear spec) | Fast / cheap |
| Implementer for integration tasks (multi-file, judgment) | Standard |
| Implementer for design judgment, broad context | Most capable |
| Final reviewer | Most capable (subtle, cross-cutting issues live here) |

When a BLOCKED implementer needed more reasoning, re-dispatch with a more capable model.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the final review | It's mandatory — it's the safety net for the whole feature |
| Reusing the same subagent instance across tasks | Fresh subagent per task — preserves clean context |
| Making the subagent read the plan file | Pass full task text inline |
| Skipping scene-setting context in the dispatch prompt | Subagent needs to know where the task fits |
| Treating Minor final-review findings as blocking | Minor = note and proceed |
| Pausing between tasks for "should I continue?" | Continuous execution unless BLOCKED |
| Silently swallowing BLOCKED status | Always assess and act; never just retry |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |

## Red Flags

- About to skip the final review → STOP; it's mandatory
- About to dispatch two implementers in parallel → STOP; sequential only
- About to "fix it myself" inline instead of dispatching a fresh implementer → STOP; protect controller context
- Final-review fix loop hitting iteration 4 → STOP and escalate
- About to start a task on `main`/`master` or a branch other than the one Stage 7 settled on (`state.branch_name`) → STOP and surface; branch was set at Stage 7, not preflight
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP

## Prompt Templates

- `./implementer-prompt.md`
- `./final-review-prompt.md`
