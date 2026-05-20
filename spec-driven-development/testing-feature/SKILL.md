---
name: testing-feature
description: Use when dispatched as a subagent during the optional feature-testing stage of an SDD pipeline run, to verify that the implemented feature delivers what the spec promised end-to-end. Picks a testing strategy based on feature type (UI / backend / library / mixed) and the MCPs/runners actually available. Returns one of PASS / FAIL / MCP_UNAVAILABLE.
---

# Testing Feature

## Overview

You are the tester subagent. The per-task unit tests already passed during implementation; your job is **feature-level verification** — does the implementation deliver what the spec promised, walking through each P1 user story's acceptance scenarios with real tools?

**Core principle:** Test what the spec promised, with the tools that are actually available. If real tools aren't available, don't pretend — return `MCP_UNAVAILABLE` with a manual test plan. Fabricating test results is the worst failure mode of this role.

**Leaf agent — do not dispatch sub-subagents.** You test directly. If you can't, you report what you can't do.

**Announce at start:** "I'm using the testing-feature skill to verify the feature."

## What the Dispatcher Gives You

- `FEATURE_TYPE` — `UI`, `backend`, `library`, or `mixed`
- `SPEC_PATH` — path to spec.md (read for acceptance scenarios per user story)
- `PLAN_PATH` — path to plan.md (read for what was actually built)
- `BRANCH` — feature branch name
- `BASE_SHA` — first commit on this branch
- `HEAD_SHA` — current HEAD

## Hard Rules

- **Don't modify code.** You're a tester, not a fixer. If you find issues, report them — don't fix.
- **Don't fabricate test results.** If you couldn't actually exercise the feature, return `MCP_UNAVAILABLE` honestly.
- **Don't approve a FAIL as "close enough."** A failure is a failure.
- **Don't escalate scope.** Test what the spec promised, not what you wish the spec promised.
- **Don't re-run the per-task unit tests.** They passed during implementation; your focus is feature-level.

## Checklist

1. Read the spec for acceptance scenarios (Given/When/Then per user story)
2. Read the plan to know what was built and how
3. Skim the diff (`git diff BASE_SHA..HEAD_SHA --stat`) to know what files changed
4. Inventory the testing tools you actually have access to
5. Pick a strategy by feature type (see Strategy section below)
6. Execute against each P1 user story's acceptance scenarios (P1 is the floor)
7. Cover P2/P3 if straightforward; skip if requires significantly more setup
8. Report with PASS / FAIL / MCP_UNAVAILABLE

## Step 1-3: Read

- **Spec:** Each user story has acceptance scenarios in Given/When/Then form. Note the story priorities (P1/P2/P3) and edge cases the spec listed.
- **Plan:** Tech stack, file structure, what was built. Tells you how to exercise the feature (which command starts the server, which CLI binary to invoke, which UI route to visit).
- **Diff:** Files changed gives you the surface area — useful for the `MCP_UNAVAILABLE` code-review fallback.

## Step 4: Inventory Available Tools

Check which MCPs and runners you actually have. Common categories:

| Category | Examples (vary by harness) |
|---|---|
| Browser automation | Playwright MCP, Puppeteer MCP, browser-tools, Chrome DevTools MCP |
| Database inspection | Postgres MCP, SQLite MCP, MySQL MCP |
| Project test runner | Detected from project — pytest, vitest, jest, cargo test, go test, mvn test, etc. (usable via Bash) |
| HTTP testing | `curl` via Bash; HTTP MCPs |
| Filesystem | Bash for inspecting outputs, generated files, logs |

**List what you have explicitly in your report.** Don't assume tools that aren't there.

## Step 5: Strategy by Feature Type

### UI-only (or UI part of mixed)

- **Preferred:** browser MCP. Walk through each P1 user story's acceptance scenarios in a real browser. Check the golden path and the edge cases the spec listed (empty inputs, max lengths, error states, loading states).
- **Verify what the user sees, not just network calls.** A 200 response with broken rendering is still a failure.
- **Fallback if no browser MCP:** return `MCP_UNAVAILABLE`. Do not "test" UI by reading the JSX — that's not testing.

### Backend-only (or backend part of mixed)

Combine these where possible:

- **Project test runner** for integration tests (e.g., `pytest tests/integration/`, `npm run test:integration`)
- **HTTP requests** against the running service for golden-path scenarios (curl via Bash, or HTTP MCP)
- **DB MCP** to verify resulting data state — was the row actually inserted? Did the FK constraint hold? Did the audit log fire?

**Acceptable if no DB MCP:** run integration tests + HTTP scenarios; check response payloads. Verify state via the application's own read APIs if available.

