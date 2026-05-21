# Skills Reference

The SDD family is 21 skills coordinated by `sdd-coordinator`. The project-bootstrap family is a separate 6-skill set used to set up `.sdd/config.yml` and project conventions (lives at `project-bootstrap/`, outside the SDD pipeline). Both families share 6 scripts under `spec-driven-development/scripts/` (`discover-context.sh`, `get-config-value.sh`, `validate-config.sh`, `validate-spec.sh`, `validate-plan.sh`, `validate-handoff.sh`) and a canonical state schema (`state-schema.md` + `state-schema.json`). This document is the per-skill reference: what it does, when it runs, what it reads, what it writes, and how it interacts with the rest of each family.

## Quick map by role

**Orchestration:**
- `sdd-coordinator` — entry point; state machine + dispatcher
- `inspecting-state` — read-only state inspection

**Workflow stages (in pipeline order):**
- `preflight-checks` — Stage 0
- `discovering-requirements` — Stage 1
- `writing-specs` — Stage 2
- `reviewing-specs` — Stages 3, 4 (subagent)
- `grilling-specs` — Stage 5
- `maintaining-adrs` — Stage 6 (subagent)
- `receiving-review-findings` — Stages 3, 4, 9, 10 (inline)
- `writing-plans` — Stage 8
- `reviewing-plans` — Stages 9, 10 (subagent)
- `implementing-plans` — Stage 12 (orchestrates per-task subagents)
- `implementing-task` — Stage 12 (loaded by implementer subagents)
- `reviewing-task-compliance` — Stage 12 (loaded by spec-compliance reviewer subagent)
- `reviewing-task-quality` — Stage 12 (loaded by code-quality reviewer subagent; also used for final review)
- `testing-implementation` — Stage 13 (orchestrates tester + fixer subagents)
- `testing-feature` — Stage 13 (loaded by tester subagent)
- `fixing-test-failures` — Stage 13 (loaded by fixer subagent)
- `generating-handoff` — Stage 14 (subagent)
- `maintaining-memory-file` — Stage 15 (subagent)
- `finishing-sdd` — Stage 16

