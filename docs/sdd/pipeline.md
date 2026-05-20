# The SDD Pipeline

The pipeline is a strict 16-stage sequence with three optional stages that the user gates explicitly. The coordinator (`sdd-coordinator`) drives the sequence; specific work is delegated to phase-skills (loaded inline) or subagents (dispatched in fresh context).

This document explains each stage in detail: what runs, what it produces, how failure is handled, and what the next stage expects.

> All stage numbers are stable references throughout the SDD documentation. Stage 7 is "user spec approval"; that's true in this doc, in the coordinator skill, in the state file's `stages_completed` array, everywhere.

## At a glance

| # | Stage | Mechanism | Optional? | Writes to disk? |
|---|---|---|---|---|
| 0 | Preflight | Inline via `preflight-checks` | No | No (git state only) |
| 1 | Discovering requirements | Inline via `discovering-requirements` | No | No (in-memory only) |
| 2 | Writing the spec | Inline via `writing-specs` | No | `spec.md`, `state.json` |
| 3 | Auto spec-review | Subagent via `reviewing-specs` | No | No (returns findings) |
| 4 | 2nd spec-review | Subagent via `reviewing-specs` | **Yes** | No (returns findings) |
| 5 | Grill session | Inline via `grilling-specs` | **Yes** | `spec.md` (updates inline) |
| 6 | ADR maintenance | Subagent via `maintaining-adrs` | No | `docs/adr/NNNN-*.md` (zero or more) |
| 7 | User spec approval | Inline (coordinator) | No | Updates ADR statuses to Accepted |
| 8 | Writing the plan | Inline via `writing-plans` | No | `plan.md`, `state.json` |
| 9 | Auto plan-review | Subagent via `reviewing-plans` | No | No (returns findings) |
| 10 | 2nd plan-review | Subagent via `reviewing-plans` | **Yes** | No (returns findings) |
| 11 | User plan approval | Inline (coordinator) | No | Updates `state.json` |
| 12 | Implementation | Per-task subagents | No | Code files, tests, `state.json` |
| 13 | Feature testing | Subagent via `testing-implementation` | **Yes** | `state.json` (test result) |
| 14 | Handoff generation | Subagent via `generating-handoff` | Default yes, config-skippable | `docs/handoff/YYYY-MM-DD-*.md` |
| 15 | Finishing | Inline via `finishing-sdd` | No | Deletes `state.json`, cleans worktree |

Subagent stages run with no inherited conversation context; the coordinator builds their prompts from scratch.

---

## Pipeline entry point

Every invocation of `sdd-coordinator` begins with the same two actions, regardless of whether this is a fresh run or a resume:

1. **Load `.sdd/config.yml`** if it exists. Cache the values (paths, preflight options, grill cap, handoff toggle, finishing mode + test command, etc.) for use throughout the rest of the run. For scalar lookups, the coordinator can shell out to `scripts/get-config-value.sh <block> <key>`.

2. **Invoke `inspecting-state`** to find active SDD runs. This skill returns a structured report listing every state file under `<spec_dir>/*/state.json` (honoring `paths.spec_dir` config), validates each against the canonical schema (`scripts/state-schema.md` and `.json`), reports the current branch alongside each state's `branch` field, and surfaces pre-state-file interruption signals — but only when the current branch matches an SDD pattern (`feat/*` or `fix/*`) AND no active state files exist anywhere.

The coordinator's decision tree depends on BOTH the report AND the current branch's relationship to the active state(s):

| Report says | Coordinator does |
|---|---|
| 0 active runs + on `main`/`master` + clean tree | Confirm fresh-start intent, then proceed to Stage 0 |
| 0 active runs + pre-state interruption flagged | Ask user: resume from Stage 1, start fresh, or abandon. Never silently pick. |
| 1 active run + current branch matches `state.branch` | Confirm `"Resuming feature X at stage Y"`. On yes, jump to the appropriate stage. |
| 1 active run + current branch does NOT match `state.branch` | **Do NOT silently resume.** Ask: switch to the state's branch and resume, start a new feature on this branch (state file stays), or abort. Never auto-checkout branches. |
| 2+ active runs + current branch matches one | Offer to resume the matching one, or pick a different one, or start fresh on this branch. |
| 2+ active runs + current branch matches none | List them with their branches; ask which to resume or start fresh on the current branch. |
| Malformed state file | Show the issues. Offer: repair (user-guided), discard, or abort. |

**Rules across all routing:** the coordinator NEVER runs `git checkout` to switch branches on its own — if the user picks "switch and resume," it instructs them to switch and re-invoke (or, with explicit consent in this session, runs the checkout). Detached HEAD with any active state aborts (too ambiguous to route).

