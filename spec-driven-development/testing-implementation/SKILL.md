---
name: testing-implementation
description: Use during the optional feature-testing stage of an SDD pipeline run, after implementation completes and before finishing. Dispatches a tester subagent that uses browser/DB MCPs when available, falls back to code review otherwise, and orchestrates a fix-loop with hard caps if issues are found.
---

# Testing Implementation

## Overview

Feature-level verification, separate from the per-task unit tests that ran during implementation. The tester subagent picks a strategy based on what kind of feature this is and what tools are actually available — Playwright/browser-tools for UI, DB MCPs for data verification, regular test runners always, code review as a last-resort fallback.

**Core principle:** The coordinator does NOT test itself. If the tester subagent reports MCP unavailability, the coordinator surfaces a manual test plan to the user — it does not improvise.

**Each subagent loads a corresponding skill:**
- Tester → `testing-feature` skill
- Fixer → `fixing-test-failures` skill

The prompt templates in this directory are dispatch envelopes only; the protocols live in those skills.

**Announce at start:** "I'm using the testing-implementation skill to run feature-level tests."

## Hard Gates

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- Do NOT skip Stage 14 if the user said yes — run it
- The coordinator does NOT attempt to test the feature itself under any circumstance. If the tester subagent can't test, the coordinator surfaces the result to the user. It does not pick up the toolkit and try.
- Fix loop caps at **3 iterations**. After the third failed fix, escalate to user.
- Do NOT dispatch multiple tester subagents in parallel for the same feature

## Checklist

1. Determine feature type (UI / backend / library / mixed) from the plan
2. Dispatch tester subagent with `./tester-prompt.md`
3. Handle the result:
   - `PASS` → mark stage complete, hand off to finishing
   - `FAIL` → dispatch fixer subagent with the failures; re-test; loop ≤3 times
   - `MCP_UNAVAILABLE` → surface tester's manual test plan + code-review findings to user, ask whether to proceed
4. Update state file
5. Report

## Step 1: Determine Feature Type

Read the plan's tech stack and file structure. Classify:

- **UI-only:** changes are in a frontend codebase (React, Vue, Svelte, etc.), no backend changes
- **Backend-only:** changes are in API / service / database code, no UI changes
- **Library / CLI / tool:** packaged code with no runtime UI or service
- **Mixed:** both UI and backend changes

**If uncertain, classify as `mixed`** — the tester subagent handles both strategies anyway, and erring on the side of more coverage is safer than under-testing.

Pass this classification to the tester subagent.

## Step 2: Dispatch Tester

Dispatch a fresh subagent with the prompt at `./tester-prompt.md`. Fill placeholders:

- `{FEATURE_TYPE}` — UI / backend / library / mixed
- `{SPEC_PATH}` — for acceptance scenarios
- `{PLAN_PATH}` — for what was implemented
- `{BRANCH}` — current branch
- `{BASE_SHA}` — the merge-base with main
- `{HEAD_SHA}` — current HEAD

The tester returns one of three statuses:

| Status | Meaning |
|---|---|
| `PASS` | Ran real tests via available tools; everything passed |
| `FAIL` | Ran real tests; issues found — list of failing scenarios with context |
| `MCP_UNAVAILABLE` | Couldn't run real tests; here's a manual test plan + code review findings |

## Step 3: Handle Result

### 3a. PASS

Update state file:

```json
{
  "current_stage": "testing_complete",
  "test_status": "passed",
  "stages_completed": [..., "testing_complete"]
}
```

Hand off to finishing-sdd.

### 3b. FAIL

The tester returns a list of failing scenarios with:
- Scenario description (from the spec)
- What was expected
- What actually happened
- Where in the code the issue likely lives (file:line if identifiable)

Dispatch a **fresh** subagent with `./fixer-prompt.md`. Fill placeholders:

- `{FAILURES}` — the failure list returned by the tester, verbatim (one block per failure with: story, scenario, expected, actual, likely location, reproduction)
- `{BRANCH}` — current branch name
- `{WORKING_DIR}` — repo root

The fixer's role is implementation-only — fix the listed issues, commit, return.

If the fixer reports `BLOCKED` due to a commit failure (pre-commit hook, signing, etc.), surface to user with the commit error output. Per the Commit Failure Protocol in `sdd-coordinator`. Do NOT instruct the fixer to bypass hooks.

After the fixer reports DONE, re-dispatch the tester with the new HEAD SHA.

**Loop cap: 3 iterations.** Track in state file:

```json
{
  "test_status": "in_fix_loop",
  "fix_iterations": 2
}
```

After 3 failed iterations, **stop and escalate**:

> "Three test-fix iterations didn't resolve the issues. The failures suggest [tester's summary]. The plan or spec may need revision. How would you like to proceed?
> 1. Pause SDD; I'll keep the branch and you can investigate
> 2. Revise the plan/spec and re-enter implementation
> 3. Accept the current state and proceed to finishing despite the failures"

Wait for user direction.

### 3c. MCP_UNAVAILABLE

The tester couldn't run real tests due to missing tools (no browser MCP, no DB MCP, etc.). It returns:
- What tests it would have run (manual test plan)
- Findings from its code-review fallback (anything suspicious it spotted)

**The coordinator MUST NOT attempt to test on its own.** Present the result to the user:

> "Couldn't run automated tests for this feature — [tester's reason: no browser MCP / no DB MCP / etc.]. The tester did a code review fallback and produced a manual test plan:
>
> [manual test plan]
>
> [code review findings, if any]
>
> Options:
> 1. Run the manual tests now and tell me the result
> 2. Skip testing and proceed to finishing
> 3. Pause SDD so you can configure the missing MCP and re-run testing later"

Wait for user direction.

If the user runs the manual tests and reports results, record them in state file and proceed accordingly.

## Step 4: Update State

After resolution, update state file:

```json
{
  "current_stage": "testing_complete" | "testing_skipped",
  "test_status": "passed" | "passed_after_fixes" | "skipped_mcp_unavailable" | "skipped_user_choice" | "failed_escalated",
  "fix_iterations": <N>,
  "stages_completed": [..., "testing_complete"]
}
```

## Step 5: Report

```
Testing complete.
- Status: <pass/fail/skipped>
- Feature type: <UI/backend/library/mixed>
- Tools used: <browser-tools | playwright | postgres-mcp | code-review-fallback>
- Fix iterations: <N>
- Manual test plan: <yes/no>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Coordinator decides to "just test it myself" when MCP_UNAVAILABLE | NO — surface to user; testing is not the coordinator's job |
| Skipping the fix-loop cap | Hard cap at 3 — beyond that, plan/spec likely needs revision |
| Re-dispatching the same tester instance for fix verification | Fresh subagent each cycle — context isolation matters |
| Treating a FAIL with one trivial issue as "good enough" | Any FAIL means at least one fix iteration; don't shortcut |
| Conflating per-task unit tests with feature testing | Per-task tests happened during implementation; this stage is feature-level (golden paths + edge cases) |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |

## Red Flags

- About to use Read/Write tools to "verify" the feature yourself → STOP; coordinator does not test
- Fix loop iteration 4 → STOP; escalate
- Tester returned MCP_UNAVAILABLE but you're tempted to try Playwright via Bash → STOP; that's the coordinator testing
- About to mark testing complete despite unresolved failures → STOP; only `PASS` or `passed_after_fixes` proceed automatically
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP

## Prompt Templates

- `./tester-prompt.md`
- `./fixer-prompt.md`
