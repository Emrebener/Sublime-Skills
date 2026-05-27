# Skills Reference

The SDD family is 20 skills coordinated by `ss-sdd-coordinator`. The project-bootstrap family is a separate 9-skill set (1 bootstrap coordinator + 1 audit coordinator + 7 per-artifact discovery skills) used to set up `.sublime-skills/config.yml` and the 7 project convention artifacts (lives at `skills/project-bootstrap/`, outside the SDD pipeline). Both families share 7 scripts under `skills/spec-driven-development/framework/` (`discover-context.sh`, `get-config-value.sh`, `validate-config.sh`, `coherence-check.sh`, `validate-spec.sh`, `validate-plan.sh`, `validate-handoff.sh`) and a canonical state schema (`state-schema.md` + `state-schema.json`). This document is the per-skill reference: what it does, when it runs, what it reads, what it writes, and how it interacts with the rest of each family.

## Quick map by role

**Orchestration:**
- `ss-sdd-coordinator` — entry point; state machine + dispatcher

**Workflow stages (in pipeline order):**
- `ss-sdd-preflight` — Stage 0
- `ss-sdd-discovering-requirements` — Stage 1
- `ss-sdd-writing-specs` — Stage 2
- `ss-sdd-reviewing-specs` — Stages 3, 5 (subagent)
- `ss-sdd-grilling-specs` — Stage 4
- `ss-sdd-maintaining-adrs` — Stage 6 (subagent)
- `ss-sdd-receiving-review-findings` — Stages 3, 5, 9, 10 (inline)
- `ss-sdd-writing-plans` — Stage 8
- `ss-sdd-reviewing-plans` — Stages 9, 10 (subagent)
- `ss-sdd-choosing-feature-branch` — Stage 12 (inline; batch-commits SDD planning artifacts)
- `ss-sdd-implementing-plans` — Stage 13 (orchestrates per-task subagents)
- `ss-sdd-implementing-task` — Stage 13 (loaded by implementer subagents)
- `ss-sdd-reviewing-task-compliance` — Stage 13 (loaded by spec-compliance reviewer subagent)
- `ss-sdd-reviewing-task-quality` — Stage 13 (loaded by code-quality reviewer subagent; also used for final review)
- `ss-sdd-testing-implementation` — Stage 14 (orchestrates tester + fixer subagents)
- `ss-sdd-testing-feature` — Stage 14 (loaded by tester subagent)
- `ss-sdd-fixing-test-failures` — Stage 14 (loaded by fixer subagent)
- `ss-sdd-generating-handoff` — Stage 15 (subagent)
- `ss-sdd-maintaining-memory-file` — Stage 16 (subagent)
- `ss-sdd-finishing` — Stage 17

