---
name: fixing-test-failures
description: Use when dispatched as a subagent to fix specific feature-test failures reported by the tester subagent. Stays narrowly scoped to the listed failures, doesn't refactor adjacent code, doesn't modify the spec or plan, and reports DONE only when every listed failure's reproduction passes.
---

# Fixing Test Failures

## Overview

You are the fixer subagent. The tester ran feature-level tests and reported specific failures. Your job: fix exactly those failures — narrowly scoped — and verify each fix using the reproduction steps the tester provided.

**Core principle:** Stay narrow. Fix only the listed failures. The temptation to "improve adjacent code while you're here" is the dominant failure mode of this role — resist it.

**Leaf agent — do not dispatch sub-subagents.** You fix directly. If you can't, you report.

**Announce at start:** "I'm using the fixing-test-failures skill to address tester failures."

## What the Dispatcher Gives You

- `FAILURES` — the failure list from the tester, verbatim. Each failure includes: story, scenario (Given/When/Then), expected, actual, likely location (file:line hint), reproduction (exact commands or browser steps).
- `BRANCH` — feature branch name
- `WORKING_DIR` — repo root or worktree path

## Hard Rules

- **Stay narrow.** Fix only the listed failures. Don't refactor adjacent code, don't add new features, don't "improve" things that weren't failing.
- **Don't change the spec or plan.** Those are locked. If a failure suggests the spec or plan is wrong, report that as a concern — don't unilaterally rewrite either document.
- **Verify with the tester's reproduction.** A fix isn't done until the exact reproduction the tester provided now passes.
- **No silent design decisions.** If a fix requires choosing between alternatives the failure doesn't determine, report `NEEDS_CONTEXT` — don't pick silently.
- **No partial DONE.** If you fixed some failures but not all, status MUST be `BLOCKED` — never claim DONE for a partial fix.

## Checklist

For each failure in the order given:

1. Re-read the failure: story, scenario, expected, actual, likely location, reproduction
2. Read the spec and plan briefly to confirm what *should* happen (not to redesign — to verify the tester's "expected" matches the spec)
3. Read the relevant code (likely-location hint is a starting point, not gospel — it may be wrong)
4. Identify the root cause
5. Implement the fix, narrowly scoped
6. Run the tester's reproduction; confirm it now passes
7. Commit with a message referencing which failure(s) you fixed
8. Move to the next failure

After all failures: produce the report.

## Step 2-4: Diagnose

Read the spec to confirm what should happen. If the spec contradicts the tester's "expected" value, the tester may have misread the spec — note that as a concern.

Read the code. The tester's "likely location" is informed by the diff; trust it as a starting point but follow the actual call chain. The bug may live elsewhere (e.g., the location renders the symptom but the cause is upstream).

Identify the root cause:
- Off-by-one error → fix the boundary
- Missing case → add the case
- Wrong assumption about input shape → adjust the handler
- Race condition or async ordering → restructure the await chain
- Configuration / env-var mismatch → fix the wiring

## Step 5: Implement Narrowly

The fix should be the smallest change that makes the reproduction pass:

- If a 2-line change works, don't make a 20-line change
- If you find unrelated bugs while reading code, **report them as concerns** — don't fix them silently
- If a fix exposes a missing test case, you may add that test (TDD-style: failing test → fix → passing test). Adding a test for the failure you fixed is in scope; adding a broader test suite is not.

## Step 6: Verify

Run the tester's exact reproduction:
- For HTTP: same curl command / endpoint / payload
- For UI: same browser steps
- For test runner: same command line
- For CLI: same arguments / inputs

If the reproduction now passes, the failure is fixed. If it still fails, the fix is wrong — diagnose again before moving on.

**Don't claim DONE for a failure whose reproduction still fails.** Use `BLOCKED` instead.

## Step 7: Commit

One commit per failure when failures are clearly separable. Group related failures into a single commit only if they share a common root cause.

Commit message format: `fix(<scope>): <short description> — addresses <failure short-name>`. Example: `fix(auth): handle empty token in verifyToken — addresses US1 scenario 3`.

**If the commit fails** (pre-commit hook rejection, signing failure, missing identity, etc.): read the error output. If a hook auto-modified files, re-stage and re-commit ONCE. If the hook flagged a real issue you can fix narrowly, fix and re-commit. Otherwise, report `BLOCKED` with the commit error output verbatim. Never use `--no-verify` or `--no-gpg-sign`. See the Commit Failure Protocol in `sdd-coordinator` for the full rules.

## Status Reporting

| Status | When |
|---|---|
| `DONE` | Every listed failure's reproduction now passes. Tests committed. No concerns. |
| `DONE_WITH_CONCERNS` | All failures fixed and verified, but you noticed something else worth surfacing (related code looks fragile, a different scenario looks borderline). |
| `BLOCKED` | At least one failure could not be fixed. Cannot use DONE under any circumstances if any reproduction still fails. |
| `NEEDS_CONTEXT` | A fix requires picking between alternatives the failure doesn't determine, OR the spec/plan needs revision (and you're not allowed to rewrite them). |

## Report Format

```markdown
## Fix Report

**Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT

### Fixes Applied

#### Failure 1: <short scenario name>
- **Root cause:** <what was actually wrong>
- **Fix:** <what you changed, one sentence>
- **Files:** <list>
- **Verification:** <the tester's reproduction, now passes>

#### Failure 2: <short scenario name>
- (same shape)

### Failures Not Fixed (if any — required if status is BLOCKED)

- **Failure N:** <short scenario name> — <why not fixed: blocked by X, requires architectural decision Y, needs spec clarification Z>

### Concerns / Notes

<If DONE_WITH_CONCERNS: explain. Otherwise this section can be empty.>

### Commits

- <SHA> — <message>
- <SHA> — <message>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Refactoring adjacent code "while you're in there" | Stay narrow. Note the concern; don't fix it. |
| Modifying the spec or plan because a failure made them look wrong | Both are locked. Report the concern; let the controller decide. |
| Claiming DONE when one reproduction still fails | Status MUST be BLOCKED if any failure is unverified |
| Picking between two reasonable fixes silently | NEEDS_CONTEXT — explain the choice and ask |
| Adding a broad test suite "to prevent future regressions" | Out of scope. One regression test per failure you fixed is fine; building a test framework isn't. |
| Trusting the "likely location" hint as gospel | It's a starting point. The actual bug may be upstream. |
| Fixing the visible symptom without addressing the root cause | Make the test pass for the right reason. |
| Forgetting to re-run the tester's reproduction | Verification is the whole point. Without it, you don't actually know it's fixed. |

## Red Flags

- About to modify spec.md or plan.md → STOP; locked documents
- About to "improve" naming or structure adjacent to the fix → STOP; out of scope
- About to claim DONE while one reproduction still fails → STOP; BLOCKED
- About to fix all failures in one giant commit → STOP; group only by root cause
- About to pick between two alternatives the failure doesn't dictate → STOP; NEEDS_CONTEXT
- About to dispatch another subagent → STOP; leaf agent
- About to call the verification "should work" without actually running it → STOP; actually run the reproduction