After this entry routing, the coordinator proceeds into the pipeline.

---

## Stage 0 — Preflight

**Skill:** `preflight-checks` (inline)
**Output:** verifies a clean working tree, ensures we're on an appropriate branch.

The skill checks `git status --porcelain` and `git branch --show-current`. The decision matrix is:

| Condition | Result |
|---|---|
| Dirty working tree | **ABORT** — tell user to commit/stash/discard manually, then re-invoke |
| Clean tree + on `main` or `master` | Create new feature branch `feat/<short-name>` (or `fix/...` for bug fixes), proceed |
| Clean tree + on a feature-like branch + matching state file exists | Resume on that branch |
| Clean tree + on a feature-like branch + no matching state file | **ABORT** — branch is ambiguous, user clarifies |
| Clean tree + on `develop`/`release/*`/`hotfix/*` | **ABORT** — protected branches; user switches first |
| Clean tree + on any other unrecognized branch | **ABORT** — user switches first |

There is no auto-commit, no stash, no checkout. The skill aborts on any unsafe condition. This is by design; magic cleanup is the failure mode we want to avoid.

If a worktree is configured (`.sdd/config.yml` → `preflight.use_worktree: true`), the skill commits the `.worktrees/` entry to `.gitignore` on the **base branch** (BEFORE creating the feature branch — keeps the gitignore commit out of every feature PR), then creates the feature branch, then creates a worktree under `.worktrees/<sanitized-branch>/` (slashes in branch names are flattened to dashes — `feat/user-auth` → `.worktrees/feat-user-auth/`). The worktree path is returned to the coordinator for later cleanup in Stage 15.

**State file does not exist yet.** Preflight outputs (branch, worktree path, original branch) are held by the coordinator in-memory. They get persisted into the state file in Stage 2.

**On abort:** the coordinator surfaces the abort message to the user and exits cleanly. No partial state is written. The user can re-invoke after fixing the underlying issue.

---

## Stage 1 — Discovering requirements

**Skill:** `discovering-requirements` (inline)
**Output:** shared understanding of the feature, held in the coordinator's conversation context.

This is the conversational stage. The skill drives a Q&A with the user — one question per message, multiple choice preferred where applicable, with a recommended answer when there's a clear best choice.