**Bootstrap (outside the SDD family — see `skills/project-bootstrap/` directory):**
- `ss-bs-bootstrapping-project` — one-time project setup coordinator
- `ss-bs-auditing-project` — sibling coordinator for re-evaluating already-bootstrapped projects (drift detection, prescriptive-by-default, per-stage commits)
- `ss-bs-discovering-constitution` / `ss-bs-discovering-architecture` / `ss-bs-discovering-testing` / `ss-bs-discovering-glossary` / `ss-bs-discovering-domain-model` / `ss-bs-discovering-design` / `ss-bs-discovering-memory-file` — per-artifact inline conversational skills (loaded into the coordinator's context, not dispatched). All seven support an optional suggestion-pass (`SUGGEST=on`) and an audit mode (`MODE=audit`) used by the audit coordinator.

**Shared scripts:**
- `discover-context.sh` — find project convention files; reads paths from `.sublime-skills/config.yml`
- `get-config-value.sh` — read a single scalar value from `.sublime-skills/config.yml`
- `validate-config.sh` — validate `.sublime-skills/config.yml` structure + path resolution (used by both bootstrap and SDD coordinator)
- `coherence-check.sh` — cross-artifact structural consistency check across the 7 bootstrap artifacts (invoked by `ss-bs-bootstrapping-project` at end of run and by `ss-bs-auditing-project` at start of run)
- `validate-spec.sh` — schema-check a spec.md (incl. duplicate FR/SC ID detection)
- `validate-plan.sh` — schema-check a plan.md (incl. duplicate T### detection)
- `validate-handoff.sh` — schema-check a handoff doc (incl. unredacted-secret patterns)

**Canonical state schema:**
- `state-schema.md` — human-readable state file schema (fields, ownership, lifecycle)
- `state-schema.json` — machine-readable JSON Schema Draft 2020-12

---

## ss-sdd-coordinator

**Type:** Orchestrator (entry point)
**Loaded:** by the user at the start of every SDD session
**Stage:** drives all 18 stages

**Purpose:** The single entry point. Reads `.sublime-skills/config.yml` (via preflight) and walks the pipeline. Loads phase-skills inline when they're inline-driven; dispatches subagents in fresh context when they're subagent-driven. Updates the state file at every stage boundary. A run starts at Stage 0 and advances through stages within a single conversation — conversation context tells the coordinator where it is, and the state file is the data-carrier between stages and the orchestration record for per-task subagents, not a resume mechanism.

**Key rules:**
- Never advances past a user-approval gate (Stages 7, 11) without explicit user yes
- Never auto-skips optional stages (4, 5, 10, 13) — always asks
- Never tests the feature itself when `ss-sdd-testing-implementation` reports MCP_UNAVAILABLE
- State updates are atomic and happen at stage boundaries only

**Reads:** `.sublime-skills/config.yml`, the state file (created by preflight at Stage 0), every artifact the pipeline produces
**Writes:** state file (atomic; the shell is created by preflight), commits at stage transitions, ADR status flips on approval

**Common mistakes the skill warns against:**
- Updating state mid-stage
- Doing phase-skill work inline instead of loading the phase-skill or dispatching a subagent
- Multiple implementer subagents in parallel (sequential only)

---

## ss-sdd-preflight

**Type:** Phase skill (inline)
**Loaded:** by the coordinator at Stage 0
**Stage:** 0

**Purpose:** Validate that the repo is workable for SDD, then create the state file shell. A **permissive** gate: aborts only on conditions that genuinely make SDD impossible. Does NOT create branches (Stage 12 owns that).

**Behavior matrix:**

| Condition | Action |
|---|---|
| `.sublime-skills/config.yml` missing | ABORT — `config_missing` |
| `.sublime-skills/config.yml` invalid | ABORT — `config_invalid` |
| Not a git repo | ABORT — `not_a_git_repo` |
| Detached HEAD | ABORT — `detached_head` |
| Dirty working tree | WARN + confirm; ABORT — `user_declined` only if user says no |
| Otherwise (clean tree, named branch, valid config, git repo) | Proceed → create state shell, return ready |

**Key rules:**
- No `git commit`, no `git stash`, no `git clean`, no `git restore`, no `git checkout`. Preflight never mutates working-tree state.
- Dirty trees are allowed because SDD's commits are path-scoped to its own artifacts — the user's pre-existing dirty files stay untouched throughout the pipeline.
- Branch creation belongs to Stage 12 (`ss-sdd-choosing-feature-branch`), not here.
- State shell is written as the **last** step, only after all validation passes — an aborted preflight leaves no trace.
- Any pre-existing `.sublime-skills/state.json` at preflight entry is treated as an orphan from a dead prior pipeline and silently removed before the fresh shell is written.

**Reads:** config + git state
**Writes:** `.sublime-skills/state.json` (shell with `started_at`, `updated_at`, `current_stage: "preflight"`, empty `stages_completed` / `stages_skipped`, empty `tasks`)
**Returns to coordinator:** current branch (also held in-memory for downstream use)

**Returns on success:**

```
Preflight complete.
- Branch: <current branch>
- Working tree: clean | dirty (proceeding per user confirmation)
- State file: created (shell) | created (orphan removed first)
- Status: ready
```

**Returns on abort:**

```
Preflight aborted.
- Status: aborted_at_preflight
- Reason: config_missing | config_invalid | not_a_git_repo | detached_head | user_declined
- Message: <user-facing message>
```

---

## ss-sdd-discovering-requirements

**Type:** Phase skill (inline; conversational)
**Loaded:** by the coordinator at Stage 1
**Stage:** 1

**Purpose:** Build shared understanding of what's being built through a four-phase conversation. Output is in-memory plus a structured end-of-stage summary in the agent's final message; nothing is written to disk in this stage. `ss-sdd-writing-specs` renders the spec next.

**Four phases:**
- **Phase 1 — Context:** load conventions, scope-check, classify work type (`feature` / `fix`)
- **Phase 2 — Framing probe:** F1 driver, F2 alternatives, F3 substitute behavior, F4 concrete walkthrough — surfaces the implicit before requirements gathering
- **Phase 3 — Targeted dimension walk:** every dimension in the 9-dimension coverage checklist ends with a stated answer (or signal-cited N/A); major decisions tagged as ADR candidates
- **Phase 4 — Synthesis:** stop-and-summarize gate, section-by-section approval (with F1/F3 framing inline), final confirmation, structured end-of-stage summary

**Cross-cutting rules (apply throughout Phases 2–4):**
- CC-1 — Playback gate (paraphrase non-obvious implications)
- CC-2 — Contradiction watch (surface and resolve conflicting answers)
- CC-3 — Adjacent-scenario invitation (ask for a scenario *distinct* from F4 when a dimension is stuck)
- CC-4 — Mid-conversation scope re-check (re-run Phase 1's scope check on added functionality)

**Conversation rules:**
- One question per message (no compound questions)
- Multiple choice with a recommended answer preferred over open-ended when there are clear alternatives
- Framing probes (F1–F4) skippable only under narrow explicit conditions
- F2 forcing function: if user considered no alternatives, agent proposes 2–3 and tags the resolved decision as an ADR candidate immediately

**Hard gate:** the skill writes NOTHING to disk. Output is the coordinator's understanding plus the structured end-of-stage summary in the agent's final message.

**Reads:** project context (via `discover-context.sh`)
**Writes:** nothing

**Section-by-section approval:** at the end, the skill summarizes back in sections (goal, users, scope, success, entities, edge cases, decisions). User approves each before moving on. The Goal section is framed with its F1 driver (and F3 substitute, when load-bearing) inline as a parenthetical.

**Structured end-of-stage summary** (the agent's final message to the coordinator):

```
=== DISCOVERY SUMMARY ===
short_name, work_type
framing: driver, alternatives, substitute_behavior, walkthrough
dimensions: purpose, users, scope_in, scope_out, success, entities, edge_cases, constraints, integration
major_decisions: [{title, chosen, rejected, reasoning}]
open_questions: [{question, default, disposition}]
approved_sections
=== END SUMMARY ===
```

The structure is for agent self-discipline and cleaner coordinator state; it is NOT a parse contract with Stage 2. No new dispatch parameters introduced — the summary populates existing in-memory carry and the existing `DECISIONS_CAPTURED` dispatch to Stage 6.

**Common mistakes:**
- Skipping framing probes without an explicit narrow skip condition
- Free-form `N/A — doesn't apply` for a dimension (must cite a Phase 1 or Phase 2 signal)
- Re-proposing decisions already resolved at F2
- Advancing past the §4.1 stop-gate without being able to write the user/trigger/success/failure paragraph
- Returning a free-form bullet list instead of the §4.4 structured summary

---

## ss-sdd-writing-specs

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

**State file:** writes feature-identifying fields (`feature_id`, `short_name`, `work_type`, `spec_path`) into the existing shell (preflight created it at Stage 0). Does NOT advance `current_stage` or append to `stages_completed`; the coordinator handles stage advancement after the skill returns.

**Validator invoked:** `framework/validate-spec.sh`. Runs as first sub-step of Step 5 self-review. Must pass before the skill reports back.

**Filename:** `docs/specs/NNN-<short-name>/spec.md` where `NNN` is the next sequential 3-digit number.

---

## ss-sdd-reviewing-specs

**Type:** Subagent skill (dispatched in fresh context)
**Loaded:** by the dispatched subagent at Stages 3, 5
**Stage:** 3 (mandatory first-pass), 5 (optional second-pass)

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

## ss-sdd-grilling-specs

**Type:** Phase skill (inline; conversational)
**Loaded:** by the coordinator at Stage 4, only if user opted in
**Stage:** 4 (optional)

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
1. Append `- Q: ... → A: ...` to the Clarifications log section (created if missing) — always, regardless of body-edit disposition
2. Pick a disposition: **Substantive change** (edit the affected section), **Confirms spec is already correct** (log only, no body edit), or **Out of scope / deferred** (log + maybe an Out-of-Scope line)
3. **Save the spec immediately (atomic write)** — even when only the Clarifications log changed; atomic per-answer writes keep each answer durable on its own
4. Move to next question

**Stop conditions:**
- User signals done
- All high-impact categories resolved
- Cap reached (default 10; configurable; hard ceiling 20)

**Reads:** spec + project context
**Writes:** updated spec.md (atomic per-answer)

---

## ss-sdd-maintaining-adrs

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

## ss-sdd-receiving-review-findings

**Type:** Inline skill (process review output)
**Loaded:** by the coordinator after each reviewer subagent returns
**Stages:** 3, 5, 9, 10

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

## ss-sdd-writing-plans

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

**Validator invoked:** `framework/validate-plan.sh`. Runs as first sub-step of Step 6 self-review.

---

## ss-sdd-reviewing-plans

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

**Severity rubric:** same shape as ss-sdd-reviewing-specs (CRITICAL / HIGH / MEDIUM / LOW with calibration).

**Output:** structured markdown report including a Spec Coverage table — the most concrete check.

**Hard rules:** READ-ONLY, no rewrites, no sub-subagent dispatch.

---

## ss-sdd-choosing-feature-branch

**Type:** Phase skill (inline)
**Loaded:** by the coordinator at Stage 12
**Stage:** 12

**Purpose:** Decide which branch the SDD planning artifacts (spec, plan, ADRs) — uncommitted through Stages 2–11 — should land on. Optionally creates a feature branch with `git checkout -b`, then batch-commits the artifacts in two thematic commits. `.sublime-skills/state.json` is gitignored and never included in commits.

**3-way user prompt:**
1. Create and switch to `<derived-name>` (recommended; derived from `branching.branch_pattern`)
2. Use a different branch name
3. Stay on the current branch — commits land here

**Batch commits (in order, skipping any whose paths don't exist):**
1. `docs(<feature_id>): spec and plan` — spec.md + plan.md
2. `docs(adr): N decisions for <feature_id>` — new ADRs from this run

**Path-scoping is mandatory.** Never `git add .` / `git add -A`, never `git add -f .sublime-skills/state.json`. The user may have pre-existing dirty files (preflight allows them through); path-scoping protects them, and `state.json` stays gitignored.

**Aborts:**
- `branch_creation_failed` (checkout failed; branch exists or invalid name)
- `user_declined` (user said abort at any prompt)
- `commit_failed` (hook rejection / signing failure — per the Commit Failure Protocol)

**Hard rules:**
- No `--no-verify`, `--no-gpg-sign`, `--force`, or `--amend`
- No push, pull, merge, or branch deletion
- On partial-commit failure (commit 1 succeeded, 2 failed), halt and surface; never amend a previous commit. User resolves the partial state manually.

---

## ss-sdd-implementing-plans

**Type:** Phase skill (inline; orchestrates per-task subagents)
**Loaded:** by the coordinator at Stage 13
**Stage:** 13

**Purpose:** Drive the per-task loop. For each task: dispatch implementer subagent → handle status → (only when `per_task_reviews: full`) dispatch spec-compliance reviewer → loop on Issues Found (cap 3) → (only when `per_task_reviews: full`) dispatch code-quality reviewer → loop on Issues Found (cap 3, Minor non-blocking) → mark complete. The per-task reviewers are gated on the `state.per_task_reviews` field that the coordinator sets at Stage 13 entry from a user-gate (default off).

**Continuous execution:** no pausing between tasks for human check-in. Only stops on BLOCKED, cap hit, plan-is-wrong, or all-tasks-complete.

**Idempotent on entry:** the skill reads existing `state.tasks` and merges with the plan's task list — **never overwrites** existing `completed` / `in_progress` statuses. Starts from the first `in_progress` task (its prior implementer subagent died before reporting completion; re-dispatching is safe since the implementer is a fresh subagent and partial work is either committed or lost) or the first `pending` task if none in-progress. Completed tasks are skipped.

**Per-task state updates:**
- At task start: `tasks[T###]: "in_progress"` (atomic write)
- At task end: `tasks[T###]: "completed"`

**Final review:** mandatory regardless of `per_task_reviews`. After all tasks, dispatch one more code-quality reviewer on the full diff with `TASK_ID=final`. The `ss-sdd-reviewing-task-quality` skill has explicit guidance for the final case (cross-cutting concerns, multi-file diff handling). Sets `final_review_completed: true` in state file.

**Prompt templates** (dispatch envelopes alongside the skill — protocols live in dedicated skills):
- `implementer-prompt.md` → calls `ss-sdd-implementing-task`
- `spec-compliance-reviewer-prompt.md` → calls `ss-sdd-reviewing-task-compliance`
- `code-quality-reviewer-prompt.md` → calls `ss-sdd-reviewing-task-quality`

**Subagent statuses handled:**

| Status | Action |
|---|---|
| DONE | If `per_task_reviews: full`, proceed to spec-compliance review. Else mark task complete and advance. |
| DONE_WITH_CONCERNS | If correctness/scope concerns: re-dispatch with concerns appended. If observations only: note and proceed. |
| NEEDS_CONTEXT | Provide context, re-dispatch |
| BLOCKED | Assess and re-dispatch with: more context / more capable model / smaller pieces / escalate to user |

**Sequential dispatch:** NEVER dispatch multiple implementers in parallel (they would conflict).

---

## ss-sdd-implementing-task

**Type:** Subagent skill (lightweight protocol)
**Loaded:** by implementer subagents themselves when they start
**Stage:** 13 (during per-task implementation)

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

**"Your work will be reviewed" priming:** explicit in the Overview and reinforced throughout. Improves output quality measurably. The priming covers both modes — mandatory final cross-cutting review (always) plus optional per-task two-stage review (when the user enabled it at Stage 13 entry).

---

## ss-sdd-reviewing-task-compliance

**Type:** Subagent skill (full protocol for the per-task spec-compliance reviewer)
**Loaded:** by the spec-compliance reviewer subagent when it's dispatched
**Stage:** 13 (per task)

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

## ss-sdd-reviewing-task-quality

**Type:** Subagent skill (full protocol for the per-task code-quality reviewer)
**Loaded:** by the code-quality reviewer subagent when it's dispatched
**Stage:** 13 (per task, after spec compliance is Approved)

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

## ss-sdd-testing-implementation

**Type:** Phase skill (inline; orchestrates tester subagent)
**Loaded:** by the coordinator at Stage 14 (only if user opted in)
**Stage:** 14 (optional)

**Purpose:** Feature-level testing distinct from per-task unit tests. Asks the user for a depth (`quick` or `standard`, default `standard`), then dispatches a tester subagent that picks a strategy based on available MCPs and feature type.

**Depth selection (asked once per invocation, not persisted to state):**

| Depth | Coverage |
|---|---|
| `quick` | Golden paths of every P1 user story only — no edge cases, no P2/P3 |
| `standard` | P1 stories + their listed edge cases; P2/P3 if straightforward (default) |

**Result statuses from the tester subagent:**

| Status | Coordinator action |
|---|---|
| PASS | Update state, advance to Stage 15 |
| FAIL | Dispatch fixer subagent with failures; re-test; cap 3 iterations before escalating |
| MCP_UNAVAILABLE | Surface manual test plan + code review findings to user; **coordinator MUST NOT test itself** |

**Strategy selection (in tester subagent):**
- **UI-only**: browser MCP for golden path + edge cases. Fallback to MCP_UNAVAILABLE.
- **Backend-only**: project test runner + HTTP requests + DB MCP for data verification. Fallback acceptable if test runner exists.
- **Library/CLI**: project test runner + direct CLI invocation.
- **Mixed**: run both UI and backend strategies.

**Prompt templates** (separate files alongside the skill):
- `tester-prompt.md` — dispatch envelope; calls `ss-sdd-testing-feature`
- `fixer-prompt.md` — dispatch envelope; calls `ss-sdd-fixing-test-failures`

**Coordinator MUST NOT test itself when MCP_UNAVAILABLE.** This rule is repeated in five different places in the skill because it's the highest-risk rationalization. If the tester can't test, the coordinator surfaces to user — doesn't pick up Bash/Playwright/curl itself.

---

## ss-sdd-testing-feature

**Type:** Subagent skill (full protocol for the tester subagent)
**Loaded:** by the tester subagent when it's dispatched
**Stage:** 14 (optional)

**Purpose:** Feature-level verification — does the implementation deliver what the spec promised end-to-end? Picks strategy by feature type and available tools.

**Inputs the dispatcher provides:** `FEATURE_TYPE`, `DEPTH` (`quick` or `standard`), `SPEC_PATH`, `PLAN_PATH`, `BRANCH`, `BASE_SHA`, `HEAD_SHA`.

**Strategy selection:**
- **UI-only:** browser MCP for golden path + edge cases; return `MCP_UNAVAILABLE` if no browser MCP
- **Backend-only:** project test runner + HTTP + DB MCP combinations; acceptable to fall back to test runner + HTTP if no DB MCP
- **Library / CLI:** project test runner or direct CLI invocation via Bash
- **Mixed:** both UI and backend strategies

**Tool inventory step:** explicitly lists what's actually available before picking strategy — prevents the "pretend tests passed" failure mode.

**Coverage rules (modulated by `DEPTH`):**
- P1 golden paths are the floor at both depths (must cover all)
- At `standard`, also cover the spec's listed edge cases per P1 story, plus P2/P3 when straightforward; mark "not exercised" otherwise
- At `quick`, skip edge cases and skip P2/P3 entirely
- Never fabricate coverage to look thorough

**Output:** one of three statuses with structured formats:
- `PASS` — tools used, stories covered, scenarios run, notes
- `FAIL` — per-failure: story, scenario, expected, actual, likely location, reproduction
- `MCP_UNAVAILABLE` — reason, available tools, manual test plan, code-review fallback findings

**Hard rules:** never modify code (you're a tester, not a fixer); never fabricate results; never approve FAIL as "close enough"; leaf agent.

---

## ss-sdd-fixing-test-failures

**Type:** Subagent skill (full protocol for the fixer subagent)
**Loaded:** by the fixer subagent when it's dispatched
**Stage:** 14 (during fix loop, on tester FAIL)

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

## ss-sdd-generating-handoff

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stage 15
**Stage:** 15 (user-prompted, default yes)

**Purpose:** Produce a self-contained handoff document at `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<short-title>.md` that lets a fresh agent (or human) continue work without re-reading everything.

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

**Validator invoked:** `framework/validate-handoff.sh`. Critical failures include unredacted secret patterns.

**Hard rules:**
- Do NOT duplicate ADR content (reference + one-line summary)
- Do NOT duplicate large spec/plan sections
- Do NOT modify any file other than the new handoff doc
- Do NOT dispatch sub-subagents

---

## ss-sdd-maintaining-memory-file

**Type:** Subagent skill
**Loaded:** by the dispatched subagent at Stage 16
**Stage:** 16 (user-prompted, default yes; auto-skipped without prompt when no memory file is configured/detected)

**Purpose:** Decide whether the project's agent memory file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`) needs updating based on what this run produced, and if so, update it. Most runs do NOT warrant an update — that's normal.

**Inputs the dispatcher provides:** `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS`, `MEMORY_FILE_PATH` (resolved from config or auto-detect; null = skip), `CHARACTER_LIMIT` (soft cap; default 40000), `EXISTING_CONTENT` (current file text).

**Path resolution** (in coordinator before dispatch):
1. `.sublime-skills/config.yml → memory_file.path` if set (absolute or repo-relative)
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
| `skipped (no path configured)` | No memory file configured/detected; `memory_file` added to `stages_skipped` |
| `skipped (file missing on disk)` | Configured path points to a missing file (mid-run deletion or preflight bypass); `memory_file` added to `stages_skipped`; coordinator surfaces hint to re-run `ss-bs-bootstrapping-project` or `ss-bs-auditing-project`. (Preflight's `validate-config.sh` normally catches this at Stage 0, so reaching this status mid-pipeline is rare.) |

**Authoring vs maintenance:** This skill is for incremental updates only — it never creates the memory file from scratch. Full authoring (with pointer synthesis from the six convention files) is the bootstrap discovery skill `ss-bs-discovering-memory-file`'s job, run by `ss-bs-bootstrapping-project` (Create/Extend) or `ss-bs-auditing-project` (audit).

The skill's SKILL.md includes a Best Practices section on what memory files are for (project conventions, NEVER/MUST rules, canonical vocabulary, pointers), what they're NOT for (changelogs, TODOs, narrative, transient state), healthy size ranges, update cadence, pruning advice, and common anti-patterns to avoid.

---

## ss-sdd-finishing

**Type:** Phase skill (inline)
**Loaded:** by the coordinator at Stage 17
**Stage:** 17

**Purpose:** Close out the SDD run by completing the source-control loop. Validate the state file, print a structured summary, merge the feature branch into `main` with `--no-ff`, safe-delete the feature branch on merge success, then `rm .sublime-skills/state.json`. Local-only — no push, no PR.

**Steps:**
1. Read and validate `.sublime-skills/state.json`. Confirm `implementation_complete` is in `stages_completed` and `branch_name` is set. If tests aren't passing (or absent when not skipped), prompt the user before proceeding. No test re-run — Stage 14 was the test gate.
2. Print summary: feature_id, short_name, feature branch (to be merged + deleted), spec/plan/handoff paths, ADRs created, tasks completed, test_status, memory_file_updated.
3. `git checkout main && git merge --no-ff "$branch_name" -m "Merge branch '$branch_name'"`. On non-zero exit, halt and surface verbatim; leave the working tree as-is, state file in place. Re-invocation is naturally idempotent (already-merged → exit 0 "Already up to date").
4. `git branch -d "$branch_name"` (safe-delete, not `-D`). On non-zero, halt and surface; leave state in place.
5. `rm .sublime-skills/state.json` — plain `rm`, not `git rm`. No commit follows; the file is gitignored.

**Hard rules:**
- No push, no PR creation, no remote ops
- No `--no-verify` / `--no-gpg-sign` / `--force` on the merge commit
- No `git branch -D` (force-delete) — only `-d`
- No auto-`git merge --abort` on conflict — surface and let the user inspect
- No `rm` of `state.json` until the merge and safe-delete both succeed
- No test re-run
- No `git add` of `state.json` (gitignored; never force-add)

---

## project-bootstrap family (outside the SDD pipeline)

Lives in `skills/project-bootstrap/`. Separate skill family from SDD because the purpose (one-time project setup) is distinct from the SDD pipeline's per-feature workflow.

### ss-bs-bootstrapping-project

**Type:** Coordinator (inline; user-interactive)
**Loaded:** manually by the user (NOT by `ss-sdd-coordinator`)
**Stage:** N/A — one-time per-project setup; safe to re-run

**Purpose:** Walk the user through each convention file with deep per-file project analysis, then scaffold `.sublime-skills/config.yml` and the supporting directories.

**Workflow:**
1. Run `discover-context.sh` to see what already exists.
2. Suggestion-pass opt-in switch: read `suggest.default` from config; if `ask`, ask the user once whether to also run the prescriptive suggestion pass (`SUGGEST=on`) or just document what exists (`SUGGEST=off`); the third option routes to `ss-bs-auditing-project` instead.
3. For each of constitution → architecture → testing → glossary → domain → design → memory-file: detect → ask the user (Create if missing; Skip / Extend / Replace if present) → load the matching `ss-bs-discovering-<topic>` skill inline with `SUGGEST=on|off` from Step 2. Each discovering-X skill handles its own code scan, optional Step 1.5 diagnose (only if `SUGGEST=on`), user conversation, draft, tweak-loop (cap 3), and atomic write internally — the coordinator just records the outcome string and moves to the next file.
4. Create `docs/adr/`, `docs/specs/` with stub READMEs.
5. Copy `skills/project-bootstrap/scaffolds/config.yml` verbatim to `.sublime-skills/config.yml`. Sub-step 5a handles config migration: if an existing config lacks the new `testing_path` or `suggest:` block (pre-update bootstrap), prompt the user and add them with safe defaults.
6. Edit config to reflect reality: any skipped convention file gets its `context.<name>_path` set to `null`.
7. Run `validate-config.sh`; fix-and-retry loop (cap 3) until PASS.
8. Run `coherence-check.sh` — surface findings verbatim with severity (CRITICAL / WARNING / INFO); user chooses Address / Acknowledge / Show. "Address" loops back into the relevant discovering-X skills in extend mode and re-runs coherence (cap 3 coherence loops).
9. Ensure `.sublime-skills/.gitignore` contains both `state.json` and `config-local.yml` entries (Step 5 creates the file; this step appends any missing entries).
10. Single commit `chore: initialize SDD project context`.
11. Report and direct user to `ss-sdd-coordinator`.

**Reads:** existing project files (via `discover-context.sh` + per-skill reads); EXISTING_CONTENT for extend/replace modes.
**Writes:** opted-in convention files (written atomically by each discovering-X skill — up to 7: `docs/CONSTITUTION.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `docs/GLOSSARY.md`, `docs/DOMAIN.md`, `docs/DESIGN.md`, and the agent memory file at `memory_file.path`); `docs/adr|specs/README.md` stubs; `.sublime-skills/config.yml`; `.sublime-skills/config-local.yml` (empty); `.sublime-skills/.gitignore` (with `state.json` and `config-local.yml` entries); one commit.

### ss-bs-auditing-project

**Type:** Coordinator (inline; user-interactive)
**Loaded:** manually by the user, OR from `ss-bs-bootstrapping-project`'s Step 2 third option (skip bootstrap and audit instead)
**Stage:** N/A — re-run on an already-bootstrapped project

**Purpose:** Re-evaluate an already-bootstrapped project for drift, incoherence, and improvement opportunities. Distinct from a bootstrap re-run: coherence runs FIRST (drives the per-stage loop), suggestion pass is always on, drift detection compares artifact vs current code state, commits are per-stage (not bundled).

**Workflow:**
1. Preflight — verify `.sublime-skills/config.yml` exists and validates; verify at least one artifact exists. If not, halt and redirect to `ss-bs-bootstrapping-project`.
2. Run `coherence-check.sh` — surface findings verbatim; group by which discovering-X skill would fix each.
3. Ask the user to pick scope: Fix top N stage-by-stage (Recommended) / I'll pick / Full audit / Skip — just wanted the report.
4. Build the audit todo list (one item per chosen stage + final coherence re-check + summary).
5. Per-stage loop: for each picked stage, load the matching `ss-bs-discovering-<topic>` skill with `MODE=audit, SUGGEST=on`. The skill runs its full audit flow (Step 1 scan + Step 1.5 diagnose + Step 1.6 drift check + Step 2 announce + Step 3 Q0 → Q1 → Q1.5 → … + Step 4 draft + Step 5 refine + Step 6 atomic write). On `audited (changes made)`, commit immediately as `audit: update <basename> — <one-line summary>`. On `audited (no changes)` or `skipped`, no commit; just record in the summary.
6. Run `coherence-check.sh` again; compare to Step 2 findings (resolved / still outstanding / new).
7. Surface the summary report (conversation-only; never persisted to disk).

**Reads:** `.sublime-skills/config.yml`; existing artifacts at configured paths; current code state (via per-skill drift checks).
**Writes:** updated convention files (one per stage that produced changes); one commit per stage updated.

**Why a separate coordinator:** audit's flow differs meaningfully from bootstrap (coherence-first, per-stage commits, prescriptive-by-default, no config-copy / dir-creation steps). Combining them into one skill would mean many `if audit` branches. The sibling skill structure is cleaner; both share the same 7 per-file discovery skills via the `MODE=audit` value.

### ss-bs-discovering-constitution / ss-bs-discovering-architecture / ss-bs-discovering-testing / ss-bs-discovering-glossary / ss-bs-discovering-domain-model / ss-bs-discovering-design / ss-bs-discovering-memory-file

**Type:** Inline conversational skills
**Loaded:** by `ss-bs-bootstrapping-project` into its own context when the per-file loop reaches each slot
**Stage:** N/A

**Purpose:** Deep, focused per-file analysis with sustained user interaction. Each skill performs a silent code scan, announces findings, asks targeted questions about things the code can't reveal, drafts the file, runs a tweak loop (cap 3 iterations), and atomically writes itself. The coordinator just records the outcome string.

| Skill | Reads | User-interaction layer | Produces |
|---|---|---|---|
| `ss-bs-discovering-constitution` | README, CONTRIBUTING, linter/formatter/CI configs, source patterns, security-relevant files | Confirm candidate principles → set MUST/SHALL/SHOULD severity → add intent principles code can't reveal | 3-7 MUST/SHALL/SHOULD principles with one-line rationales each |
| `ss-bs-discovering-architecture` | Top-level dirs, build files, entry points, infra config (Docker/k8s/terraform), `.env.example` | Confirm component grouping → declare out-of-scope → confirm env-var-only integrations → add non-code facts → resolve cardinality | System summary, Components, Runtime topology, Data stores, External integrations, Boundaries (no diagrams) |
| `ss-bs-discovering-testing` | Test dirs, runner configs, CI test commands, coverage tooling, mocking patterns, fixtures | Confirm test categories → canonical test commands → mocking philosophy → fixture/factory location. New-project mode: starter-strategy Q&A when no tests exist yet | Test categories, Runner & framework, Coverage, Mocking philosophy, Fixtures & factories, Conventions |
| `ss-bs-discovering-glossary` | Source identifiers (class/table/route names), inline definitions in comments, README | Pick which ≤30 terms make the cut → declare aliases / multi-naming → refine definitions during tweak loop | 10-30 alphabetical terms, each ≤2 sentences |
| `ss-bs-discovering-domain-model` | DB schemas/migrations, model/type definitions, test fixtures, state-machine code | Pick which ≤15 entities are load-bearing → confirm lifecycles → resolve cardinality → add workflow exceptions | 3-15 entities with conceptual attributes, relationships (with cardinality), lifecycles (no diagrams) |
| `ss-bs-discovering-design` | Tailwind config, CSS custom properties, theme/token files, `components/`, design-system deps in `package.json` | (Build path) Confirm vibe / theme intent → set color role rules → confirm component vocabulary → state do's-and-don'ts. (Import path) Verify + preview + confirm a user-supplied file. | Design system: theme, colors, typography, spacing, surfaces, components, do's & don'ts |
| `ss-bs-discovering-memory-file` | The 6 other artifacts (just written), README first paragraph, run commands from package.json/Makefile/justfile/Taskfile/pyproject | Step 0 detect target file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md) → which canonical sections → confirm pointers → free-form conventions → confirm NEVER/MUST list (seeded from constitution) | Project conventions, Domain vocabulary (3-5 + GLOSSARY.md pointer), NEVER/MUST (seeded from constitution), Pointers (linkdump), Commands |

All seven skills support `create` / `extend` / `replace` / `audit` modes from the coordinator (audit is used only by `ss-bs-auditing-project`). When invoked with `SUGGEST=on`, each runs an additional Step 1.5 (silent diagnose) and surfaces a Q1.5 question proposing evidence-cited additions to the artifact. Accepted suggestions land with a provenance marker that audit re-evaluates on later runs. Each enforces hard caps (no diagrams; length limits where applicable; codebase-evidence OR explicit user input for every proposition; ALWAYS uses the harness question tool; one question per turn; multi-choice with recommended options when possible; no external-authority citations).

**Outcome strings** reported back to the coordinator:
- `created` (or for design: `created via build` / `created via import from <path>`; or for testing: `created via new-project starter` when scan found <2 tests)
- `extended`
- `replaced`
- `audited (changes made)` — audit mode only
- `audited (no changes)` — audit mode only
- `skipped (declined mid-skill)`

**Why inline (not subagent):** Each convention file mixes code-derivable signal (extractable in one pass) with user-held intent (only drawable out conversationally — which principles matter, which terms are load-bearing, which boundaries are deliberate, what the vibe is). A dispatched subagent returns once and dies; it can't have the back-and-forth needed for the second half. Routing the conversation through the coordinator (subagent returns findings → coordinator paraphrases → user replies → coordinator re-dispatches) wastes turns and drifts intent. So all seven stay inline.

**Writes:** each skill writes its own target file directly via atomic `<path>.tmp` + `mv` (`docs/CONSTITUTION.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `docs/GLOSSARY.md`, `docs/DOMAIN.md`, `docs/DESIGN.md`, or the resolved memory-file path) — `ss-bs-bootstrapping-project` and `ss-bs-auditing-project` don't intervene in the per-file Draft / Write steps.

---

## Shared Scripts

### discover-context.sh

**Location:** `skills/spec-driven-development/framework/discover-context.sh`
**Purpose:** Find project convention files and active SDD state. Output is JSON listing the paths from config for context files (or `null` when a path is unset or the file doesn't exist on disk), and hardcoded values for SDD directories.

**Source of truth:** `.sublime-skills/config.yml`, with `.sublime-skills/config-local.yml` overlaid per-key when present (overlay wins). There is **no auto-fallback search** — every path is read straight from these files. The script verifies each context file exists before returning the path; if it doesn't, the corresponding output is `null`.

| JSON field | Config key | Notes |
|---|---|---|
| `constitution` | `context.constitution_path` | scalar; null = not used |
| `architecture` | `context.architecture_path` | scalar; null = not used |
| `testing` | `context.testing_path` | scalar; null = not used |
| `glossary` | `context.glossary_path` | scalar; null = not used |
| `domain` | `context.domain_path` | scalar; null = not used |
| `design` | `context.design_path` | scalar; null = not used |
| `spec_dir` | fixed at `docs/specs` — emitted for debugging only | — |
| `adr_dir` | fixed at `docs/adr` — emitted for debugging only | also drives `adrs` |
| `readme` | (hardcoded `README.md`) | one universal location |
| `adrs` | — | all `.md` files at `<adr_dir>/` |
| `active_state` | — | `.sublime-skills/state.json` if present, else null |
| `config` | — | path to `.sublime-skills/config.yml` if present |
| `config_local` | — | path to `.sublime-skills/config-local.yml` if present, else null |

**YAML extractor:** delegated to the sibling `get-config-value.sh`, which is the single source of truth for scalar reads and overlay semantics. Its extractor is awk-based and handles flat `block: \n  key: value` only — sufficient for the singular scalars in `context:`, `branching:`, `grill:`, and `memory_file:`. List-typed or multi-line config values are parsed by individual skills that need them.

**Output JSON shape:**

```json
{
  "repo_root": "/abs/path",
  "config": ".sublime-skills/config.yml" | null,
  "config_local": ".sublime-skills/config-local.yml" | null,
  "constitution": "docs/CONSTITUTION.md" | null,
  "architecture": "docs/ARCHITECTURE.md" | null,
  "testing": "docs/TESTING.md" | null,
  "glossary": "docs/GLOSSARY.md" | null,
  "domain": null,
  "design": "docs/DESIGN.md" | null,
  "readme": "README.md",
  "spec_dir": "docs/specs",
  "adr_dir": "docs/adr",
  "adrs": ["docs/adr/0001-...", ...],
  "active_state": ".sublime-skills/state.json" | null
}
```

### validate-config.sh

**Location:** `skills/spec-driven-development/framework/validate-config.sh`
**Purpose:** Validate `.sublime-skills/config.yml` structurally and semantically — together with `.sublime-skills/config-local.yml` when present (overlay merged before validation). Used by `ss-bs-bootstrapping-project`'s fix-and-retry loop and by `ss-sdd-preflight` (Stage 0, Step 1) to halt the SDD pipeline if the config is missing or invalid.

**Usage:** `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh" [config-path]` (default: `<repo-root>/.sublime-skills/config.yml`)

**Checks (on the merged config):**
- YAML parses for both files (uses `python3` + PyYAML when available; falls back to an awk-based shallow scanner that validates the base config only and warns when overlay is present)
- All four top-level blocks present: `context`, `branching`, `grill`, `memory_file`
- Required scalar keys per block
- Each `context.<name>_path` is null OR points to an existing file (orphan paths fail)
- Numeric sanity (`grill.question_cap` 1-20; `memory_file.character_limit` ≥ 1000)
- Type sanity (strings, null-or-string)
- Rejects unknown `context.*_path` keys (catches stale schema after upgrades)

**Overlay-specific checks:** any block name in `config-local.yml` that isn't one of the four known blocks is flagged; any key under a known block that isn't part of the schema is flagged. Findings sourced from the overlay are prefixed with `config-local.yml:` so it's clear where to fix them.

**Exit codes:**
- `0` — PASS
- `1` — FAIL (one or more issues; findings on stderr with `FAIL:` / `WARN:` prefixes)
- `2` — config file not found
- `3` — usage error

**Output:** findings on stderr; final summary line on stdout (`validate-config: PASS` or `validate-config: FAIL (N issues)`).

### get-config-value.sh

**Location:** `skills/spec-driven-development/framework/get-config-value.sh`
**Purpose:** Read a single scalar value from the layered config — `config-local.yml` overrides `config.yml` on a per-key basis. Intended for skills that need one or two config values and don't want to inline YAML parsing.

**Lookup order:** `config-local.yml` first; if the key is present there (even as `null`), that value is returned. Otherwise fall through to `config.yml`.

**Usage:** `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" <block> <key> [config-path]`

Examples:
- `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" branching branch_pattern` → `"feat/{short-name}"`
- `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" grill question_cap` → `"10"`
- `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" memory_file character_limit` → `"40000"`

**Exit codes:**
- `0` — value found (printed to stdout, no trailing newline)
- `2` — config file missing, or block/key absent in both layers
- `3` — usage error

**Limitations:** scalars only, no lists, no nested objects, no multi-line block scalars. This script owns the awk-based YAML extractor that all other config-reading scripts (notably `discover-context.sh`) delegate to. For complex YAML, skills use a proper parser.

### coherence-check.sh

**Location:** `skills/spec-driven-development/framework/coherence-check.sh`
**Purpose:** Run Tier 1 structural / pointer checks across the 7 bootstrap artifacts. Invoked by `ss-bs-bootstrapping-project` at end of run (Step 8) and by `ss-bs-auditing-project` at start of run (Step 2).

**Checks:**
- Every `.md` link in any artifact resolves to an existing file → CRITICAL on miss
- Memory file Pointers section lists every existing artifact → WARNING on miss
- Every DOMAIN.md entity is defined in GLOSSARY.md → WARNING
- Every architecture component is mentioned in TESTING.md → INFO
- Constitution principles citing evidence files → those files exist → CRITICAL on miss
- Constitution principles don't contradict each other (heuristic: MUST throw vs MUST use Result) → WARNING
- Suggestion-pass provenance markers older than 6 months → INFO (informational, supports audit)

**Output format:** one block per finding (severity, title, context, fix) on stdout; final summary line `coherence-check: N findings (X CRITICAL, Y WARNING, Z INFO)` or `coherence-check: PASS (0 findings)`.

**Exit codes:** 0 (no findings), 1 (findings present), 2 (config not found), 3 (usage error), 4 (internal error — python3 missing or YAML unparseable).

**Requires:** python3 + PyYAML (no awk fallback; coherence parsing needs accurate YAML handling).

**Findings are surfaced verbatim to the user** by the invoking coordinator (bootstrap or audit) — never summarized. The user decides how to act: Address findings now (loops back into the relevant discovery skills in extend mode), Acknowledge and commit/proceed as-is, or Show details for one finding. Address is capped at 3 coherence loops to prevent stubborn findings from trapping the user.

### validate-spec.sh

**Purpose:** Schema-check a `spec.md`. Run by `ss-sdd-writing-specs` as the first sub-step of its self-review; re-run by the coordinator before committing.

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

**Location:** `skills/spec-driven-development/framework/state-schema.md`, `skills/spec-driven-development/framework/state-schema.json`

**Purpose:** Single source of truth for the state file schema. The coordinator and any other skill that touches the state file MUST match this definition. If a skill diverges from these files, fix the skill (or update these files if the change is intentional) — drift between them is a bug.

The `.md` file is the readable reference (field tables, ownership, lifecycle, worked example). The `.json` file is for objective validation: a JSON Schema validator (e.g., `ajv`, `python -m jsonschema`) can check a state file against it directly.

Cross-references in this repo:
- `ss-sdd-coordinator/SKILL.md` links to it for state schema details
- `docs/sdd/state-and-config.md` references it as canonical

---

## Skill interaction graph (text form)

```
ss-sdd-coordinator (entry; user-invoked)
├── ss-sdd-preflight            (Stage 0)
├── ss-sdd-discovering-requirements    (Stage 1)
├── ss-sdd-writing-specs               (Stage 2; uses validate-spec.sh)
│
├── dispatch → ss-sdd-reviewing-specs  (Stages 3, 5; subagent, first-pass + optional 2nd)
│       ↓
│   ss-sdd-receiving-review-findings   (inline; process findings)
│
├── ss-sdd-grilling-specs              (Stage 4; optional)
│
├── dispatch → ss-sdd-maintaining-adrs (Stage 6; subagent)
│
├── (user approval — Stage 7)
│
├── ss-sdd-writing-plans               (Stage 8; uses validate-plan.sh)
│
├── dispatch → ss-sdd-reviewing-plans  (Stages 9, 10; subagent)
│       ↓
│   ss-sdd-receiving-review-findings   (inline; process findings)
│
├── (user approval — Stage 11)
│
├── ss-sdd-choosing-feature-branch     (Stage 12; inline; batch-commits planning artifacts)
│
├── ss-sdd-implementing-plans          (Stage 13; orchestrates per-task subagents)
│       ↓
│       per-task fresh subagents (each task: implementer + 2 reviewers)
│           ↓
│       implementer subagents load → ss-sdd-implementing-task
│
├── ss-sdd-testing-implementation      (Stage 14; orchestrates tester subagent)
│
├── dispatch → ss-sdd-generating-handoff (Stage 15; subagent; uses validate-handoff.sh)
│
├── dispatch → ss-sdd-maintaining-memory-file (Stage 16; subagent)
│
└── ss-sdd-finishing               (Stage 17)


project-bootstrap family (outside SDD pipeline; user-invoked manually)
├── ss-bs-bootstrapping-project (coordinator)
│       ↓ loads inline (one per convention file, sequential):
│   ├── ss-bs-discovering-constitution   (inline, conversational)
│   ├── ss-bs-discovering-architecture   (inline, conversational)
│   ├── ss-bs-discovering-testing        (inline, conversational)
│   ├── ss-bs-discovering-glossary       (inline, conversational)
│   ├── ss-bs-discovering-domain-model   (inline, conversational)
│   ├── ss-bs-discovering-design         (inline, conversational — Import path or Build path)
│   └── ss-bs-discovering-memory-file    (inline, conversational)
│
└── ss-bs-auditing-project (coordinator — sibling; re-run on bootstrapped projects)
        ↓ loads inline (per picked stage, with MODE=audit SUGGEST=on):
    ├── ss-bs-discovering-constitution   (inline, conversational)
    ├── ss-bs-discovering-architecture   (inline, conversational)
    ├── ss-bs-discovering-testing        (inline, conversational)
    ├── ss-bs-discovering-glossary       (inline, conversational)
    ├── ss-bs-discovering-domain-model   (inline, conversational)
    ├── ss-bs-discovering-design         (inline, conversational — Import path or Build path)
    └── ss-bs-discovering-memory-file    (inline, conversational)
```

---

## Cross-references

- For artifact formats produced by these skills, see [artifacts.md](artifacts.md).
- For state-file schema and config schema, see [state-and-config.md](state-and-config.md).
- For subagent dispatch protocols and validation script details, see [operations.md](operations.md).
- For pipeline stage details (what happens between skills), see [pipeline.md](pipeline.md).
