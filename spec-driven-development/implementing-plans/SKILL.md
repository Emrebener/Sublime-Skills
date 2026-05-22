---
name: implementing-plans
description: Use during the implementation stage of an SDD pipeline run, after the plan is committed and approved. Drives the per-task loop — dispatching implementer subagents and two-stage reviewer subagents (spec compliance, then code quality) for each task — with continuous execution between independent tasks.
---

# Implementing Plans

## Overview

Execute the plan task-by-task. Per task: fresh implementer subagent → spec-compliance reviewer subagent → code-quality reviewer subagent. The loop continues without pausing for human check-in unless a task is BLOCKED or all tasks are complete.

**Core principle:** Fresh subagent per task (no context pollution) + two-stage review (spec compliance first, then code quality) = high quality, fast iteration.

**Each subagent loads a corresponding skill:**
- Implementer → `implementing-task` skill
- Spec-compliance reviewer → `reviewing-task-compliance` skill
- Code-quality reviewer → `reviewing-task-quality` skill

The prompt templates in this directory are dispatch envelopes only; the protocols live in those skills.

**Announce at start:** "I'm using the implementing-plans skill to execute the plan task-by-task."

## Hard Gates

- Do NOT start implementation on main/master without explicit user consent — preflight should have moved you to a feature branch
- Do NOT skip reviews. Each task goes through both spec compliance AND code quality.
- Do NOT proceed to the next task while either review has open issues
- Do NOT dispatch multiple implementer subagents in parallel — sequential is the rule; conflicts otherwise
- Do NOT let an implementer's self-review replace the spec-compliance review — both are needed
- Do NOT start code-quality review before spec compliance is approved

## Checklist

1. Read the plan and extract every task with its full text and context
2. Initialize/sync the state file's `tasks` map and create todos via the harness's task tool
3. For each task in order:
   - Dispatch implementer subagent
   - Handle status (DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT)
   - Dispatch spec-compliance reviewer; loop fix-review until approved
   - Dispatch code-quality reviewer; loop fix-review until approved
   - Mark task complete in state file and todo tool
4. After all tasks complete: dispatch final code-reviewer subagent on the full diff
5. Update state file with `current_stage: "implementation_complete"`
6. Hand off to the next stage (testing or finishing)

## Step 1: Read the Plan, Extract Tasks

