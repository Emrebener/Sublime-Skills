---
name: reviewing-plans
description: Use when dispatched as a subagent to review a plan.md produced by the SDD pipeline. Returns a structured findings report on whether the plan is implementable as-is; does NOT modify files.
---

# Reviewing Plans

## Overview

Independent fresh-eyes review of an implementation plan before per-task execution begins. Focused on whether a per-task implementer subagent could actually execute the plan without getting stuck or making decisions on the fly.

**Core principle:** Approve unless there's a serious gap that would block or mislead the implementer. Restraint matters.

**Operating mode:** STRICTLY READ-ONLY. Do not modify files.

**Announce at start:** "I'm using the reviewing-plans skill to review the plan."

## Hard Gates

- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.

## What You Get From the Coordinator

The dispatch prompt includes:

- `PLAN_PATH` — absolute path to the plan file
- `SPEC_PATH` — absolute path to the spec it's based on
- `CONTEXT_FILES` — list of project context files (constitution, ADRs, architecture, glossary)
- `REVIEW_FOCUS` (optional) — "first-pass" or "second-pass — focus on X"

## Checklist

1. Read the spec
2. Read the plan
3. Read all listed context files
4. Run the detection passes (Detection section)
5. Assign severity
6. Produce the structured report

## Detection Passes

### A. Spec Coverage

- Every FR-### in the spec has at least one task implementing it
- Every story in the spec has a Phase that covers it end-to-end
- Every SC-### has a task that demonstrates the criterion (typically a test)
- No FR-### or SC-### is referenced by a task that doesn't actually serve it (loose `**Requirements:**` tagging)

### B. Placeholders

- "TBD", "TODO", "implement later", "fill in details", "add appropriate error handling", "add validation"
- "Write tests for the above" without actual test code
- "Similar to Task N" instead of repeating the code
- Steps that describe what to do without showing how (code steps without code blocks)
- References to functions, types, properties, or methods not defined in any task and not present in the existing codebase

### C. Type / Name / Path Consistency

- Function/method/property names match across tasks
- Type signatures are consistent (a function declared with one signature in T003 isn't called with a different one in T007)
- File paths used in later tasks match what earlier tasks created
- Import paths actually work given the file structure

### D. TDD Discipline

- Each non-[NO-TDD] task has the Red-Green-Refactor steps (failing test → run-and-see-fail → minimal implementation → run-and-see-pass → commit)
- [NO-TDD] markers have a justification line whose category matches one of the allowed labels (see `writing-plans` skill's [NO-TDD] Criteria section): `docs-only`, `config-only`, `asset-addition`, `dependency-bump`, `mechanical-rename`, `lint-only`
- **[NO-TDD] misuse is CRITICAL**: if a `[NO-TDD]` task involves logic changes, bug fixes, or refactors that could affect behavior, that's a CRITICAL finding regardless of how clever the reason sounds
- Tests are concrete (real assertions, not mocked-everything tests)
- "Expected: FAIL" messages match what would actually be observed (e.g., "Cannot find module" makes sense before the file is created)

### E. Parallel [P] Correctness

- `[P]`-marked tasks within the same phase don't share files
- `[P]` tasks don't depend on each other's outputs
- `[P]` is genuinely concurrent-safe (no shared mutable state, no order-dependent setup)

### F. Story Independence (MVP-first)

- Phase 3 (US1) alone produces a working, testable increment — not "works only if Phase 4 also runs"
- Each subsequent story phase is an additive increment
- The Final Polish phase is genuinely polish, not load-bearing for any individual story

### G. Constitution / ADR Alignment

- Tasks comply with constitution principles (if any)
- Tasks reflect the ADRs that govern the choices in this feature
- No task silently contradicts a settled ADR

### H. Granularity

- Steps are bite-sized (2-5 minutes each), not multi-hour blocks
- Tasks don't span more than ~2-3 files unless the change is genuinely one logical unit
- A task hard to read in one screen is too big — flag it

## Severity Assignment

| Severity | When |
|---|---|
| **CRITICAL** | Spec coverage gap (an FR has no task), placeholder in a code step, type inconsistency that would cause implementation failure, constitution violation, story isn't actually independent |
| **HIGH** | TDD steps missing or malformed, [P] marker on tasks that share files, [NO-TDD] without justification, ADR contradiction without acknowledgment |
| **MEDIUM** | Granularity concern (task too big), missing traceability tag, expected-failure message likely wouldn't match reality |
| **LOW** | Style/wording, minor redundancy across tasks, suggestion to clarify a step that's already clear enough |

CRITICAL and HIGH must be addressed before approval. MEDIUM/LOW are advisory.

## Calibration Rule

**Approve unless there is at least one CRITICAL or HIGH finding.**

A plan with only MEDIUM/LOW findings should be approved. Don't manufacture HIGH-severity issues to look thorough.

## Output

```markdown
## Plan Review

**Status:** Approved | Issues Found
**Plan:** docs/specs/NNN-<short-name>/plan.md
**Spec:** docs/specs/NNN-<short-name>/spec.md
**Reviewer focus:** first-pass | second-pass — <focus>

### Spec Coverage

| FR | Covered by | Notes |
|---|---|---|
| FR-001 | T003, T005 | ✓ |
| FR-002 | — | **GAP** |
| FR-003 | T007 | ✓ |

Coverage: <N>/<M> FRs covered

### CRITICAL

(Empty if none.)

- **[Task TNNN]** <Issue>. <Why it blocks implementation.> <Suggested resolution.>

### HIGH

(Empty if none.)

### MEDIUM (advisory)

### LOW (advisory)

### Strengths

- <One or two notable strengths.>

### Summary

<2-3 sentences. Headline concerns in priority order if Issues Found; what's strong + one nudge if Approved.>
```

## What NOT to do

- Don't rewrite the plan. Suggest, don't implement.
- Don't flag style preferences as issues.
- Don't approve a plan with unresolved CRITICAL findings.
- Don't read implementation code (the plan hasn't been implemented yet).
- Don't dispatch sub-subagents.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Approving when an FR is uncovered ("close enough") | Spec coverage gaps are CRITICAL — never let them through |
| Missing inconsistent function names across tasks | Read names across tasks explicitly; mismatches are easy to miss otherwise |
| Treating granularity issues as critical | Granularity is MEDIUM unless it makes a task literally unexecutable |
| Flagging every `[P]` as suspect | Only flag when the tasks actually share files or have ordering deps |
| Spending review time on the prose around tasks rather than the tasks themselves | The tasks are the contract; prose is secondary |

## Red Flags

- About to write findings without having Read the constitution + ADRs from `CONTEXT_FILES` → STOP; Detection Pass G (Constitution / ADR Alignment) is CRITICAL-severity and you'll miss it
- About to skip the spec-coverage table — STOP; that table is the most concrete check this review does
- About to flag 10+ findings on a normal-sized plan → STOP and re-calibrate
- Spotted a placeholder ("TBD", "implement later") in a task code step but flagged it as MEDIUM → it's CRITICAL; the implementer cannot proceed past it
- About to modify the plan file → STOP; you are read-only. Suggest changes only.
- About to dispatch your own sub-subagent → STOP; leaf reviewer, no nesting
- About to read implementation code (the plan hasn't been executed yet) → STOP; review the plan against the spec