The skill walks through (and skips dimensions already covered by the user's initial description):

| Dimension | What gets discussed |
|---|---|
| Purpose | What problem is being solved, for whom |
| Users | Roles, journeys, motivations |
| Scope (in) | The smallest valuable slice |
| Scope (out) | What's deferred or out of bounds |
| Success | Measurable outcomes |
| Key entities | Domain objects involved (if any) |
| Edge cases | Negative paths, boundary conditions |
| Constraints | Tech stack, performance, security, compliance |
| Integration | External systems, APIs, dependencies |

**Major design decisions** with non-obvious tradeoffs are presented as 2-3 options with the skill's recommendation and reasoning. The user picks one. These decisions become candidates for ADRs in Stage 6.

**Scope check:** if the user's request actually describes multiple independent subsystems, the skill surfaces this early and recommends decomposition into separate SDD runs.

**Project context loading:** the skill runs `scripts/discover-context.sh` to find any project convention files (constitution, ADRs, ARCHITECTURE.md, glossary, domain model). If present, it loads them and uses the project's domain vocabulary throughout the conversation.

**Final confirmation:** when discovery is sufficient, the skill summarizes back in sections (goal, users, scope, success, entities, edge cases, decisions). The user approves each section before moving on.

**Hard gate:** the skill writes nothing to disk. The output is shared understanding in the coordinator's context. Stage 2 turns that understanding into the formal spec artifact.

---

## Stage 2 — Writing the spec

**Skill:** `writing-specs` (inline)
**Output:** `docs/specs/NNN-<short-name>/spec.md`, `docs/specs/NNN-<short-name>/state.json`

The coordinator passes the in-memory understanding from Stage 1 plus the preflight outcomes (branch, worktree path, original branch) to this skill. The skill:

1. Resolves the feature directory: scans `<spec_dir>/` (default `docs/specs/`) for the highest existing `NNN`, picks `NNN+1` (or `001` if none exist). Composes with the short name.
2. Loads project context (skip if coordinator already passed it).
3. Renders the spec following the opinionated structure (see [artifacts.md](artifacts.md) for the full spec format). Writes atomically — composes content, writes to `<spec_path>.tmp`, then `mv`.
4. Initializes the state file with the preflight outcomes and the spec path.
5. Runs `scripts/validate-spec.sh` against the new file. Fixes any CRITICAL issues until it passes. Validator catches duplicate FR/SC IDs, placeholders, missing sections, and forbidden diagram syntax.
6. Runs an inline fresh-eyes self-review for semantic issues the validator can't catch (internal consistency, testability, ambiguity, vocabulary drift).
7. Returns the spec path to the coordinator, **including the validator's PASS line verbatim** in the report. Coordinator re-runs the validator before committing; if results disagree, the stage halts.

**State file initial values:**

```json
{
  "feature_id": "NNN-<short-name>",
  "current_stage": "spec_writing",
  "stages_completed": ["preflight", "discovering"],
  "preflight": { "worktree_path": null, "original_branch": "main" }
}
```

Note: `current_stage` stays as `spec_writing` (still mid-stage from the skill's perspective). After the skill returns, the coordinator advances and adds `spec_written` to `stages_completed`.

**Commit:** the coordinator commits the spec and the state file in one commit:

```bash
git add docs/specs/NNN-<short-name>/spec.md docs/specs/NNN-<short-name>/state.json
git commit -m "spec(NNN-short-name): initial draft"
```

---

## Stage 3 — Auto spec-review

**Subagent:** `general-purpose` agent loaded with `reviewing-specs` skill
**Output:** structured findings report (returned to coordinator)

The coordinator dispatches a fresh subagent with a prompt like:

```
You are reviewing a spec for the SDD pipeline.

Use the `reviewing-specs` skill via the Skill tool.

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
CONTEXT_FILES:
  - docs/constitution.md (if present)
  - docs/adr/0001-*.md (and any other prior ADRs)
  - ARCHITECTURE.md (if present)
  - GLOSSARY.md (if present)
REVIEW_FOCUS: first-pass

Return your findings report.
```

The subagent reads the spec, all listed context files, and runs the detection passes specified in `reviewing-specs` (completeness, consistency, clarity, constitution alignment, scope, YAGNI, vocabulary). It returns findings categorized as CRITICAL / HIGH / MEDIUM / LOW.

**The coordinator processes the findings via `receiving-review-findings`** — a separate skill that establishes the protocol for evaluating reviewer output:

- Read all findings end-to-end before reacting
- For each CRITICAL/HIGH: verify it's a real issue (read the cited section, check against project context), then fix or push back
- For MEDIUM: fix if trivial; otherwise document in spec's Open Questions or accept
- For LOW: usually skip
- Never use performative agreement language ("you're right!"); state the fix or push back

If the coordinator pushes back on a finding, the rationale is logged in the state file's `reviewer_pushbacks` array.

**Fix-loop cap: 2 iterations (hard ceiling).** If iteration 2's re-dispatch still surfaces CRITICAL/HIGH findings, the coordinator follows `receiving-review-findings` Step 8 (escalation protocol):

- Surface the fix history (what was attempted in each iteration) and currently-unresolved findings to the user
- Offer four options: (1) iterate with user guidance (user dictates exact edits; no further auto-review), (2) override the reviewer (each push-back recorded with user's reason), (3) accept current state with known issues (records `reviewer_pushbacks` with "accepted with known issues"), (4) abort the stage and pause SDD
- Wait for explicit selection; never silently dispatch a third iteration

**Advance condition:** Approved by the reviewer, OR all findings handled per the protocol above with the coordinator's confidence (CRITICAL/HIGH resolved or push-backs justified).

---

## Stage 4 — 2nd spec-review (optional, user-gated)

**Subagent:** same as Stage 3, with `REVIEW_FOCUS: second-pass`
**Output:** structured findings report

The coordinator asks:

> "Spec auto-review passed. Want a second-pass review for extra rigor? (yes/no, default no)"

On `no`: `spec_second_review` is added to `stages_skipped`. Skip to Stage 5.

On `yes`: optionally ask the user to specify a focus (e.g., "security implications", "edge cases", "API design"). Dispatch a fresh `reviewing-specs` subagent with `REVIEW_FOCUS: second-pass — focus on <whatever>`. Process findings via `receiving-review-findings` exactly like Stage 3.

**Why a second pass?** Two reasons:
1. A different angle catches issues the first pass missed.
2. The user explicitly chose to invest more rigor — that signal matters; the workflow honors it.

**Why not always run a 2nd pass?** Diminishing returns. For most features the first pass is enough.

---

## Stage 5 — Grill session (optional, user-gated)

**Skill:** `grilling-specs` (inline)
**Output:** updated `spec.md` (atomic per-answer save)

The coordinator asks:

> "Want a grill session to stress-test the spec? It'll ask scoped questions and update the spec inline. (yes/no, default no)"

On `no`: `spec_grill` added to `stages_skipped`. Skip to Stage 6.

On `yes`: load `grilling-specs`. The skill:

1. Loads the current spec and project context.
2. Builds an internal queue of prioritized questions across categories (goal sharpness, story priority rationale, acceptance testability, FR coverage, SC measurability, entity completeness, edge case depth, constraint rigor, integration risk, constitution/ADR fit, out-of-scope explicitness).
3. Asks questions one at a time, each with a recommended answer.
4. **After every accepted answer:**
   - Adds a Clarifications log entry in the spec
   - Applies the substance to the appropriate spec section
   - **Saves the spec immediately (atomic)** so an interruption doesn't lose anything
5. Stops when: user says done, all high-impact areas resolved, OR hits the cap (default 10 questions; configurable; hard ceiling 20).

**Why inline (not subagent)?** Grilling is a multi-turn user conversation. Subagents can't have back-and-forth with the user — they take a prompt and return a result. So this stage runs in the coordinator's session.

**Commit:** after the grill, the coordinator commits the updated spec:

```bash
git add docs/specs/NNN-<short-name>/spec.md
git commit -m "spec(NNN-short-name): grill session updates"
```

---

## Stage 6 — ADR maintenance

**Subagent:** `general-purpose` agent loaded with `maintaining-adrs` skill
**Output:** zero or more new ADR files at `docs/adr/NNNN-<title>.md`, possibly updates to existing ADRs (supersession markers)

The coordinator dispatches with:

```
You are maintaining ADRs for the SDD pipeline.

Use the `maintaining-adrs` skill via the Skill tool.

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
ADR_DIR: docs/adr (or config override)
EXISTING_ADRS: [list of all current ADR paths]
DECISIONS_CAPTURED: [list of decisions the coordinator flagged during discovery]

Return the result.
```

The subagent:

1. Reads the spec and every existing ADR.
2. Identifies decisions in the spec that qualify as ADR-worthy (architectural, with real alternatives, where reasoning isn't self-evident).
3. Cross-checks against existing ADRs — no duplicates.
4. For each qualifying decision, writes a new ADR using the locked format (Title / Status / Date / Spec link / Context / Decision / Consequences / Alternatives Considered).
5. For supersession cases: updates the older ADR's status to "Superseded by ADR-NNNN" and writes the new one with "Supersedes: ADR-NNNN".
6. Returns a structured result including paths created, paths modified, and decisions skipped (with reasons).

**Zero ADRs is a valid outcome.** Not every spec contains architecturally significant decisions. The subagent should return "0 ADRs created" with a one-sentence explanation when that's the case.

**Commit (if any ADRs created/modified):**

```bash
git add docs/adr/<new files> [docs/adr/<modified ones>]
git commit -m "docs(adr): NNNN-NNNN from spec NNN-short-name"
```

ADRs are written with `Status: Proposed`. Stage 7's default behavior on approval flips them to `Accepted`.

---

## Stage 7 — User spec approval

**Inline (coordinator)**
**Output:** user approval, ADR statuses flipped (default) or kept (explicit opt-out), commit of any final changes

The coordinator tells the user:

> "Spec and ADRs are ready for your review:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list with paths]
>
> Please let me know one of:
> - **Approve** — flip ADRs to Accepted and proceed (default for spec approval)
> - **Approve, keep ADRs as Proposed** — proceed but leave ADR statuses untouched
> - **Request changes** — tell me what to change"

The user reads the files and responds. Possibilities:

- **Approve** (default flow): the coordinator flips every ADR file's status from `Proposed` to `Accepted`, commits, advances to Stage 8.
- **Approve, keep ADRs as Proposed**: ADRs stay as-is; the coordinator commits state.json advancement only and proceeds to Stage 8.
- **Request changes**: classify before applying.
  - **Light-touch edit** (typo, wording, tightening an FR, adding an edge case, ADR text adjustment): apply inline using `receiving-review-findings` discipline, re-run validator, re-ask.
  - **Substantive — re-discovery needed** (decomposition, fundamental requirement change, story added/removed, big rethink): do NOT edit inline. Confirm with user, then reset `current_stage` to `discovering` and re-enter Stage 1. The new discovery may produce a revised spec that supersedes the current one.
  - **Substantive — ADR overhaul** (an ADR needs replacing, or new ADR-worthy decisions emerge): re-dispatch `maintaining-adrs` after any spec changes; the subagent handles supersession.
  - If unsure, default to light-touch and apply inline; if it becomes clear the change is substantive, stop and reclassify.
- **Reject and abandon**: coordinator exits the pipeline; user decides what to do with the work-in-progress branch.

**Why "flip by default":** leaving ADRs `Proposed` after a shipped feature creates stale statuses users forget to update. The "keep as Proposed" option exists for the rare case where the ADR needs more deliberation but the spec is fine.

**Hard gate:** the coordinator does NOT advance to Stage 8 without explicit user approval.

---

## Stage 8 — Writing the plan

**Skill:** `writing-plans` (inline)
**Output:** `docs/specs/NNN-<short-name>/plan.md`, updated `state.json`

The skill:

1. Reads the approved spec in full.
2. Loads project context (constitution / ADRs from this run / architecture / glossary).
3. Writes the plan header (title, feature ID, spec link, status, goal, architecture, tech stack).
4. Maps out the file structure (which files get created/modified, one-line responsibility each).
5. Decomposes work into tasks, organized into phases:
   - Phase 1: Setup
   - Phase 2: Foundational (blocking prerequisites)
   - Phase 3+: One phase per user story in priority order (P1 first)
   - Final Phase: Polish
6. Each task gets `[T###]` ID, optional `[P]` parallel marker, `[US#]` story label, exact file paths, `**Requirements:**` traceability to spec FRs, and bite-sized TDD steps with actual code + commands + expected output + commit messages.
7. Runs `scripts/validate-plan.sh` until it passes.
8. Runs an inline fresh-eyes self-review for semantic issues.
9. Returns the plan path.

**[NO-TDD] discipline:** see [operations.md](operations.md) for the strict criteria. Reviewers in Stage 9 flag misuse as CRITICAL.

**Atomic write:** the plan content is written to `<plan_path>.tmp` and atomically moved to the final path.

**Validator enforcement:** `writing-plans` returns the validator's PASS line verbatim in its report. The coordinator re-runs `validate-plan.sh` before committing — if the fresh run disagrees with the writer's report, the stage halts. Validator catches duplicate T### IDs, placeholders, missing required sections, and forbidden diagram syntax.

**Commit:**

```bash
git add docs/specs/NNN-<short-name>/plan.md docs/specs/NNN-<short-name>/state.json
git commit -m "plan(NNN-short-name): initial draft"
```

---

## Stage 9 — Auto plan-review

**Subagent:** `general-purpose` agent loaded with `reviewing-plans` skill
**Output:** structured findings report

Same pattern as Stage 3. The subagent runs detection passes specific to plans:
- **Spec coverage** (every FR has at least one task)
- **Placeholders** (no "TBD", "implement later", etc.)
- **Type/name/path consistency** across tasks
- **TDD discipline** (Red-Green-Refactor present; `[NO-TDD]` matches allowed categories)
- **`[P]` correctness** (parallel-marked tasks don't share files)
- **Story independence** (each story phase produces a working increment standalone)
- **Constitution/ADR alignment**
- **Granularity** (tasks bite-sized, 2-5 minutes each)

The coordinator processes findings via `receiving-review-findings`. Fix-loop cap: 2 iterations (hard). At cap, same escalation protocol as Stage 3 — user picks from iterate-with-guidance / override / accept-with-known-issues / abort.

---

## Stage 10 — 2nd plan-review (optional, user-gated)

Same pattern as Stage 4. Asked: `"Want a second-pass plan review? (yes/no, default no)"`. If yes, dispatch with `REVIEW_FOCUS: second-pass`.

---

## Stage 11 — User plan approval

**Inline (coordinator)**

The coordinator tells the user:

> "Plan ready for review: docs/specs/NNN-<short-name>/plan.md
> Approve to start implementation, or request changes."

Possibilities:

- **Approve**: commit, advance to Stage 12.
- **Request changes**: coordinator applies inline, re-validates, re-asks.
- **Loop back to spec**: if the plan reveals a spec gap, the coordinator can return to earlier stages. (Practically rare — Stage 9 should catch most issues.)
- **Reject and abandon**: coordinator exits.

**Hard gate:** no implementation without approval.

---

## Stage 12 — Implementation

**Skill:** `implementing-plans` (inline; orchestrates subagents)
**Output:** code changes, commits, updated `state.json` per task

The skill drives the per-task loop. For each task in plan order:

**On entry:** the skill reads existing state. If `tasks` has any entries (resume case), it merges with the plan's task list — preserving `completed` and `in_progress` statuses — instead of overwriting them. It then starts at the first `in_progress` task, or the first `pending` task if none in-progress. Completed tasks are skipped.

1. **Mark task in-progress**: state file updates `tasks[T###]: "in_progress"` (atomic write).

2. **Dispatch implementer subagent** using the `implementer-prompt.md` template, filled with:
   - `{TASK_ID}`
   - `{TASK_TEXT}` — full task text from the plan, pasted inline (the subagent doesn't re-read the plan file)
   - `{CONTEXT}` — scene-setting (story it serves, prior tasks it depends on, architectural notes)
   - `{SPEC_PATH}`, `{PLAN_PATH}` — for targeted lookups only (e.g., verifying a cited `**Requirements:** FR-NNN`)
   - `{WORKING_DIR}` — repo root or worktree path

   The implementer subagent uses the `implementing-task` skill for guidance. If anything in the task is unclear, the implementer returns `NEEDS_CONTEXT` immediately (with what they need / what they tried / what they'd do if forced to guess) — they do NOT proceed and guess. The four statuses:

   | Status | Coordinator action |
   |---|---|
   | DONE | Proceed to spec-compliance review |
   | DONE_WITH_CONCERNS | Read concerns. If about correctness/scope: re-dispatch implementer with concerns appended. If observations only: note and proceed. |
   | NEEDS_CONTEXT | Read the "What you need / tried / forced-guess" sections; provide the missing context inline (from spec/plan); re-dispatch a fresh implementer with the answer appended. If the controller can't answer without user input, surface to user. Never auto-decide on the "forced guess" without confirming. |
   | BLOCKED | Assess: more context, more capable model, smaller pieces, or escalate to user. If commit failure (hook rejection, signing, missing identity), surface the commit error per the Commit Failure Protocol — never bypass with `--no-verify`. |

3. **Dispatch spec-compliance reviewer** using `spec-compliance-reviewer-prompt.md` (dispatch envelope calling the `reviewing-task-compliance` skill). Inputs: task text, `SPEC_PATH`, `PLAN_PATH`, git SHA range. Returns Approved or Issues Found. If Issues Found, re-dispatch a fresh implementer with the findings appended; re-review. Cap: 3 iterations.

4. **Dispatch code-quality reviewer** (only after spec-compliance Approved) using `code-quality-reviewer-prompt.md` (calls the `reviewing-task-quality` skill). Returns findings categorized Critical / Important / Minor. Critical and Important block; Minor is noted but doesn't block. Cap: 3 iterations.

5. **Mark task complete**: state file updates `tasks[T###]: "completed"`.

After all tasks: dispatch a **final code reviewer** using the same code-quality prompt with `TASK_ID=final` and the branch-wide SHA range. The `reviewing-task-quality` skill has explicit "When TASK_ID is `final`" guidance — the reviewer expects a multi-file diff, prioritizes cross-cutting concerns (inconsistencies between tasks, integration points, cumulative drift), and de-prioritizes per-task issues.

Once final review passes, write `final_review_completed: true` to state file.

**Continuous execution:** the coordinator does NOT pause between tasks for human check-in. Only reasons to stop:
- A BLOCKED status that can't be resolved
- A review loop hit its 3-iteration cap
- The plan itself appears wrong
- All tasks complete

**Why fresh subagents per task?**
- No context pollution between tasks
- Per-task context budgets stay small
- Subagents can ask focused questions without scrolling through history

**Why two-stage review per task?**
- Spec compliance asks: did you do exactly what the task said?
- Code quality asks: is the code well-built?
- Conflating them produces noisier, less useful feedback

---

## Stage 13 — Feature testing (optional, user-gated)

**Skill:** `testing-implementation` (inline; orchestrates subagents)
**Output:** test result in `state.json`

The coordinator asks:

> "Implementation complete. Run feature-level tests now? (yes/no, default yes — recommended for any feature with observable behavior)"

This is feature-level verification, distinct from per-task unit tests (those ran during implementation as part of TDD).

On `no`: `testing` added to `stages_skipped`. Advance to Stage 14.

On `yes`:

1. **Determine feature type** from the plan's file structure: UI-only / Backend-only / Library-or-CLI / Mixed. (If uncertain, classify as Mixed.)

2. **Dispatch tester subagent** with `tester-prompt.md`. The subagent inventories what tools are actually available (browser MCP for UI, DB MCP for backend, project test runners always), picks a strategy:
   - **UI**: walk acceptance scenarios via browser MCP
   - **Backend**: run test runner + HTTP requests + DB state checks
   - **Library/CLI**: drive directly via Bash
   - **Mixed**: run both UI and backend strategies
   - **Fallback**: if no relevant MCP is available, report `MCP_UNAVAILABLE` with a manual test plan and code-review findings

3. **Handle the result:**

   | Status | Coordinator action |
   |---|---|
   | PASS | Update state, advance to Stage 14 |
   | FAIL | Dispatch fresh fixer subagent (using `fixer-prompt.md`) with the failure list. Re-test after fixes. Cap: 3 iterations. After 3, escalate to user. |
   | MCP_UNAVAILABLE | **CRITICAL: the coordinator MUST NOT try to test the feature itself.** Present the tester's manual test plan + code-review findings to the user. Ask whether to (a) run manual tests now, (b) skip testing and advance, (c) pause SDD so the user can configure the missing MCP. |

   This last rule is **load-bearing**: the testing-implementation skill repeats it in five different places. Coordinators that have access to Bash/Playwright/curl will be tempted to "just check the feature works." That's not their job; testing is delegated.

---

## Stage 14 — Generate handoff

**Subagent:** `general-purpose` agent loaded with `generating-handoff` skill
**Output:** `docs/handoff/YYYY-MM-DD-<short-title>.md`

The coordinator checks `.sdd/config.yml` → `handoff.enabled`. Default is `true`. If false, add `handoff` to `stages_skipped` and advance.

Otherwise, resolve `HANDOFF_DIR`:
- Default: `docs/handoff` (repo-relative; handoff will be committed)
- Override: `paths.handoff_dir` in config. May be a repo-relative path OR an absolute path (e.g., `/home/user/sdd-handoffs/`, `~/notes/sdd/`). If absolute (or resolves outside the repo), set `OUTSIDE_REPO=true` — the handoff file will NOT be staged or committed, only the path recorded in state.json.

Dispatch:

```
You are generating the handoff document for the SDD pipeline.

Use the `generating-handoff` skill via the Skill tool.

STATE_PATH: docs/specs/NNN-<short-name>/state.json
SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
PLAN_PATH: docs/specs/NNN-<short-name>/plan.md
ADR_PATHS: [list from state.adr_results]
BRANCH: <branch name>
BASE_SHA: <first commit on this branch>
HEAD_SHA: <current HEAD>
HANDOFF_DIR: docs/handoff (or config override)

Return the path to the generated handoff and a report.
```

The subagent:

1. Reads spec, plan, ADRs (titles only — links, not full content), and the state file.
2. Gets the git log between BASE_SHA and HEAD_SHA (commit count, file changes, notable commits).
3. Builds the handoff structure (Quick context, Source artifacts, What got built, Build highlights, Test status, Open concerns, "If you're continuing this work", Redactions, Files not to look at).
4. **Runs a redaction sweep** on every string going into the doc. Patterns redacted: OpenAI/Anthropic/AWS/GitHub tokens, JWT-shaped strings, URLs with embedded credentials, sensitive env-var value assignments, SSH private key markers, generic secret literals. Two-pass scan to catch redactions that reveal more redactions.
5. Validates via `scripts/validate-handoff.sh` (which also enforces redaction).
6. Writes the file atomically.

**The handoff is a bridge, not a duplicate.** It references the source artifacts (with one-line summaries) rather than restating them. The goal is to enable a fresh agent — or a human stepping in for PR iteration — to continue work without re-reading the entire spec + plan + ADR set.

**Validator enforcement:** the coordinator re-runs `validate-handoff.sh` on the now-final file before committing. If FAIL (especially "potential unredacted secret matching pattern"), halt and surface — do NOT commit a handoff that may contain secrets.

**Commit (if `OUTSIDE_REPO=false`):**

```bash
git add docs/handoff/YYYY-MM-DD-<title>.md docs/specs/NNN-<short-name>/state.json
git commit -m "docs(NNN-short-name): handoff document"
```

**If `OUTSIDE_REPO=true`** (handoff lives outside the repo): only state.json is committed (`"chore(NNN-short-name): record external handoff path"`); the user is told where the external handoff was written.

Record the handoff path in state file under `handoff_path` (absolute path if outside repo, otherwise repo-relative).

---

## Stage 15 — Finishing

**Skill:** `finishing-sdd` (inline)
**Output:** closes the run; merge / PR / keep / discard; deletes state file (unless "keep")

1. **Verify pre-finish state.** Re-run the project's test suite as a final sanity check. Resolution order: (a) `finishing.test_command` config override if set (preferred for Makefile-driven repos, nox/tox, monorepos, anything outside auto-detect), (b) auto-detect by file presence in priority order (`Makefile` → `package.json` → `Cargo.toml` → `pyproject.toml` → `setup.py` → `go.mod` → `pom.xml` → `build.gradle`), running the first match only — never multiple, (c) if nothing matches, ask the user (and offer to save their answer to `finishing.test_command`). If tests fail here, halt — don't offer finishing options until tests pass (or user explicitly overrides).

2. **Detect environment** (normal repo / linked worktree / detached HEAD).

3. **Determine mode** from `.sdd/config.yml` → `finishing.mode`:
   - `prompt` (default): interactive 4-option menu
   - `leave`: skip menu; leave branch as-is
   - `merge-local`: skip menu; merge into base branch
   - `pr`: skip menu; push + create PR
   - `auto`: pick automatically (PR if remote exists and PR command configured; else merge-local; else leave)

4. **Execute the choice:**

   **Merge locally** — checkout base branch, pull, merge feature branch. If the merge fails with conflicts (`git status` shows `UU` entries): STOP, tell user which files conflicted, do NOT auto-resolve. If the merge fails for other commit-related reasons (hook rejection, signing): STOP per the Commit Failure Protocol — never use `--no-verify`. If merge succeeded, run tests on the merged result. If pass: cleanup worktree (Step 6 below), delete feature branch. If fail: stop, let user resolve.

   **Push and create PR** — push branch, run configured PR command (default `gh pr create`). Worktree is preserved (user needs it for PR iteration). State file is deleted (SDD's work is done; further iteration is normal git work).

   **Keep as-is** — leave everything. State file is kept (work may continue via SDD later).

   **Discard** — requires typed `discard` confirmation. Checkout base branch, cleanup worktree, force-delete feature branch. Everything goes.

5. **Worktree cleanup** (only for Merge or Discard) — provenance check: only remove worktrees under `.worktrees/` whose path matches `preflight.worktree_path` in the state file. Run from main repo root: `git worktree remove <path>; git worktree prune`.

6. **Delete state file** (for Merge, PR, Discard — work is done from SDD's perspective). State file deletion is committed alongside the feature's final commits.

   For Keep: state file is preserved.

7. **Report** to user with the final summary.

---

## Stage-transition rules (across the whole pipeline)

- **State updates happen at stage boundaries, not mid-stage.** This makes interruption-recovery deterministic: if the state file says `current_stage: "implementing"` and `tasks: {T003: "in_progress"}`, the resume knows exactly what to do (continue T003).
- **Atomic writes** for every state file update: write to `state.json.tmp`, then `mv state.json.tmp state.json`.
- **Commits ride along** with stage transitions when there's a spec/plan/code change to commit. State file deltas don't get their own commits; they ride with the relevant content commit.
- **Squash-merge eats state file deltas.** If the project squashes on merge, the state file's history disappears at merge time — only the final spec, plan, ADRs, and handoff survive in main.

---

## What if you need to revise mid-pipeline?

The pipeline is forward-flowing by default, but you can iterate:

- **Spec changes during plan review (Stage 9-10)**: if the plan reviewer surfaces a spec gap, the coordinator can apply minor edits to the spec inline (re-running the spec validator) without going back through Stage 3. For substantive spec changes, the coordinator returns to Stage 8 (writing-plans) after the spec is updated — Stage 7 was already approved; the spec change is treated as a fix not a redo unless the user requests otherwise.

- **Plan changes during implementation (Stage 12)**: if a task surfaces a plan-level issue (e.g., a required file doesn't exist as the plan said it would), the coordinator surfaces to the user. The user may want to revise the plan and re-enter Stage 8, or override the issue manually.

- **Mid-implementation spec changes**: rare but possible. Treat as: pause Stage 12, revise spec inline (re-validate), revise plan inline (re-validate), then resume Stage 12 from where it left off. The state file's `tasks` map is preserved.

The pipeline doesn't prescribe a clean "loop back to earlier stage" mechanism for every case — that's deliberate. Real iteration is messier than a strict state machine accommodates, and the coordinator's judgment (plus user input on big calls) handles it.

---

## Resume semantics in detail

`inspecting-state` and the coordinator's resume protocol cover:

- **Mid-stage interruption**: the state file's `current_stage` shows the in-progress stage; `stages_completed` doesn't yet include that stage. The coordinator re-runs that stage from the start (the stage's work is idempotent-ish — re-writing a spec.md or re-dispatching a reviewer is safe).

- **Mid-task interruption (Stage 12)**: the `tasks` map shows `T003: "in_progress"`. The coordinator re-dispatches T003 from the start. Per-task work is fully isolated; re-dispatching is safe.

- **Pre-state-file interruption (between Stage 0 and Stage 2)**: no state file exists. `inspecting-state` detects this via the git-branch signal (non-default branch + no matching state). The coordinator asks the user whether to resume from Stage 1 or start fresh.

- **Cross-machine resumption**: pull the feature branch, re-invoke the coordinator. State file comes with the branch.

See [state-and-config.md](state-and-config.md) for the full state file schema and lifecycle.