Read `docs/specs/NNN-<short-name>/plan.md` ONCE. Build an internal list of every task with:
- Task ID (T###)
- Full task text (header, files, requirements traceability, all steps)
- Scene-setting context: which story it serves, what was built in prior tasks that this task depends on, any architectural notes

Do NOT make subagents re-read the plan file. You pass them the full text inline.

## Step 2: Initialize or Sync State and Todos

**Read the current `state.json` first** — this skill runs on both fresh starts and resumes, and resume state MUST be preserved.

### 2a. Sync the tasks map

Compare the plan's task list (T001, T002, ...) against `state.tasks`:

- **If `state.tasks` is empty or absent** → fresh start. Initialize every task as `"pending"`.
- **If `state.tasks` has entries** → resume. **Do NOT overwrite existing statuses.** Apply this merge:
  - For each task in the plan: if it already has a status in `state.tasks`, keep it. If not, add it as `"pending"`.
  - For any key in `state.tasks` that's no longer in the plan (rare — usually only if the plan was re-rendered with renumbered tasks): leave it alone but log a warning to the controller's report ("orphan task in state").

Resulting tasks map example on resume:

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

### 2b. Sync the todo tool

Create one todo per plan task using the harness's todo/task tool.

On resume: if the harness preserved todos from a prior session, reconcile their statuses to match `state.tasks`. If the harness didn't preserve todos, create them fresh and immediately mark `completed`/`in_progress` ones to match the state file.

### 2c. Pick the starting task

- If any task is `"in_progress"`: that's where the prior session was interrupted. **Re-dispatch from the start of that task** (the implementer is a fresh subagent; partial work is either committed or lost — re-running from scratch is safe).
- Otherwise: start with the first `"pending"` task in plan order.

## Step 3: Per-Task Loop

Starting from the task identified by Step 2c (either the in-progress task on resume, or the first pending task on a fresh start), iterate forward in plan order. **Skip any task already marked `"completed"`** in `state.tasks` — do not re-run them.

For each task in order:

### 3a. Dispatch Implementer

First, update the state file to mark this task as in progress:

```json
"tasks": { "T###": "in_progress", ... }
```

(Atomic write: write to `state.json.tmp`, then `mv`.)

Dispatch a fresh subagent with the prompt at `./implementer-prompt.md`. Fill in placeholders:

- `{TASK_ID}`
- `{TASK_TEXT}` — full task text from the plan
- `{CONTEXT}` — scene-setting (story, dependencies, architectural notes)
- `{SPEC_PATH}` — `docs/specs/NNN-<short-name>/spec.md`
- `{PLAN_PATH}` — `docs/specs/NNN-<short-name>/plan.md`
- `{WORKING_DIR}` — repo root

The implementer subagent uses the `implementing-task` skill for protocol and produces: implementation, tests, commits, self-review, status report.

### 3b. Handle Status

The implementer reports one of:

| Status | Action |
|---|---|
| `DONE` | Proceed to 3c (spec-compliance review) |
| `DONE_WITH_CONCERNS` | Read the concerns. **If concerns are about correctness or scope:** re-dispatch a fresh implementer with the original task PLUS the concerns appended ("address these specific concerns before reporting DONE: [list]"). **If observations only** (e.g., "this file is getting large"), note in your task summary and proceed to 3c (spec-compliance review). |
| `NEEDS_CONTEXT` | Read the implementer's `NEEDS_CONTEXT` response — it should include "What you need / What you tried / What you'd do if forced to guess". For each missing piece: if you can answer from the plan/spec/your context, append the answer to the task and re-dispatch a fresh implementer. If you can't answer (it requires user judgment), surface to user — don't fabricate context. Never auto-decide on the implementer's "forced guess" without confirming first. |
| `BLOCKED` | Assess: (1) context problem → provide more context, re-dispatch same model; (2) reasoning insufficient → re-dispatch with a more capable model; (3) task too large → break into smaller pieces (update plan, ask user); (4) plan is wrong → escalate to user. Never silently retry the same dispatch. |

Never silently ignore a BLOCKED or NEEDS_CONTEXT.

### 3c. Spec-Compliance Review

Dispatch a fresh subagent with `./spec-compliance-reviewer-prompt.md`. Fill in:

- `{TASK_ID}`
- `{TASK_TEXT}` — same task text as the implementer received
- `{SPEC_PATH}` — `docs/specs/NNN-<short-name>/spec.md`
- `{PLAN_PATH}` — `docs/specs/NNN-<short-name>/plan.md`
- `{BASE_SHA}` — `git log --oneline` head before implementer started
- `{HEAD_SHA}` — `git rev-parse HEAD` after implementer's commits

The reviewer compares the implementer's diff to the task spec. Returns: Approved or Issues Found with a list.

**If Issues Found:**
- Re-dispatch the implementer subagent (fresh — don't reuse) with the original task plus the reviewer's findings
- Tell the implementer: "Address these specific findings: [list]. Do not change anything else."
- Re-dispatch the spec-compliance reviewer with the new SHAs
- Loop until Approved

**Loop cap:** if spec-compliance review fails 3 times in a row, stop and escalate to user. The plan may be wrong or the task may be ill-specified.

### 3d. Code-Quality Review

Only after spec-compliance is Approved. Dispatch with `./code-quality-reviewer-prompt.md`. Same SHA pattern.

The reviewer evaluates the code (readability, naming, structure, idiomatic style, security, performance). Categorizes findings as Critical / Important / Minor.

**Handle:**
- Critical or Important findings → re-dispatch implementer to fix → re-dispatch code-quality reviewer
- Minor findings → accept; note them in the task report; proceed (no fix loop for minor)

**Loop cap:** same as spec-compliance — 3 iterations max, then escalate.

### 3e. Mark Complete

Once both reviewers have approved (or only Minor code-quality findings remain):

1. Update state file (atomic write): `tasks[T###]: "completed"`, update `updated_at`
2. Update todo tool: mark this task's todo as completed
3. Continue to next task

## Step 4: Final Review

After every task is complete, dispatch one more fresh subagent with the same code-quality-reviewer prompt but with:

- `{TASK_ID}` = "final"
- `{BASE_SHA}` = first commit on this feature branch
- `{HEAD_SHA}` = current HEAD

This catches cross-cutting issues that per-task review couldn't see.

If issues are found, address them (dispatch a fresh implementer with the findings as the task) and re-review.

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

Leave the coordinator to advance `current_stage` after this skill returns (it sets `current_stage` to `"testing"` or `"finishing"` per user choice in Stage 13 prompt, and adds `"implementation_complete"` to `stages_completed`).

## Step 6: Hand Off

Return to the coordinator with:

```
Implementation complete.
- Tasks completed: <N>/<N>
- Spec-compliance loops: <total iterations>
- Code-quality loops: <total iterations>
- Final review: Approved
- Branch: <branch-name>
```

The coordinator moves to Stage 13 (optional testing) or directly to Stage 14 (handoff generation) based on user choice. Finishing is now Stage 16.

## Continuous Execution

Do not pause to check in with the user between tasks. The user asked you to execute the plan — execute it. The only reasons to stop:

- BLOCKED status you cannot resolve internally
- A review loop hit its cap (3 iterations)
- The plan itself appears wrong
- All tasks are complete

"Should I continue?" prompts between completed tasks waste the user's time.

## Model Selection (Cost / Speed)

Use the least capable model that can handle each role:

| Role | Suggested model strength |
|---|---|
| Implementer for mechanical tasks (1-2 files, clear spec) | Fast / cheap |
| Implementer for integration tasks (multi-file, judgment) | Standard |
| Implementer for design judgment, broad context | Most capable |
| Spec-compliance reviewer | Standard |
| Code-quality reviewer | Most capable (subtle issues live here) |
| Final reviewer | Most capable |

When a BLOCKED implementer needed more reasoning, re-dispatch with a more capable model.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Reusing the same subagent instance across tasks | Fresh subagent per task — preserves clean context |
| Making the subagent read the plan file | Pass full task text inline |
| Skipping scene-setting context in the dispatch prompt | Subagent needs to know where the task fits |
| Starting code-quality before spec-compliance is approved | Wrong order — always spec first |
| Treating Minor code-quality findings as blocking | Minor = note and proceed |
| Pausing between tasks for "should I continue?" | Continuous execution unless BLOCKED |
| Silently swallowing BLOCKED status | Always assess and act; never just retry |

## Red Flags

- About to dispatch two implementers in parallel → STOP; sequential only
- About to "fix it myself" inline instead of dispatching a fresh implementer → STOP; protect controller context
- Review loop hitting iteration 4 → STOP and escalate
- About to start a task on a different branch than expected → STOP and verify preflight state

## Prompt Templates

- `./implementer-prompt.md`
- `./spec-compliance-reviewer-prompt.md`
- `./code-quality-reviewer-prompt.md`