**Bootstrap (outside the SDD family — see `project-bootstrap/` directory):**
- `bootstrapping-project` — one-time project setup coordinator
- `discovering-constitution` / `discovering-architecture` / `discovering-glossary` / `discovering-domain-model` / `discovering-design` — per-artifact inline conversational skills (loaded into the coordinator's context, not dispatched)

**Shared scripts:**
- `discover-context.sh` — find project convention files; reads paths from `.sdd/config.yml`
- `get-config-value.sh` — read a single scalar value from `.sdd/config.yml`
- `validate-config.sh` — validate `.sdd/config.yml` structure + path resolution (used by both bootstrap and SDD coordinator)
- `validate-spec.sh` — schema-check a spec.md (incl. duplicate FR/SC ID detection)
- `validate-plan.sh` — schema-check a plan.md (incl. duplicate T### detection)
- `validate-handoff.sh` — schema-check a handoff doc (incl. unredacted-secret patterns)

**Canonical state schema:**
- `state-schema.md` — human-readable state file schema (fields, ownership, lifecycle)
- `state-schema.json` — machine-readable JSON Schema Draft 2020-12

---

## sdd-coordinator

**Type:** Orchestrator (entry point)
**Loaded:** by the user (via the Skill tool) at the start of every SDD session
**Stage:** drives all 16 stages

**Purpose:** The single entry point. Reads `.sdd/config.yml`, runs `inspecting-state`, decides whether to start fresh or resume, then walks the pipeline. Loads phase-skills inline when they're inline-driven; dispatches subagents in fresh context when they're subagent-driven. Updates the state file at every stage boundary.

**Key rules:**
- ALWAYS runs `inspecting-state` first on every invocation
- Never advances past a user-approval gate (Stages 7, 11) without explicit user yes
- Never auto-skips optional stages (4, 5, 10, 13) — always asks
- Never tests the feature itself when `testing-implementation` reports MCP_UNAVAILABLE
- State updates are atomic and happen at stage boundaries only

**Reads:** `.sdd/config.yml`, output of `inspecting-state`, every artifact the pipeline produces
**Writes:** state file (atomic), commits at stage transitions, ADR status flips on approval

**Common mistakes the skill warns against:**
- Skipping the resume check at session start
- Updating state mid-stage
- Doing phase-skill work inline instead of loading the phase-skill or dispatching a subagent
- Multiple implementer subagents in parallel (sequential only)

---

## inspecting-state

**Type:** Read-only utility
**Loaded:** by the coordinator at the start of every invocation; directly by the user when they want to check status
**Stage:** entry / on-demand

**Purpose:** Single source of truth for "what SDD state currently exists in this repo." Finds all `<spec_dir>/*/state.json` files (honoring `paths.spec_dir`), validates each against the canonical schema (`scripts/state-schema.json`), checks git for pre-state-file interruption signals, and reports.

**Key rules:**
- STRICTLY read-only. Does not modify any file.
- Does NOT decide "resume vs start fresh" — only reports facts. The coordinator interprets.
- Does NOT dispatch subagents.

**Pre-state interruption detection** (tightened to eliminate false positives): flagged ONLY when all three are true — zero active state files exist anywhere, current branch matches an SDD pattern (`feat/*` or `fix/*`), and the branch isn't `main`/`master`/`develop`/`release/*`/`hotfix/*`. This avoids firing on unrelated branches like `chore/cleanup` or `wip/anything`.

**Reads:** all state files (validated against `state-schema.json`), git branch info
**Writes:** nothing (returns a report)

**Report format:**

```markdown
## SDD State Report
**Active runs found:** N
**Pre-state interruption suspected:** yes|no
**Current branch:** ...

### Run 1: <feature_id>
- Path, short_name, started, updated, branch, **branch match with current (yes|no)**, current_stage, stages_completed/skipped, tasks summary, test_status, ADR count, validation status, preflight worktree

### Pre-State Interruption Signals (if applicable)

### Summary
<One sentence — what coordinator/user should do next, including the branch-match disposition>
```

The "Branch match with current" field per run lets the coordinator route correctly when current branch and state.branch disagree (per the coordinator's resume decision table).

**User invocation:** "Use the inspecting-state skill to show me what SDD runs are in progress."

---

## preflight-checks

**Type:** Phase skill (inline)
**Loaded:** by the coordinator at Stage 0
**Stage:** 0

**Purpose:** Verify the repo is in a fit state to start an SDD pipeline run. **Aborts on any problem.** Does not clean up; the user fixes things manually.

**Behavior matrix:**

| Condition | Action |
|---|---|
| Dirty working tree | ABORT — `dirty_working_tree` |
| Clean + on `main`/`master` | Create feature branch, proceed |
| Clean + on feature-like branch + matching state file | Resume on this branch |
| Clean + on feature-like branch + no matching state | ABORT — `ambiguous_branch` |
| Clean + on `develop`/`release/*`/`hotfix/*` | ABORT — `protected_branch` |
| Clean + on any other branch | ABORT — `ambiguous_branch` |
| Worktree config'd but creation fails | ABORT — `worktree_creation_failed` |

**Key rules:**
- No `git commit`, no `git stash`, no `git clean`, no `git restore`, no `git checkout` to escape an inappropriate branch. Just abort.
- Branch naming default: `feat/<short-name>` (or `fix/<short-name>` for bug fixes). Overridable via `.sdd/config.yml` → `preflight.branch_pattern`.

**Reads:** git state
**Writes:** at most one new branch via `git checkout -b`; possibly a worktree
**State file:** does not yet exist; outputs (branch, worktree path, original branch) are returned to the coordinator for in-memory holding

**Returns on success:**

```
Preflight complete.
- Branch: feat/user-auth (created from main) | (resumed)
- Original branch: main
- Worktree: none | .worktrees/feat-user-auth
- Working tree: clean
- Status: ready
```

**Returns on abort:**

```
Preflight aborted.
- Status: aborted_at_preflight
- Reason: dirty_working_tree | ambiguous_branch | protected_branch | worktree_creation_failed | user_declined
- Message: <user-facing message>
```

---

## discovering-requirements

**Type:** Phase skill (inline; conversational)
**Loaded:** by the coordinator at Stage 1
**Stage:** 1

**Purpose:** Interview the user to build shared understanding of what's being built. Output is in-memory, not on disk. `writing-specs` renders it next.

**Conversation rules:**
- One question per message (no compound questions)
- Multiple choice with a recommended answer preferred over open-ended when there are clear alternatives
- Walk through dimensions: purpose, users, scope (in/out), success criteria, key entities, edge cases, constraints, integration
- For non-obvious major decisions, propose 2-3 alternatives with reasoning; user picks
- Skip dimensions already obvious from the user's initial description
- Scope check: surface decomposition if the request describes multiple subsystems

**Hard gate:** the skill writes NOTHING to disk. Output is the coordinator's understanding.

**Reads:** project context (via `discover-context.sh`), all that's relevant
**Writes:** nothing

**Section-by-section approval:** at the end, the skill summarizes back in sections (goal, users, scope, success, entities, edge cases, decisions). User approves each before moving on.

**Common mistakes:**
- Writing partial spec content during this stage (out of scope; writing-specs handles it)
- Open-ended questions when MCQ would work
- Combining multiple questions into one message
- Re-asking what an existing ADR already decided

---

## writing-specs

**Type:** Phase skill (inline; mechanical)
**Loaded:** by the coordinator at Stage 2
**Stage:** 2

**Purpose:** Render the agreed understanding from Stage 1 into the `spec.md` artifact. No more user interaction in this stage.

**Output structure** (full template in [artifacts.md](artifacts.md)):
- Required: Header, Goal, User Stories (P1/P2/P3 with Given/When/Then or EARS), Functional Requirements (FR-###), Success Criteria (SC-###), Edge Cases, Assumptions, Out-of-Scope
- Optional: Key Entities, Open Questions, References

**Hard gates:**
- No new design decisions (gaps → return to discovery)
- No implementation details (file paths, code, task lists)
- No Mermaid, C4, PlantUML, or ASCII diagrams

**State file:** initialized here. Writes `current_stage: "spec_writing"` and `stages_completed: ["preflight", "discovering"]`. Coordinator advances after the skill returns.

**Validator invoked:** `scripts/validate-spec.sh`. Runs as first sub-step of Step 5 self-review. Must pass before the skill reports back.

**Filename:** `docs/specs/NNN-<short-name>/spec.md` where `NNN` is the next sequential 3-digit number.

---

## reviewing-specs

**Type:** Subagent skill (dispatched in fresh context)
**Loaded:** by the dispatched subagent at Stages 3, 4
**Stage:** 3 (mandatory first-pass), 4 (optional second-pass)

**Purpose:** Independent fresh-eyes review of the spec before plan writing. Read-only.

**What the dispatched subagent gets from the coordinator:**
- `SPEC_PATH`
- `CONTEXT_FILES` — constitution, ADRs, architecture, glossary, etc.
- `REVIEW_FOCUS` — "first-pass" or "second-pass — focus on X"

**Detection passes:**
- **Completeness** — placeholders, missing sections, untraceable FRs
- **Internal consistency** — contradictions between sections
- **Clarity / testability** — vague adjectives without quantification, ambiguous wording
- **Constitution / ADR alignment** — violations are CRITICAL
- **Scope** — multiple subsystems crammed together → recommend decomposition
- **YAGNI** — capabilities not requested
- **Vocabulary** — domain-noun drift, synonym proliferation

**Severity rubric:**

| Severity | Examples |
|---|---|
| CRITICAL | Constitution violation, contradiction between sections, requirement so ambiguous it would lead to wrong implementation, scope sprawl |
| HIGH | Untestable acceptance scenario, FR with no story, unmeasurable SC, ADR re-litigation without acknowledgment |
| MEDIUM | Vocabulary drift, vague adjective in non-critical requirement |
| LOW | Style/wording, minor redundancy |

**Calibration rule:** approve unless CRITICAL or HIGH findings. Reviewers that flag 10+ findings train coordinators to ignore reviews.

**Output:** structured markdown report (see skill file for the template).

**Hard rules:**
- STRICTLY READ-ONLY
- Don't rewrite the spec; suggest, don't implement
- Don't dispatch sub-subagents (leaf reviewer)

---

## grilling-specs

**Type:** Phase skill (inline; conversational)
**Loaded:** by the coordinator at Stage 5, only if user opted in
**Stage:** 5 (optional)

**Purpose:** Optional bounded stress-test of the spec. Asks scoped, prioritized questions one at a time with recommended answers, and **applies each accepted answer to the spec inline**.

**Why inline (not subagent)?** Interactive multi-turn conversation with the user — subagents can't have that.

**Question categories** (the skill internally prioritizes by impact × uncertainty):
- Goal sharpness
- Story priority rationale
- Acceptance testability
- FR coverage
- SC measurability
- Entity completeness
- Edge case depth
- Constraint rigor
- Integration risk
- Constitution / ADR fit
- Out-of-scope explicitness

**Question format:**
- Multiple choice with recommendation prominent (preferred)
- Short-answer with suggestion (when options don't fit)
- One question per message; the recommendation is always shown

**After each accepted answer:**
1. Append `- Q: ... → A: ...` to the Clarifications log section (created if missing)
2. Apply the substance to the appropriate spec section
3. **Save the spec immediately (atomic write)** — never batch
4. Move to next question

**Stop conditions:**
- User signals done
- All high-impact categories resolved
- Cap reached (default 10; configurable; hard ceiling 20)

**Reads:** spec + project context
**Writes:** updated spec.md (atomic per-answer)

---

## maintaining-adrs

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stage 6
**Stage:** 6 (mandatory; may produce zero ADRs)

**Purpose:** Identify decisions in the spec that warrant new ADRs and write them in the locked format.

**ADR-worthy criteria (ALL must hold):**
- Architectural (touches structure, technology, communication, data flow, security model, deployment)
- A reasonable alternative was considered and rejected (or could have been chosen)
- Reasoning isn't self-evident from the code or spec
- Not already covered by an existing ADR

**What the dispatched subagent gets:**
- `SPEC_PATH`
- `ADR_DIR` — default `docs/adr` (configurable)
- `EXISTING_ADRS` — list of paths (subagent reads them to avoid duplicates)
- `DECISIONS_CAPTURED` — list flagged during discovery as ADR candidates (may be empty)

**Locked ADR format** (see [artifacts.md](artifacts.md) for full template):
- Title with `ADR-NNNN` prefix
- Status (default `Proposed`)
- Date, Spec link, optional Supersedes link
- Context, Decision, Consequences (Positive/Negative/Trade-offs), Alternatives Considered

**Numbering:** sequential across all ADRs, zero-padded 4 digits. Multiple new ADRs from one spec are sequential in order written.

**Supersession:** if a new decision supersedes an existing ADR, the subagent writes the new one with `Supersedes: ADR-NNNN` and updates the older ADR's `Status` to `Superseded by ADR-NNNN`. Both files are touched as a pair.

**Zero ADRs is valid output.** Not every spec needs new ADRs. The subagent returns "0 ADRs created" with a one-sentence reason.

**Status flips to `Accepted`** in Stage 7 when the user approves.

---

## receiving-review-findings

**Type:** Inline skill (process review output)
**Loaded:** by the coordinator after each reviewer subagent returns
**Stages:** 3, 4, 9, 10

**Purpose:** Establishes how the coordinator consumes findings from a spec or plan reviewer. Borrows from superpowers' `receiving-code-review` philosophy.

**Core protocol:**

1. Read ALL findings end-to-end before reacting
2. For each CRITICAL/HIGH:
   - Verify it's real (read the cited section, check against project context)
   - If real and the artifact is wrong → fix
   - If real but a deliberate decision → push back (document in artifact + log in state)
   - If not real → push back with technical reasoning
3. For MEDIUM: fix if trivial; otherwise move to Open Questions or accept
4. For LOW: usually skip
5. If material fixes were made: re-dispatch reviewer (cap at 2 fix iterations before escalating to user)

**Forbidden patterns:**
- "Great point!", "You're absolutely right!", "Thanks for catching that" — all performative; deleted
- Blind implementation without verification
- Silently ignoring a finding (every one gets handled or pushed back)
- Looping past the iteration cap without escalating

**State file impact:**

```json
{
  "reviewer_pushbacks": [
    {
      "stage": "spec_auto_review",
      "finding": "<short identifier>",
      "reason": "<technical reasoning>"
    }
  ],
  "<stage>_review_iterations": <N>
}
```

**Surface to user when:**
- A finding implies decomposition (multiple subsystems)
- A finding contradicts a recent user statement
- 2+ fix iterations have passed without resolution
- A finding needs human judgment

---

## writing-plans

**Type:** Phase skill (inline; mechanical)
**Loaded:** by the coordinator at Stage 8
**Stage:** 8

**Purpose:** Render the approved spec into `plan.md`. Tasks are bite-sized, organized into phases by user story, with TDD steps.

**Output structure** (full template in [artifacts.md](artifacts.md)):
- Required: Header (title, feature ID, spec link, status, goal, architecture, tech stack), File Structure, Phases (Setup, Foundational, story phases in priority order, Polish)
- Each task: `[T###]` ID, optional `[P]`, `[US#]`, file paths, `**Requirements:**` traceability, TDD steps (or `[NO-TDD]` with reason)

**Hard gates:**
- No placeholders ("TBD", "fill in", "similar to Task N")
- No Mermaid/C4/PlantUML/ASCII diagrams
- No references to functions/types/methods not defined in this plan or codebase
- No new design decisions (gaps → return to coordinator)

**[NO-TDD] strict criteria** (see [operations.md](operations.md) for the full list of allowed categories):
- `docs-only`, `config-only`, `asset-addition`, `dependency-bump`, `mechanical-rename`, `lint-only`
- Anything else with logic = TDD required

**Validator invoked:** `scripts/validate-plan.sh`. Runs as first sub-step of Step 6 self-review.

---

## reviewing-plans

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stages 9, 10
**Stage:** 9 (mandatory), 10 (optional)

**Purpose:** Independent review of the plan before implementation. Read-only.

**Detection passes:**
- **Spec coverage** — every FR has at least one task (the output includes a coverage table)
- **Placeholders** — "TBD", "TODO", "similar to Task N", etc.
- **Type / name / path consistency** across tasks
- **TDD discipline** — Red-Green-Refactor steps present; `[NO-TDD]` matches allowed categories (misuse is CRITICAL)
- **`[P]` correctness** — parallel-marked tasks don't share files
- **Story independence** — each story phase produces a working increment standalone
- **Constitution / ADR alignment**
- **Granularity** — tasks bite-sized (2-5 min each)

**Severity rubric:** same shape as reviewing-specs (CRITICAL / HIGH / MEDIUM / LOW with calibration).

**Output:** structured markdown report including a Spec Coverage table — the most concrete check.

**Hard rules:** READ-ONLY, no rewrites, no sub-subagent dispatch.

---

## implementing-plans

**Type:** Phase skill (inline; orchestrates per-task subagents)
**Loaded:** by the coordinator at Stage 12
**Stage:** 12

**Purpose:** Drive the per-task loop. For each task: dispatch implementer subagent → handle status → dispatch spec-compliance reviewer → loop on Issues Found (cap 3) → dispatch code-quality reviewer → loop on Issues Found (cap 3, Minor non-blocking) → mark complete.

**Continuous execution:** no pausing between tasks for human check-in. Only stops on BLOCKED, cap hit, plan-is-wrong, or all-tasks-complete.

**Resume safety:** on entry, the skill reads existing `state.tasks` and merges with the plan's task list — **never overwrites** existing `completed` / `in_progress` statuses. Starts from the first `in_progress` task (re-dispatching from scratch, which is safe since the implementer is a fresh subagent and partial work is either committed or lost) or the first `pending` task if none in-progress. Completed tasks are skipped.

**Per-task state updates:**
- At task start: `tasks[T###]: "in_progress"` (atomic write)
- At task end: `tasks[T###]: "completed"`

**Final review:** after all tasks, dispatch one more code-quality reviewer on the full diff with `TASK_ID=final`. The `reviewing-task-quality` skill has explicit guidance for the final case (cross-cutting concerns, multi-file diff handling). Sets `final_review_completed: true` in state file.

**Prompt templates** (dispatch envelopes alongside the skill — protocols live in dedicated skills):
- `implementer-prompt.md` → calls `implementing-task`
- `spec-compliance-reviewer-prompt.md` → calls `reviewing-task-compliance`
- `code-quality-reviewer-prompt.md` → calls `reviewing-task-quality`

**Subagent statuses handled:**

| Status | Action |
|---|---|
| DONE | Proceed to spec-compliance review |
| DONE_WITH_CONCERNS | If correctness/scope concerns: re-dispatch with concerns appended. If observations only: note and proceed. |
| NEEDS_CONTEXT | Provide context, re-dispatch |
| BLOCKED | Assess and re-dispatch with: more context / more capable model / smaller pieces / escalate to user |

**Sequential dispatch:** NEVER dispatch multiple implementers in parallel (they would conflict).

---

## implementing-task

**Type:** Subagent skill (lightweight protocol)
**Loaded:** by implementer subagents themselves when they start
**Stage:** 12 (during per-task implementation)

**Purpose:** Establish the implementer's protocol — scope discipline, TDD-by-default, status protocol, self-review, commit hygiene.

**Key sections:**

- **Stay In Scope** — concrete in-scope vs out-of-scope examples; resist additions
- **TDD By Default** — Red-Green-Refactor; `[NO-TDD]` handling
- **Status Reporting** — the four statuses with clear criteria
- **Surface Unclear Things Before You Begin** — return `NEEDS_CONTEXT` immediately (don't guess, don't proceed). Format: "What you need / What you tried / What you'd do if forced to guess" — lets the controller answer or re-dispatch.
- **Self-Review Before Reporting** — completeness, quality, discipline, testing
- **Commit Hygiene** — one task = one commit (or a few), Conventional Commits style with task ID
- **If a Commit Fails** — read the error, re-stage once if hook auto-fixed, otherwise BLOCKED; never `--no-verify` / `--no-gpg-sign` / `--force`
- **What Reviewers Will Check** — primer on spec-compliance vs code-quality reviewers
- **Examples of In-Scope vs Out-of-Scope** — concrete cases (TypeScript/JWT example; principles transfer)
- **Common Rationalizations and Why They're Wrong** — table addressing the most common scope-creep traps

**"Your work will be reviewed" priming:** explicit in the Overview and reinforced throughout. Improves output quality measurably.

---

## reviewing-task-compliance

**Type:** Subagent skill (full protocol for the per-task spec-compliance reviewer)
**Loaded:** by the spec-compliance reviewer subagent when it's dispatched
**Stage:** 12 (per task)

**Purpose:** First-stage per-task review. Confirms the implementation matches the task spec exactly — no scope creep, no missing steps, no silent design decisions.

**Inputs the dispatcher provides:** `TASK_ID`, `TASK_TEXT`, `SPEC_PATH`, `PLAN_PATH`, `BASE_SHA`, `HEAD_SHA`. Spec and plan paths are for targeted lookups only.

**The seven checks:**

1. Coverage + Requirements Traceability — every step done; cited FRs actually satisfied
2. Scope Creep — the dominant failure mode (extra options, refactors, defensive code, new abstractions)
3. Tests Present and Meaningful — including TDD verification via commit order
4. Tests Pass — re-run by the reviewer, not trusting the implementer
5. No Silent Decisions — design choices the task didn't make
6. Commit Hygiene — task ID reference, no grab-bag commits
7. Files Touched Match the Task

**Output:** `Approved` or `Issues Found` with categorized findings (Missing / Extra / Scope creep / Test gap / FR not satisfied / Silent decision / Commit hygiene / Files out of scope) + re-run verification + 2-3 sentence summary.

**Lane discipline:** does NOT flag code quality, naming, style, or idiom. Those are the next reviewer's job.

**Hard rules:** READ + re-run tests; never fix the code; leaf reviewer (no sub-subagent dispatch).

---

## reviewing-task-quality

**Type:** Subagent skill (full protocol for the per-task code-quality reviewer)
**Loaded:** by the code-quality reviewer subagent when it's dispatched
**Stage:** 12 (per task, after spec compliance is Approved)

**Purpose:** Second-stage per-task review. Catches code-quality issues that would harm the codebase if merged — assumes the previous reviewer verified scope.

**Inputs the dispatcher provides:** `TASK_ID`, `BASE_SHA`, `HEAD_SHA`. No spec/plan paths needed (not re-checking compliance).

**Six dimensions checked:**

| Dimension | Focus |
|---|---|
| Readability | Naming, function length, nesting, flow |
| Correctness around edges | Nulls, empties, errors, concurrency |
| Idiom | Alignment with the project's existing patterns |
| Security | Injection, deserialization, leaked secrets, missing authz, custom crypto |
| Performance | O(n²), unbounded growth, N+1, missing indexes |
| Maintainability | DRY-within-reason, single responsibility, WHY comments only |

**Severity rubric:**
- **Critical** — must fix; correctness, security, or data integrity
- **Important** — should fix; idiom, readability, real future-pain risks
- **Minor** — could fix; style preferences, small naming improvements

**Style is NEVER Critical.** Minor findings don't block merging.

**Hard rules:** does NOT re-check compliance; does NOT re-run tests; does NOT propose architecture changes; never fixes the code; no filler "Strengths" section; leaf reviewer.

---

## testing-implementation

**Type:** Phase skill (inline; orchestrates tester subagent)
**Loaded:** by the coordinator at Stage 13 (only if user opted in)
**Stage:** 13 (optional)

**Purpose:** Feature-level testing distinct from per-task unit tests. Dispatches a tester subagent that picks a strategy based on available MCPs and feature type.

**Result statuses from the tester subagent:**

| Status | Coordinator action |
|---|---|
| PASS | Update state, advance to Stage 14 |
| FAIL | Dispatch fixer subagent with failures; re-test; cap 3 iterations before escalating |
| MCP_UNAVAILABLE | Surface manual test plan + code review findings to user; **coordinator MUST NOT test itself** |

**Strategy selection (in tester subagent):**
- **UI-only**: browser MCP for golden path + edge cases. Fallback to MCP_UNAVAILABLE.
- **Backend-only**: project test runner + HTTP requests + DB MCP for data verification. Fallback acceptable if test runner exists.
- **Library/CLI**: project test runner + direct CLI invocation.
- **Mixed**: run both UI and backend strategies.

**Prompt templates** (separate files alongside the skill):
- `tester-prompt.md` — dispatch envelope; calls `testing-feature`
- `fixer-prompt.md` — dispatch envelope; calls `fixing-test-failures`

**Coordinator MUST NOT test itself when MCP_UNAVAILABLE.** This rule is repeated in five different places in the skill because it's the highest-risk rationalization. If the tester can't test, the coordinator surfaces to user — doesn't pick up Bash/Playwright/curl itself.

---

## testing-feature

**Type:** Subagent skill (full protocol for the tester subagent)
**Loaded:** by the tester subagent when it's dispatched
**Stage:** 13 (optional)

**Purpose:** Feature-level verification — does the implementation deliver what the spec promised end-to-end? Picks strategy by feature type and available tools.

**Inputs the dispatcher provides:** `FEATURE_TYPE`, `SPEC_PATH`, `PLAN_PATH`, `BRANCH`, `BASE_SHA`, `HEAD_SHA`.

**Strategy selection:**
- **UI-only:** browser MCP for golden path + edge cases; return `MCP_UNAVAILABLE` if no browser MCP
- **Backend-only:** project test runner + HTTP + DB MCP combinations; acceptable to fall back to test runner + HTTP if no DB MCP
- **Library / CLI:** project test runner or direct CLI invocation via Bash
- **Mixed:** both UI and backend strategies

**Tool inventory step:** explicitly lists what's actually available before picking strategy — prevents the "pretend tests passed" failure mode.

**Coverage rules:**
- P1 user stories are the floor (must cover all)
- P2/P3 covered when straightforward; marked "not exercised" otherwise (no fabricated coverage)

**Output:** one of three statuses with structured formats:
- `PASS` — tools used, stories covered, scenarios run, notes
- `FAIL` — per-failure: story, scenario, expected, actual, likely location, reproduction
- `MCP_UNAVAILABLE` — reason, available tools, manual test plan, code-review fallback findings

**Hard rules:** never modify code (you're a tester, not a fixer); never fabricate results; never approve FAIL as "close enough"; leaf agent.

---

## fixing-test-failures

**Type:** Subagent skill (full protocol for the fixer subagent)
**Loaded:** by the fixer subagent when it's dispatched
**Stage:** 13 (during fix loop, on tester FAIL)

**Purpose:** Fix the specific failures the tester reported — narrowly scoped, verified by running the tester's exact reproduction.

**Inputs the dispatcher provides:** `FAILURES` (verbatim from tester), `BRANCH`, `WORKING_DIR`.

**Scope discipline:**
- Fix only listed failures (no adjacent refactors)
- Never modify the spec or plan (report concerns instead)
- Smallest change that makes the reproduction pass

**Per-failure protocol:** re-read failure → confirm against spec → read code → diagnose root cause → implement narrowly → run tester's reproduction → commit referencing failure.

**Status protocol:**

| Status | When |
|---|---|
| DONE | Every reproduction passes; no concerns |
| DONE_WITH_CONCERNS | All fixed and verified; surfacing observations |
| BLOCKED | At least one reproduction still fails (cannot use DONE for partial fixes) |
| NEEDS_CONTEXT | Fix requires picking between alternatives, OR spec/plan needs revision |

**Hard rules:** strict scope discipline; verify with the tester's exact reproduction (the symptom matters); no silent design decisions; never claim DONE for partial fixes; leaf agent.

---

## generating-handoff

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stage 14
**Stage:** 14 (user-prompted, default yes)

**Purpose:** Produce a self-contained handoff document at `docs/handoff/YYYY-MM-DD-<short-title>.md` that lets a fresh agent (or human) continue work without re-reading everything.

**What the dispatched subagent gets:**
- `STATE_PATH`, `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS`, `BRANCH`, `BASE_SHA`, `HEAD_SHA`, `HANDOFF_DIR`

**Handoff structure** (see [artifacts.md](artifacts.md) for full template):
- Quick context (2-3 sentences)
- Source artifacts (references with one-line summaries — NOT duplicates)
- What got built (2-4 paragraphs)
- Build highlights (from git log)
- Test status
- Open concerns
- If you're continuing this work (practical guidance)
- Redactions (note count if any)
- Files not to look at (optional; for low-signal diffs like lockfiles)

**Redaction sweep:**
- OpenAI/Anthropic keys (`sk-...`, `sk-ant-...`)
- AWS keys (`AKIA...`, `ASIA...`)
- GitHub tokens (`ghp_...`, `gho_...`, `ghu_...`, `ghs_...`, `ghr_...`)
- JWT-shaped strings (`eyJ...` 3-part)
- URLs with embedded credentials
- SSH private key markers
- Sensitive env var assignments (`*_SECRET=`, `*_PASSWORD=`, `*_TOKEN=`, `*_KEY=`)
- Generic high-entropy secret literals near `password|secret|token|api_key`

Two-pass scan: keep going until no new redactions surface.

**Validator invoked:** `scripts/validate-handoff.sh`. Critical failures include unredacted secret patterns.

**Hard rules:**
- Do NOT duplicate ADR content (reference + one-line summary)
- Do NOT duplicate large spec/plan sections
- Do NOT modify any file other than the new handoff doc
- Do NOT dispatch sub-subagents

---

## maintaining-memory-file

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stage 15
**Stage:** 15 (user-prompted, default yes; auto-skipped without prompt when no memory file is configured/detected)

**Purpose:** Decide whether the project's agent memory file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`) needs updating based on what this run produced, and if so, update it. Most runs do NOT warrant an update — that's normal.

**Inputs the dispatcher provides:** `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS`, `MEMORY_FILE_PATH` (resolved from config or auto-detect; null = skip), `CHARACTER_LIMIT` (soft cap; default 40000), `EXISTING_CONTENT` (current file text).

**Path resolution** (in coordinator before dispatch):
1. `.sdd/config.yml → memory_file.path` if set (absolute or repo-relative)
2. Auto-detect at repo root: `CLAUDE.md` → `AGENTS.md` → `GEMINI.md` → `.agents.md`; first match wins
3. None found → skip (no failure)

**Decision filter — every candidate update must pass ALL of these:**

| Filter | Pass = keep |
|---|---|
| Would a future agent get this wrong without the line? | yes |
| Stable (won't change next month)? | yes |
| Not already obvious from reading the code? | yes |
| Not already in the memory file? | yes |
| Line shorter than the paragraph that would explain it? | yes |

**Default to drop.** Memory files atrophy from accretion.

**Character budget:**
- Under 90% of cap → safe
- 90-100% → write but warn
- Over 100% → REFUSE; tighten existing content first or omit additions

**Format rules:**
- One line per rule; bullets over prose
- Lead with the verb / rule ("MUST validate inputs via the schema layer")
- Cite ADR/spec for traceability
- No timestamps; no "we recently added X"; no narrative
- Respect existing file structure if it exists; don't reorganize

**Hard rules:** leaf skill (no sub-subagent dispatch); only modify the memory file (never spec/plan/ADRs/state); never duplicate content from other docs (link instead).

**Output statuses:**
| Status | Meaning |
|---|---|
| `updated` | File was written; coordinator commits |
| `no update needed` | Most common outcome; no commit; advance |
| `skipped` | No memory file configured/detected; `memory_file` added to `stages_skipped` |

The skill's SKILL.md includes a Best Practices section on what memory files are for (project conventions, NEVER/MUST rules, canonical vocabulary, pointers), what they're NOT for (changelogs, TODOs, narrative, transient state), healthy size ranges, update cadence, pruning advice, and common anti-patterns to avoid.

---

## finishing-sdd

**Type:** Phase skill (inline; user-interactive)
**Loaded:** by the coordinator at Stage 16
**Stage:** 16

**Purpose:** Close out the SDD run. Verify tests, present 4 options (merge / PR / keep / discard), execute the choice, clean up.

**Pre-finish verification:** run the project test suite one more time. If failures: halt; user must resolve or explicitly override.

**Mode selection** (`.sdd/config.yml` → `finishing.mode`):
- `prompt` (default): interactive menu
- `leave`: no menu; leave branch as-is
- `merge-local`: no menu; merge into base
- `pr`: no menu; push + create PR
- `auto`: pick based on remote and PR command availability

**4 options (when interactive):**

| Option | Action | Worktree cleanup | State file | Branch deletion |
|---|---|---|---|---|
| 1. Merge locally | Checkout base, merge, test merged result | Yes (if we created it) | Deleted | Yes (if config) |
| 2. Push + PR | Push + run PR command | NO (user needs it for iteration) | Deleted | No |
| 3. Keep as-is | Leave everything | No | Kept | No |
| 4. Discard | Typed `discard` confirmation; force-delete branch | Yes | Deleted | Yes (force) |

**Worktree cleanup provenance check:** only cleans up worktrees under `.worktrees/<branch>` whose path matches `preflight.worktree_path` in the state file. Harness-managed worktrees are never touched.

**Hard rules:**
- No `git push --force` anywhere
- No branch deletion without typed confirmation for Discard
- Cleanup respects worktree provenance

---

## project-bootstrap family (outside the SDD pipeline)

Lives in `project-bootstrap/`. Separate skill family from SDD because the purpose (one-time project setup) is distinct from the SDD pipeline's per-feature workflow.

### bootstrapping-project

**Type:** Coordinator (inline; user-interactive)
**Loaded:** manually by the user (NOT by `sdd-coordinator`)
**Stage:** N/A — one-time per-project setup; safe to re-run

**Purpose:** Walk the user through each convention file with deep per-file project analysis, then scaffold `.sdd/config.yml` and the supporting directories.

**Workflow:**
1. Run `discover-context.sh` to see what already exists.
2. For each of constitution → architecture → glossary → domain → design: detect → ask the user (Create if missing; Skip / Extend / Replace if present) → load the matching `discovering-<topic>` skill inline via the Skill tool. Each discovering-X skill handles its own code scan, user conversation, draft, tweak-loop (cap 3), and atomic write internally — the coordinator just records the outcome string and moves to the next file.
3. Create `docs/adr/`, `docs/specs/`, `docs/handoff/` with stub READMEs.
4. Copy `project-bootstrap/scaffolds/config.yml` verbatim to `.sdd/config.yml`.
5. Edit config to reflect reality: any skipped convention file gets its `context.<name>_path` set to `null`.
6. Run `validate-config.sh`; fix-and-retry loop (cap 3) until PASS.
7. Ensure `.sdd/local.yml` is gitignored.
8. Single commit `chore: initialize SDD project context`.

**Reads:** existing project files (via `discover-context.sh` + per-skill reads); EXISTING_CONTENT for extend/replace modes.
**Writes:** opted-in convention files (written atomically by each discovering-X skill); `docs/adr|specs|handoff/README.md` stubs; `.sdd/config.yml`; possibly `.gitignore` entry; one commit.

### discovering-constitution / discovering-architecture / discovering-glossary / discovering-domain-model / discovering-design

**Type:** Inline conversational skills
**Loaded:** by `bootstrapping-project` into its own context via the Skill tool when the per-file loop reaches each slot
**Stage:** N/A

**Purpose:** Deep, focused per-file analysis with sustained user interaction. Each skill performs a silent code scan, announces findings, asks targeted questions about things the code can't reveal, drafts the file, runs a tweak loop (cap 3 iterations), and atomically writes itself. The coordinator just records the outcome string.

| Skill | Reads | User-interaction layer | Produces |
|---|---|---|---|
| `discovering-constitution` | README, CONTRIBUTING, linter/formatter/CI configs, source patterns, security-relevant files | Confirm candidate principles → set MUST/SHALL/SHOULD severity → add intent principles code can't reveal | 3-7 MUST/SHALL/SHOULD principles with one-line rationales each |
| `discovering-architecture` | Top-level dirs, build files, entry points, infra config (Docker/k8s/terraform), `.env.example` | Confirm component grouping → declare out-of-scope → confirm env-var-only integrations → add non-code facts → resolve cardinality | System summary, Components, Runtime topology, Data stores, External integrations, Boundaries (no diagrams) |
| `discovering-glossary` | Source identifiers (class/table/route names), inline definitions in comments, README | Pick which ≤30 terms make the cut → declare aliases / multi-naming → refine definitions during tweak loop | 10-30 alphabetical terms, each ≤2 sentences |
| `discovering-domain-model` | DB schemas/migrations, model/type definitions, test fixtures, state-machine code | Pick which ≤15 entities are load-bearing → confirm lifecycles → resolve cardinality → add workflow exceptions | 3-15 entities with conceptual attributes, relationships (with cardinality), lifecycles (no diagrams) |
| `discovering-design` | Tailwind config, CSS custom properties, theme/token files, `components/`, design-system deps in `package.json` | (Build path) Confirm vibe / theme intent → set color role rules → confirm component vocabulary → state do's-and-don'ts. (Import path) Verify + preview + confirm a user-supplied file. | Design system: theme, colors, typography, spacing, surfaces, components, do's & don'ts |

All five skills support `create` / `extend` / `replace` modes from the coordinator. Each enforces hard caps (no diagrams; length limits where applicable; codebase-evidence OR explicit user input for every proposition; ALWAYS uses the harness question tool; one question per turn; multi-choice with recommended options when possible; no external-authority citations).

**Outcome strings** reported back to the coordinator:
- `created` (or for design: `created via build` / `created via import from <path>`)
- `extended`
- `replaced`
- `skipped (declined mid-skill)`

**Why inline (not subagent):** Each convention file mixes code-derivable signal (extractable in one pass) with user-held intent (only drawable out conversationally — which principles matter, which terms are load-bearing, which boundaries are deliberate, what the vibe is). A dispatched subagent returns once and dies; it can't have the back-and-forth needed for the second half. Routing the conversation through the coordinator (subagent returns findings → coordinator paraphrases → user replies → coordinator re-dispatches) wastes turns and drifts intent. So all five stay inline.

**Writes:** `docs/DESIGN.md` (or `context.design_path` if overridden) directly — `bootstrapping-project` skips its usual Discuss / Write steps for this file.

**Outcomes reported to coordinator:** `created via import from <path>` / `created via build` / `extended via build` / `replaced via build` / `skipped (declined mid-skill)`.

---

## Shared Scripts

### discover-context.sh

**Location:** `spec-driven-development/scripts/discover-context.sh`
**Purpose:** Find project convention files and active SDD state. Output is JSON listing the paths from config (or `null` when a path is unset or the file doesn't exist on disk).

**Source of truth:** `.sdd/config.yml`. There is **no auto-fallback search** — every path is read straight from config. The script verifies each context file exists before returning the path; if it doesn't, the corresponding output is `null`.

| JSON field | Config key | Notes |
|---|---|---|
| `constitution` | `context.constitution_path` | scalar; null = not used |
| `architecture` | `context.architecture_path` | scalar; null = not used |
| `glossary` | `context.glossary_path` | scalar; null = not used |
| `domain` | `context.domain_path` | scalar; null = not used |
| `design` | `context.design_path` | scalar; null = not used |
| `spec_dir` | `paths.spec_dir` | also drives `active_states` |
| `adr_dir` | `paths.adr_dir` | also drives `adrs` |
| `readme` | (hardcoded `README.md`) | one universal location |
| `adrs` | — | all `.md` files at `<adr_dir>/` |
| `active_states` | — | all `state.json` at `<spec_dir>/*/state.json` |
| `config` | — | path to `.sdd/config.yml` if present |

**YAML extractor:** minimal awk-based, handles flat `block: \n  key: value` only. Sufficient for the singular scalars in `paths:` and `context:`. List-typed or multi-line config values (e.g., `finishing.pr_body_template`) are parsed by individual skills that need them.

**Output JSON shape:**

```json
{
  "repo_root": "/abs/path",
  "config": ".sdd/config.yml" | null,
  "constitution": "docs/constitution.md" | null,
  "architecture": "docs/ARCHITECTURE.md" | null,
  "glossary": "docs/GLOSSARY.md" | null,
  "domain": null,
  "design": "docs/DESIGN.md" | null,
  "readme": "README.md",
  "spec_dir": "docs/specs",
  "adr_dir": "docs/adr",
  "adrs": ["docs/adr/0001-...", ...],
  "active_states": ["docs/specs/003-user-auth/state.json", ...]
}
```

### validate-config.sh

**Location:** `spec-driven-development/scripts/validate-config.sh`
**Purpose:** Validate `.sdd/config.yml` structurally and semantically. Used by `bootstrapping-project`'s fix-and-retry loop and by `preflight-checks` (Stage 0, Step 1) to halt the SDD pipeline if the config is missing or invalid.

**Usage:** `./scripts/validate-config.sh [config-path]` (default: `<repo-root>/.sdd/config.yml`)

**Checks:**
- YAML parses (uses `python3` + PyYAML when available; falls back to an awk-based shallow scanner)
- All six top-level blocks present: `paths`, `context`, `preflight`, `grill`, `memory_file`, `finishing`
- Required scalar keys per block
- Each `context.<name>_path` is null OR points to an existing file (orphan paths fail)
- `finishing.mode` ∈ `{prompt, leave, merge-local, pr, auto}`
- Numeric sanity (`grill.question_cap` 1-20; `memory_file.character_limit` ≥ 1000)
- Type sanity (booleans, strings, null-or-string)
- Rejects unknown `context.*_path` keys (catches stale schema after upgrades)

**Exit codes:**
- `0` — PASS
- `1` — FAIL (one or more issues; findings on stderr with `FAIL:` / `WARN:` prefixes)
- `2` — config file not found
- `3` — usage error

**Output:** findings on stderr; final summary line on stdout (`validate-config: PASS` or `validate-config: FAIL (N issues)`).

### get-config-value.sh

**Location:** `spec-driven-development/scripts/get-config-value.sh`
**Purpose:** Read a single scalar value from `.sdd/config.yml`. Intended for skills that need one or two config values and don't want to inline YAML parsing.

**Usage:** `./scripts/get-config-value.sh <block> <key> [config-path]`

Examples:
- `./scripts/get-config-value.sh finishing test_command` → `"make test"`
- `./scripts/get-config-value.sh preflight use_worktree` → `"true"`
- `./scripts/get-config-value.sh grill question_cap` → `"15"`
- `./scripts/get-config-value.sh memory_file character_limit` → `"40000"`

**Exit codes:**
- `0` — value found (printed to stdout, no trailing newline)
- `2` — config file missing, or block/key not found
- `3` — usage error

**Limitations** (same as discover-context.sh's extractor): scalars only, no lists, no nested objects, no multi-line block scalars. For complex YAML, skills use a proper parser.

### validate-spec.sh

**Purpose:** Schema-check a `spec.md`. Run by `writing-specs` as the first sub-step of its self-review; re-run by the coordinator before committing.

**Checks:**
- Required sections (Header, Goal, User Stories, Functional Requirements, Success Criteria, Edge Cases, Assumptions, Out-of-Scope)
- At least one FR-### and one SC-###
- **Duplicate FR-### and SC-### IDs** (defined more than once)
- User stories with priorities (P1/P2/...)
- Each story has acceptance scenarios (warning if mismatched count)
- Placeholder patterns (TBD, TODO, FIXME, `<your-`, etc.)
- Forbidden diagram syntax (Mermaid, PlantUML, C4)
- Soft length guard (warning at 800+ lines)

**Exit codes:** 0 = pass (warnings allowed); 1 = fail (critical issues).

### validate-plan.sh

**Purpose:** Schema-check a `plan.md`. Same producer/consumer pattern as validate-spec.sh.

**Checks:**
- Required sections (Header, Goal, Architecture, Tech Stack, File Structure)
- At least one Phase
- At least one T### task ID
- **Duplicate T### task IDs**
- Task headers have Requirements traceability
- `[NO-TDD]` markers have a reason on the next line
- Placeholder patterns (TBD, TODO, "similar to Task", etc.)
- Forbidden diagram syntax
- Soft length guard (warning at 2000+ lines)

### validate-handoff.sh

**Purpose:** Schema-check a handoff document. Critical: catches unredacted secrets. Strips trailing `.tmp` for filename pattern check so it validates the staged file before atomic mv.

**Checks:**
- Filename pattern `YYYY-MM-DD-<kebab-title>.md` (trailing `.tmp` is stripped before the check)
- Required sections (Header, Quick context, Source artifacts, What got built, Build highlights, Test status, Open concerns, If you're continuing this work, Redactions)
- Unredacted secret patterns (OpenAI/AWS/GitHub tokens, JWTs, private keys, URLs with credentials, sensitive env-var values)
- Placeholder patterns (handoff is generated, not drafted — placeholders shouldn't appear)
- Soft length guard (warning at 800+ lines)

---

## Canonical State Schema

### state-schema.md (human-readable) and state-schema.json (JSON Schema Draft 2020-12)

**Location:** `spec-driven-development/scripts/state-schema.md`, `spec-driven-development/scripts/state-schema.json`

**Purpose:** Single source of truth for the state file schema. The coordinator, `inspecting-state`, and any other skill that touches the state file MUST match this definition. If a skill diverges from these files, fix the skill (or update these files if the change is intentional) — drift between them is a bug.

The `.md` file is the readable reference (field tables, ownership, lifecycle, worked example). The `.json` file is for objective validation: a JSON Schema validator (e.g., `ajv`, `python -m jsonschema`) can check a state file against it directly.

Cross-references in this repo:
- `sdd-coordinator/SKILL.md` links to it for state schema details
- `inspecting-state/SKILL.md` uses it as the source for validation
- `docs/sdd/state-and-config.md` references it as canonical

---

## Skill interaction graph (text form)

```
sdd-coordinator (entry; user-invoked)
├── inspecting-state            (Step 1 of every invocation)
├── preflight-checks            (Stage 0)
├── discovering-requirements    (Stage 1)
├── writing-specs               (Stage 2; uses validate-spec.sh)
│
├── dispatch → reviewing-specs  (Stages 3, 4; subagent)
│       ↓
│   receiving-review-findings   (inline; process findings)
│
├── grilling-specs              (Stage 5; optional)
│
├── dispatch → maintaining-adrs (Stage 6; subagent)
│
├── (user approval — Stage 7)
│
├── writing-plans               (Stage 8; uses validate-plan.sh)
│
├── dispatch → reviewing-plans  (Stages 9, 10; subagent)
│       ↓
│   receiving-review-findings   (inline; process findings)
│
├── (user approval — Stage 11)
│
├── implementing-plans          (Stage 12; orchestrates per-task subagents)
│       ↓
│       per-task fresh subagents (each task: implementer + 2 reviewers)
│           ↓
│       implementer subagents load → implementing-task
│
├── testing-implementation      (Stage 13; orchestrates tester subagent)
│
├── dispatch → generating-handoff (Stage 14; subagent; uses validate-handoff.sh)
│
├── dispatch → maintaining-memory-file (Stage 15; subagent)
│
└── finishing-sdd               (Stage 16)


project-bootstrap family (outside SDD pipeline; user-invoked manually)
├── bootstrapping-project (coordinator)
│       ↓ loads inline via Skill tool (one per convention file, sequential):
│   ├── discovering-constitution   (inline, conversational)
│   ├── discovering-architecture   (inline, conversational)
│   ├── discovering-glossary       (inline, conversational)
│   ├── discovering-domain-model   (inline, conversational)
│   └── discovering-design         (inline, conversational — Import path or Build path)
```

---

## Cross-references

- For artifact formats produced by these skills, see [artifacts.md](artifacts.md).
- For state-file schema and config schema, see [state-and-config.md](state-and-config.md).
- For subagent dispatch protocols and validation script details, see [operations.md](operations.md).
- For pipeline stage details (what happens between skills), see [pipeline.md](pipeline.md).