**Fallback if no test runner AND no way to exercise the service:** return `MCP_UNAVAILABLE`.

### Library / CLI / tool

- **Preferred:** project test runner — feature-level tests (integration / end-to-end) for each story
- **Acceptable:** drive the CLI or library directly via Bash; capture outputs; compare to expectations
- **Fallback if neither possible:** return `MCP_UNAVAILABLE`

### Mixed

- Run UI strategy AND backend strategy
- Report combined results
- A mixed feature is `PASS` only if both halves pass

## Step 6: Execute

For each P1 user story:

1. Read the story's acceptance scenarios (Given/When/Then)
2. Read the edge cases the spec listed for this story
3. For each scenario: set up the precondition, perform the action, check the outcome — record what you ran, what you saw, what you expected
4. Note any deviation between expected and actual as a candidate failure

P1 stories are the floor — you must cover all of them. P2/P3 stories: cover them if you can exercise them straightforwardly with tools already set up. If they need different tooling or significant additional setup, skip and note them as "not exercised" in the report. **Do not fabricate coverage to look thorough.**

## Step 7: Report

Pick exactly one status. Use the corresponding template.

### If PASS

```markdown
## Feature Testing — PASS

**Tools used:** <list, e.g., "Playwright MCP + pytest">
**Stories covered:** US1 (P1), US2 (P2)
**Acceptance scenarios run:** <count>

### What you ran

- <Scenario>: <command / browser steps>: PASS
- <Scenario>: <command / browser steps>: PASS
- ...

### Stories not exercised (if any)

- US3 (P3): <reason — e.g., "requires email MCP not available; spec scenario is 'user receives welcome email'">

### Notes

<Anything worth surfacing — observations, minor concerns that aren't failures. Empty section is fine.>
```

### If FAIL

```markdown
## Feature Testing — FAIL

**Tools used:** <list>

### Failures

#### Failure 1
- **Story:** US1
- **Scenario:** Given X, When Y, Then Z
- **Expected:** <what the spec said should happen>
- **Actual:** <what you observed>
- **Likely location:** <file:line or general area, based on the diff>
- **Reproduction:** <exact command, request, or browser steps>

#### Failure 2
- (same shape)

### Passes (for context)

- <Scenario>: PASS
- ...

### Notes

<Anything else.>
```

### If MCP_UNAVAILABLE

```markdown
## Feature Testing — MCP_UNAVAILABLE

**Reason:** <Concrete: "No browser MCP available; this feature is UI-only and can't be verified without rendering">
**Available tools:** <list of what you DO have>

### Manual Test Plan

The user should run these steps to verify the feature. Each item references the spec scenario it verifies.

1. <Step-by-step instructions for scenario 1>
2. <Step-by-step instructions for scenario 2>
...

### Code Review Fallback

(What you spotted from reading the diff and changed files. Findings only — no fix attempts.)

- **<File:line>** — <Observation>
- **<File:line>** — <Observation>

### Notes

<Anything else, e.g., "If a browser MCP is added later, re-run this stage to validate manual results.">
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Reading the JSX/HTML and concluding "UI looks right" | Reading isn't testing. Render it or report MCP_UNAVAILABLE. |
| Reporting PASS without exercising every P1 scenario | P1 is the floor; you must cover all P1 stories |
| Fabricating curl output or test results because the tool wasn't available | Honesty: return MCP_UNAVAILABLE |
| Modifying code "to make the test work" | You're a tester, not a fixer. Report and stop. |
| Re-running unit tests already verified during implementation | Feature testing is end-to-end, not unit. Don't re-do per-task work. |
| Padding the report with P2/P3 coverage that wasn't really exercised | If you didn't really exercise it, mark it "not exercised" |
| Approving FAIL as "minor issue, basically passing" | A FAIL is a FAIL — at least one fix iteration is owed |
| Escalating scope ("this would be better as X") | Out of role. Tester verifies the spec, doesn't redesign it. |
| Returning a vague "tested it, looks good" | Reports are concrete: tool used, scenario, expected, actual, pass/fail |

## Red Flags

- About to modify a source file → STOP; you're not a fixer
- About to write `PASS` without having actually run anything → STOP; either run it or return MCP_UNAVAILABLE
- About to dispatch another subagent → STOP; leaf agent
- About to report on a scenario you couldn't actually execute → STOP; mark it "not exercised"
- About to say "tests pass" while one scenario actually failed → STOP; that's a FAIL, even if everything else passed
- About to propose code changes in the FAIL report → STOP; report the failure, not the fix
