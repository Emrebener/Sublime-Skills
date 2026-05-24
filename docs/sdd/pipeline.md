# The SDD Pipeline

The pipeline is a strict 18-stage sequence (Stages 0-17) with several optional stages the user gates explicitly. The coordinator (`ss-sdd-coordinator`) drives the sequence; specific work is delegated to phase-skills (loaded inline) or subagents (dispatched in fresh context).

This document explains each stage in detail: what runs, what it produces, how failure is handled, and what the next stage expects.

> All stage numbers are stable references throughout the SDD documentation. Stage 7 is "user spec approval"; that's true in this doc, in the coordinator skill, in the state file's `stages_completed` array, everywhere.

## At a glance

| # | Stage | Mechanism | Optional? | Writes to disk? |
|---|---|---|---|---|
| 0 | Preflight | Inline via `ss-sdd-preflight-checks` | No | No (git state only) |
| 1 | Discovering requirements | Inline via `ss-sdd-discovering-requirements` | No | No (in-memory only) |
| 2 | Writing the spec | Inline via `ss-sdd-writing-specs` | No | `spec.md` (uncommitted), `.sublime-skills/state.json` (gitignored) |
| 3 | Auto spec-review | Subagent via `ss-sdd-reviewing-specs` | No | No (returns findings) |
| 4 | Grill session | Inline via `ss-sdd-grilling-specs` | **Yes** | `spec.md` (updates inline; uncommitted) |
| 5 | 2nd spec-review | Subagent via `ss-sdd-reviewing-specs` | **Yes** | No (returns findings) |
| 6 | ADR maintenance | Subagent via `ss-sdd-maintaining-adrs` | No | `docs/adr/NNNN-*.md` (zero or more; uncommitted) |
| 7 | User spec approval | Inline (coordinator) | No | Updates ADR statuses to Accepted (uncommitted) |
| 8 | Writing the plan | Inline via `ss-sdd-writing-plans` | No | `plan.md` (uncommitted), `.sublime-skills/state.json` (gitignored) |
| 9 | Auto plan-review | Subagent via `ss-sdd-reviewing-plans` | No | No (returns findings) |
| 10 | 2nd plan-review | Subagent via `ss-sdd-reviewing-plans` | **Yes** | No (returns findings) |
| 11 | User plan approval | Inline (coordinator) | No | No (approval gate; artifacts remain uncommitted) |
| 12 | Choosing feature branch + batch commit | Inline via `ss-sdd-choosing-feature-branch` | No | Optionally creates branch; batch-commits all SDD planning artifacts (spec, plan, ADRs) on the chosen branch |
| 13 | Implementation (sub-pipeline) | Per-task subagents | No | Code files and tests (committed per task); `state.json` updated atomically (never committed) |
| 14 | Feature testing | Subagent via `ss-sdd-testing-implementation` | **Yes** | `.sublime-skills/state.json` updated with test result (gitignored) |
| 15 | Handoff generation | Subagent via `ss-sdd-generating-handoff` | **Yes** | `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-*.md` |
| 16 | Memory file maintenance | Subagent via `ss-sdd-maintaining-memory-file` | **Yes** (auto-skips if no memory file configured/detected — no prompt in that case) | Possibly updates `CLAUDE.md` / `AGENTS.md` / etc. (often: no update) |
| 17 | Finishing | Inline via `ss-sdd-finishing` | No | Deletes `state.json` (no commit; gitignored) |

Subagent stages run with no inherited conversation context; the coordinator builds their prompts from scratch.

---

## Pipeline entry point

Every invocation of `ss-sdd-coordinator` begins with a quick resume check, then a todo-list build, then the pipeline. All halt checks (config validation, git repo presence, detached HEAD) live inside Stage 0 (`ss-sdd-preflight-checks`), not in this entry sequence.

1. **Resume check.** Check `.sublime-skills/state.json`:
   - **File not found** → fresh start. Confirm intent ("Start a new feature?") and proceed to Stage 0.
   - **File found** → ask "Resume `<feature_id>` at `<current_stage>`?". On yes, jump to the appropriate stage based on `current_stage`. On no, ask whether to start a fresh feature (overwriting the existing state file) or abort.

   No halts here. Bad-config / not-a-repo / detached-HEAD all fall through to Stage 0.

2. **Build the progress todo list** for the user's view.

After the entry sequence, the coordinator proceeds into the pipeline. **Stage 0 is the first stage** and the single home for every pre-pipeline halt check — config validation (`validate-config.sh`, HALT on non-zero), git repo presence, detached HEAD — plus a dirty-tree warning (proceed-or-abort confirmation, not an automatic abort). After Stage 0 returns ready, the config is known-valid and the coordinator caches values (paths, `branching.branch_pattern`, grill cap, memory file size budget) via `framework/get-config-value.sh` for use throughout the rest of the run.

### Commit timing (important)

Through Stages 2–11, SDD writes files (spec, plan, ADRs) but does **not** commit them — they live uncommitted in the working tree. (`state.json` lives at `.sublime-skills/state.json` and is gitignored, so it's never committed in any stage.) The `ss-sdd-choosing-feature-branch` skill at Stage 12 batch-commits the spec/plan/ADRs on the user's chosen branch in two thematic commits. From Stage 13 onward, commits happen normally per stage.

**Why:** Stage 12 is where the user decides which branch the work lives on. Committing earlier would force SDD to make a branch decision up front (or land commits on `main`/wherever the user happened to be).

**Tradeoff:** if you `git stash`, `git restore`, or change branches mid-pipeline (Stages 0–11), the uncommitted SDD artifacts may be displaced. Don't do destructive git operations on a run that hasn't reached Stage 12 yet.

---

## Stage 0 — Preflight

**Skill:** `ss-sdd-preflight-checks` (inline)
**Output:** validated `.sublime-skills/config.yml`, confirmed git repo, named branch, dirty-tree warning acknowledged (if applicable).

Stage 0 is a permissive validation gate. It runs in this order:

1. `validate-config.sh` — config presence and validity
2. `git rev-parse --git-dir` — confirm we're in a git repo
3. `git branch --show-current` — must be non-empty (no detached HEAD)
4. `git status --porcelain` — if non-empty, show files and ask the user to confirm proceeding (SDD will only commit its own artifacts via path-scoped `git add`; their other dirty files stay untouched)

The abort matrix:

| Condition | Result |
|---|---|
| `.sublime-skills/config.yml` missing | **ABORT** with `config_missing` — direct user to `ss-bs-bootstrapping-project` |
| `.sublime-skills/config.yml` invalid (`validate-config.sh` exit 1) | **ABORT** with `config_invalid` — surface validator output verbatim |
| Not a git repo (`git rev-parse --git-dir` fails) | **ABORT** with `not_a_git_repo` — direct user to `git init` |
| Detached HEAD | **ABORT** with `detached_head` — no branch to commit to |
| Dirty working tree + user declines | **ABORT** with `user_declined` |

**Stage 0 does NOT:**
- Create or switch branches (that's Stage 12's job)
- Abort on a dirty working tree (it warns and asks; if the user wants SDD to run on top of in-progress work, that's allowed)
- Abort on which branch you're on — any named branch is fine

**State file does not exist yet.** Preflight outputs (current branch) are held by the coordinator in-memory. They get persisted into the state file in Stage 2.

**On abort:** the coordinator surfaces the abort message to the user and exits cleanly. No partial state is written.

---

## Stage 1 — Discovering requirements

**Skill:** `ss-sdd-discovering-requirements` (inline)
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

**Project context loading:** the skill runs `framework/discover-context.sh` to find any project convention files (constitution, ADRs, ARCHITECTURE.md, glossary, domain model). If present, it loads them and uses the project's domain vocabulary throughout the conversation.

**Final confirmation:** when discovery is sufficient, the skill summarizes back in sections (goal, users, scope, success, entities, edge cases, decisions). The user approves each section before moving on.

**Hard gate:** the skill writes nothing to disk. The output is shared understanding in the coordinator's context. Stage 2 turns that understanding into the formal spec artifact.

---

## Stage 2 — Writing the spec

**Skill:** `ss-sdd-writing-specs` (inline)
**Output:** `docs/specs/NNN-<short-name>/spec.md`, `.sublime-skills/state.json`

The coordinator passes the in-memory understanding from Stage 1 to this skill. The skill:

1. Resolves the feature directory: scans `docs/specs/` for the highest existing `NNN`, picks `NNN+1` (or `001` if none exist). Composes with the short name.
2. Loads project context (skip if coordinator already passed it).
3. Renders the spec following the opinionated structure (see [artifacts.md](artifacts.md) for the full spec format). Writes atomically — composes content, writes to `<spec_path>.tmp`, then `mv`.
4. Initializes the state file with the feature ID, work type, paths, and initial stage markers.
5. Runs `framework/validate-spec.sh` against the new file. Fixes any CRITICAL issues until it passes. Validator catches duplicate FR/SC IDs, placeholders, missing sections, and forbidden diagram syntax.
6. Runs an inline fresh-eyes self-review for semantic issues the validator can't catch (internal consistency, testability, ambiguity, vocabulary drift).
7. Returns the spec path to the coordinator, **including the validator's PASS line verbatim** in the report. Coordinator re-runs the validator before committing; if results disagree, the stage halts.

**State file initial values:**

```json
{
  "feature_id": "NNN-<short-name>",
  "current_stage": "spec_writing",
  "stages_completed": ["preflight", "discovering"]
}
```

Note: `current_stage` stays as `spec_writing` (still mid-stage from the skill's perspective). After the skill returns, the coordinator advances and adds `spec_written` to `stages_completed`.

**No commit.** The spec stays uncommitted; `ss-sdd-choosing-feature-branch` (Stage 12) batch-commits it on the chosen branch. The state file is at `.sublime-skills/state.json` (gitignored — never committed).

---

## Stage 3 — Auto spec-review

**Subagent:** fresh subagent invoking `ss-sdd-reviewing-specs`
**Output:** structured findings report (returned to coordinator)

The coordinator dispatches a fresh subagent with a prompt like:

```
You are reviewing a spec for the SDD pipeline.

Use the `ss-sdd-reviewing-specs` skill.

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
CONTEXT_FILES:
  - docs/constitution.md (if present)
  - docs/adr/0001-*.md (and any other prior ADRs)
  - ARCHITECTURE.md (if present)
  - GLOSSARY.md (if present)
REVIEW_FOCUS: first-pass

Return your findings report.
```

The subagent reads the spec, all listed context files, and runs the detection passes specified in `ss-sdd-reviewing-specs` (completeness, consistency, clarity, constitution alignment, scope, YAGNI, vocabulary). It returns findings categorized as CRITICAL / HIGH / MEDIUM / LOW.

**The coordinator processes the findings via `ss-sdd-receiving-review-findings`** — a separate skill that establishes the protocol for evaluating reviewer output:

- Read all findings end-to-end before reacting
- For each CRITICAL/HIGH: verify it's a real issue (read the cited section, check against project context), then fix or push back
- For MEDIUM: fix if trivial; otherwise document in spec's Open Questions or accept
- For LOW: usually skip
- Never use performative agreement language ("you're right!"); state the fix or push back

If the coordinator pushes back on a finding, the rationale is logged in the state file's `reviewer_pushbacks` array.

**Fix-loop cap: 2 iterations (hard ceiling).** If iteration 2's re-dispatch still surfaces CRITICAL/HIGH findings, the coordinator follows `ss-sdd-receiving-review-findings` Step 8 (escalation protocol):

- Surface the fix history (what was attempted in each iteration) and currently-unresolved findings to the user
- Offer four options: (1) iterate with user guidance (user dictates exact edits; no further auto-review), (2) override the reviewer (each push-back recorded with user's reason), (3) accept current state with known issues (records `reviewer_pushbacks` with "accepted with known issues"), (4) abort the stage and pause SDD
- Wait for explicit selection; never silently dispatch a third iteration

**Advance condition:** Approved by the reviewer, OR all findings handled per the protocol above with the coordinator's confidence (CRITICAL/HIGH resolved or push-backs justified).

---

## Stage 4 — Grill session (optional, user-gated)

**Skill:** `ss-sdd-grilling-specs` (inline)
**Output:** updated `spec.md` (atomic per-answer save)

The coordinator asks:

> "Want a grill session to stress-test the spec? It'll ask scoped questions and update the spec inline. (yes/no, default no)"

On `no`: `spec_grill` added to `stages_skipped`. Skip to Stage 5.

On `yes`: load `ss-sdd-grilling-specs`. The skill:

1. Loads the current spec and project context.
2. Builds an internal queue of prioritized questions across categories (goal sharpness, story priority rationale, acceptance testability, FR coverage, SC measurability, entity completeness, edge case depth, constraint rigor, integration risk, constitution/ADR fit, out-of-scope explicitness).
3. Asks questions one at a time, each with a recommended answer.
4. **After every accepted answer:**
   - Always adds a Clarifications log entry in the spec (audit trail and resume anchor)
   - Picks a disposition: **Substantive change** (edits the affected section), **Confirms spec is already correct** (log only, no body edit), or **Out of scope / deferred** (log + maybe an Out-of-Scope line)
   - **Saves the spec immediately (atomic)** even when only the Clarifications log changed — that's the per-answer durable record that lets a resumed grill pick up cleanly
5. Stops when: user says done, all high-impact areas resolved, OR hits the cap (default 10 questions; configurable; hard ceiling 20).

**Why inline (not subagent)?** Grilling is a multi-turn user conversation. Subagents can't have back-and-forth with the user — they take a prompt and return a result. So this stage runs in the coordinator's session.

**No commit.** Spec edits stay uncommitted; `ss-sdd-choosing-feature-branch` (Stage 12) batch-commits the final spec on the chosen branch.

---

## Stage 5 — 2nd spec-review (optional, user-gated)

**Subagent:** same as Stage 3, with `REVIEW_FOCUS: second-pass`
**Output:** structured findings report

The coordinator asks:

> "Want a second-pass review for extra rigor? (yes/no, default no)"

On `no`: `spec_second_review` is added to `stages_skipped`. Skip to Stage 6.

On `yes`: optionally ask the user to specify a focus (e.g., "security implications", "edge cases", "API design"). Dispatch a fresh `ss-sdd-reviewing-specs` subagent with `REVIEW_FOCUS: second-pass — focus on <whatever>`. Process findings via `ss-sdd-receiving-review-findings` exactly like Stage 3.

**Why a second pass?** Two reasons:
1. A different angle catches issues the first pass missed — especially relevant now that the spec may have been substantively edited in the grill.
2. The user explicitly chose to invest more rigor — that signal matters; the workflow honors it.

**Why not always run a 2nd pass?** Diminishing returns. For most features the first pass plus the optional grill is enough.

---

## Stage 6 — ADR maintenance

**Subagent:** fresh subagent invoking `ss-sdd-maintaining-adrs`
**Output:** zero or more new ADR files at `docs/adr/NNNN-<title>.md`, possibly updates to existing ADRs (supersession markers)

The coordinator dispatches with:

```
You are maintaining ADRs for the SDD pipeline.

Use the `ss-sdd-maintaining-adrs` skill.

SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
ADR_DIR: docs/adr (hardcoded)
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

**No commit.** New/modified ADR files stay uncommitted; `ss-sdd-choosing-feature-branch` (Stage 12) batch-commits them.

ADRs are written with `Status: Proposed`. Stage 7's default behavior on approval flips them to `Accepted`.

---

## Stage 7 — User spec approval

**Inline (coordinator)**
**Output:** user approval; ADR statuses flipped (default) or kept (explicit opt-out) as in-place file edits (uncommitted — Stage 12 batch-commits them)

The coordinator tells the user:

> "Spec and ADRs are ready for your review:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list with paths]
>
> Please let me know one of:
> - **Approve** — flip ADRs to Accepted (in your working tree; commits happen at Stage 12) and proceed (default for spec approval)
> - **Approve, keep ADRs as Proposed** — proceed but leave ADR statuses untouched
> - **Request changes** — tell me what to change"

All artifact updates from approval (ADR status flips, any inline spec edits from "request changes") stay uncommitted in the working tree. Stage 12 (`ss-sdd-choosing-feature-branch`) batch-commits them on the chosen branch.

The user reads the files and responds. Possibilities:

- **Approve** (default flow): the coordinator flips every ADR file's status from `Proposed` to `Accepted` (file edits only — uncommitted), advances to Stage 8.
- **Approve, keep ADRs as Proposed**: ADRs stay as-is; the coordinator advances to Stage 8 (no commit).
- **Request changes**: classify before applying.
  - **Light-touch edit** (typo, wording, tightening an FR, adding an edge case, ADR text adjustment): apply inline using `ss-sdd-receiving-review-findings` discipline, re-run validator, re-ask.
  - **Substantive — re-discovery needed** (decomposition, fundamental requirement change, story added/removed, big rethink): do NOT edit inline. Confirm with user, then reset `current_stage` to `discovering` and re-enter Stage 1. The new discovery may produce a revised spec that supersedes the current one.
  - **Substantive — ADR overhaul** (an ADR needs replacing, or new ADR-worthy decisions emerge): re-dispatch `ss-sdd-maintaining-adrs` after any spec changes; the subagent handles supersession.
  - If unsure, default to light-touch and apply inline; if it becomes clear the change is substantive, stop and reclassify.
- **Reject and abandon**: coordinator exits the pipeline; user decides what to do with the work-in-progress branch.

**Why "flip by default":** leaving ADRs `Proposed` after a shipped feature creates stale statuses users forget to update. The "keep as Proposed" option exists for the rare case where the ADR needs more deliberation but the spec is fine.

**Hard gate:** the coordinator does NOT advance to Stage 8 without explicit user approval.

---

## Stage 8 — Writing the plan

**Skill:** `ss-sdd-writing-plans` (inline)
**Output:** `docs/specs/NNN-<short-name>/plan.md`, updated `.sublime-skills/state.json`

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
7. Runs `framework/validate-plan.sh` until it passes.
8. Runs an inline fresh-eyes self-review for semantic issues.
9. Returns the plan path.

**[NO-TDD] discipline:** see [operations.md](operations.md) for the strict criteria. Reviewers in Stage 9 flag misuse as CRITICAL.

**Atomic write:** the plan content is written to `<plan_path>.tmp` and atomically moved to the final path.

**Validator enforcement:** `ss-sdd-writing-plans` returns the validator's PASS line verbatim in its report. The coordinator re-runs `validate-plan.sh` — if the fresh run disagrees with the writer's report, the stage halts. Validator catches duplicate T### IDs, placeholders, missing required sections, and forbidden diagram syntax.

**No commit.** The plan stays uncommitted; `ss-sdd-choosing-feature-branch` (Stage 12) batch-commits it on the chosen branch. The state file is at `.sublime-skills/state.json` (gitignored — never committed).

---

## Stage 9 — Auto plan-review

**Subagent:** fresh subagent invoking `ss-sdd-reviewing-plans`
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

The coordinator processes findings via `ss-sdd-receiving-review-findings`. Fix-loop cap: 2 iterations (hard). At cap, same escalation protocol as Stage 3 — user picks from iterate-with-guidance / override / accept-with-known-issues / abort.

---

## Stage 10 — 2nd plan-review (optional, user-gated)

Same pattern as Stage 5. Asked: `"Want a second-pass plan review? (yes/no, default no)"`. If yes, dispatch with `REVIEW_FOCUS: second-pass`.

---

## Stage 11 — User plan approval

**Inline (coordinator)**

The coordinator tells the user:

> "Plan ready for review: docs/specs/NNN-<short-name>/plan.md
> Approve to choose a feature branch and start implementation, or request changes."

Possibilities:

- **Approve**: advance to Stage 12 (`ss-sdd-choosing-feature-branch`). No commit here — artifacts remain uncommitted through Stage 11.
- **Request changes**: coordinator applies inline, re-validates, re-asks.
- **Loop back to spec**: if the plan reveals a spec gap, the coordinator can return to earlier stages. (Practically rare — Stage 9 should catch most issues.)
- **Reject and abandon**: coordinator exits.

**Hard gate:** no Stage 12 without approval.

---

## Stage 12 — Choosing feature branch + batch commit

**Skill:** `ss-sdd-choosing-feature-branch` (inline)
**Output:** branch decided (and optionally created); two thematic commits landing all SDD planning artifacts on the chosen branch.

The skill asks the user a single 3-way prompt:

> About to start implementation for `<feature_id>`.
> You're currently on `<current-branch>`. Choose:
> 1. Create and switch to `<derived-name>` (from `branching.branch_pattern`) — recommended
> 2. Use a different branch name
> 3. Stay on `<current-branch>` — commits will land here

On options 1 or 2: validates the chosen name, checks for collision, runs `git checkout -b`. The uncommitted spec/plan/ADR files travel with the working tree to the new branch (this is just how git works — uncommitted changes follow you across `checkout`). `.sublime-skills/state.json` is gitignored, so it also stays put across the switch.

On option 3: no branch op.

Then the skill batch-commits in two thematic, **path-scoped** commits (skipping any whose paths don't exist):

```bash
# Commit 1 — spec + plan
git add docs/specs/NNN-<short-name>/spec.md docs/specs/NNN-<short-name>/plan.md
git commit -m "docs(NNN-short-name): spec and plan"

# Commit 2 — ADRs (skipped if none)
git add <each ADR path>
git commit -m "docs(adr): N decisions for NNN-short-name"
```

**Path-scoping is mandatory.** Never `git add .` / `git add -A` — the user's pre-existing dirty files (which preflight allowed) must stay untouched.

After commits, update `state.json` (`current_stage: implementing`, append `branch_chosen` to `stages_completed`, write `branch` if changed). Return to the coordinator.

**On abort** (`branch_creation_failed` / `user_declined` / `commit_failed`): surface and halt. The user resolves (e.g., delete the conflicting branch, fix a pre-commit hook) and re-invokes the coordinator.

---

## Stage 13 — Implementation (sub-pipeline)

**Skill:** `ss-sdd-implementing-plans` (inline; orchestrates subagents)
**Output:** code changes, commits, updated `state.json` per task

The skill drives the per-task loop. For each task in plan order:

**On entry:** the skill reads existing state. If `tasks` has any entries (resume case), it merges with the plan's task list — preserving `completed` and `in_progress` statuses — instead of overwriting them. It then starts at the first `in_progress` task, or the first `pending` task if none in-progress. Completed tasks are skipped.

1. **Mark task in-progress**: state file updates `tasks[T###]: "in_progress"` (atomic write).

2. **Dispatch implementer subagent** using the `implementer-prompt.md` template, filled with:
   - `{TASK_ID}`
   - `{TASK_TEXT}` — full task text from the plan, pasted inline (the subagent doesn't re-read the plan file)
   - `{CONTEXT}` — scene-setting (story it serves, prior tasks it depends on, architectural notes)
   - `{SPEC_PATH}`, `{PLAN_PATH}` — for targeted lookups only (e.g., verifying a cited `**Requirements:** FR-NNN`)
   - `{WORKING_DIR}` — repo root

   The implementer subagent uses the `ss-sdd-implementing-task` skill for guidance. If anything in the task is unclear, the implementer returns `NEEDS_CONTEXT` immediately (with what they need / what they tried / what they'd do if forced to guess) — they do NOT proceed and guess. The four statuses:

   | Status | Coordinator action |
   |---|---|
   | DONE | Proceed to spec-compliance review |
   | DONE_WITH_CONCERNS | Read concerns. If about correctness/scope: re-dispatch implementer with concerns appended. If observations only: note and proceed. |
   | NEEDS_CONTEXT | Read the "What you need / tried / forced-guess" sections; provide the missing context inline (from spec/plan); re-dispatch a fresh implementer with the answer appended. If the controller can't answer without user input, surface to user. Never auto-decide on the "forced guess" without confirming. |
   | BLOCKED | Assess: more context, more capable model, smaller pieces, or escalate to user. If commit failure (hook rejection, signing, missing identity), surface the commit error per the Commit Failure Protocol — never bypass with `--no-verify`. |

3. **Dispatch spec-compliance reviewer** using `spec-compliance-reviewer-prompt.md` (dispatch envelope calling the `ss-sdd-reviewing-task-compliance` skill). Inputs: task text, `SPEC_PATH`, `PLAN_PATH`, git SHA range. Returns Approved or Issues Found. If Issues Found, re-dispatch a fresh implementer with the findings appended; re-review. Cap: 3 iterations.

4. **Dispatch code-quality reviewer** (only after spec-compliance Approved) using `code-quality-reviewer-prompt.md` (calls the `ss-sdd-reviewing-task-quality` skill). Returns findings categorized Critical / Important / Minor. Critical and Important block; Minor is noted but doesn't block. Cap: 3 iterations.

5. **Mark task complete**: state file updates `tasks[T###]: "completed"`.

After all tasks: dispatch a **final code reviewer** using the same code-quality prompt with `TASK_ID=final` and the branch-wide SHA range. The `ss-sdd-reviewing-task-quality` skill has explicit "When TASK_ID is `final`" guidance — the reviewer expects a multi-file diff, prioritizes cross-cutting concerns (inconsistencies between tasks, integration points, cumulative drift), and de-prioritizes per-task issues.

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

## Stage 14 — Feature testing (optional, user-gated)

**Skill:** `ss-sdd-testing-implementation` (inline; orchestrates subagents)
**Output:** test result in `state.json`

The coordinator asks:

> "Implementation complete. Run feature-level tests now? (yes/no, default yes — recommended for any feature with observable behavior)"

This is feature-level verification, distinct from per-task unit tests (those ran during implementation as part of TDD).

On `no`: `testing` added to `stages_skipped`. Advance to Stage 15.

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
   | PASS | Update state, advance to Stage 15 |
   | FAIL | Dispatch fresh fixer subagent (using `fixer-prompt.md`) with the failure list. Re-test after fixes. Cap: 3 iterations. After 3, escalate to user. |
   | MCP_UNAVAILABLE | **CRITICAL: the coordinator MUST NOT try to test the feature itself.** Present the tester's manual test plan + code-review findings to the user. Ask whether to (a) run manual tests now, (b) skip testing and advance, (c) pause SDD so the user can configure the missing MCP. |

   This last rule is **load-bearing**: the ss-sdd-testing-implementation skill repeats it in five different places. Coordinators that have access to Bash/Playwright/curl will be tempted to "just check the feature works." That's not their job; testing is delegated.

---

## Stage 15 — Generate handoff (optional, user-gated)

**Subagent:** fresh subagent invoking `ss-sdd-generating-handoff`
**Output:** `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<short-title>.md`

The coordinator asks:

> "Generate a handoff document for this run? (yes/no, default yes — recommended when someone else may pick this up, or you'll iterate on it later in a fresh session)"

On `no`: `handoff` added to `stages_skipped`. Advance to Stage 16.

On `yes`, resolve `HANDOFF_DIR`:
- Location (fixed): `$HOME/.sublime-skills/handoffs/<repo-basename>/`. Always outside the repo; never staged or committed. The absolute path is recorded in `state.json`.

Dispatch:

```
You are generating the handoff document for the SDD pipeline.

Use the `ss-sdd-generating-handoff` skill.

STATE_PATH: .sublime-skills/state.json
SPEC_PATH: docs/specs/NNN-<short-name>/spec.md
PLAN_PATH: docs/specs/NNN-<short-name>/plan.md
ADR_PATHS: [list from state.adr_results]
BRANCH: <branch name>
BASE_SHA: <first commit on this branch>
HEAD_SHA: <current HEAD>
HANDOFF_DIR: $HOME/.sublime-skills/handoffs/<repo-basename> (resolved by coordinator)

Return the path to the generated handoff and a report.
```

The subagent:

1. Reads spec, plan, ADRs (titles only — links, not full content), and the state file.
2. Gets the git log between BASE_SHA and HEAD_SHA (commit count, file changes, notable commits).
3. Builds the handoff structure (Quick context, Source artifacts, What got built, Build highlights, Test status, Open concerns, "If you're continuing this work", Redactions, Files not to look at).
4. **Runs a redaction sweep** on every string going into the doc. Patterns redacted: OpenAI/Anthropic/AWS/GitHub tokens, JWT-shaped strings, URLs with embedded credentials, sensitive env-var value assignments, SSH private key markers, generic secret literals. Two-pass scan to catch redactions that reveal more redactions.
5. Validates via `framework/validate-handoff.sh` (which also enforces redaction).
6. Writes the file atomically.

**The handoff is a bridge, not a duplicate.** It references the source artifacts (with one-line summaries) rather than restating them. The goal is to enable a fresh agent — or a human stepping in for PR iteration — to continue work without re-reading the entire spec + plan + ADR set.

**Validator enforcement:** the coordinator re-runs `validate-handoff.sh` on the now-final file. If FAIL (especially "potential unredacted secret matching pattern"), halt and surface — do NOT proceed; the unredacted handoff is on disk but the run must not record its path in state until the user resolves.

After the handoff doc is written, the coordinator updates `state.json` with the `handoff_path` field (atomic on-disk write, no commit — `.sublime-skills/state.json` is gitignored). The handoff file itself lives outside the repo and was never committed in either design.

---

## Stage 16 — Maintain memory file (optional, user-gated)

**Subagent:** fresh subagent invoking `ss-sdd-maintaining-memory-file`
**Output:** possibly an updated agent memory file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.agents.md`); often, no update

Most features don't change project-level truth. This stage exists because when they DO, keeping the memory file in sync is a real, valuable chore that's tedious to do manually — and a stale memory file actively misleads future agents.

The coordinator resolves `MEMORY_FILE_PATH` first:
1. `memory_file.path` in config if set
2. Otherwise auto-detect at repo root in order: `CLAUDE.md` → `AGENTS.md` → `GEMINI.md` → `.agents.md`; first match wins
3. If neither config nor auto-detect finds a path: auto-skip (`memory_file` → `stages_skipped`); **no prompt** — there's nothing to maintain.

If a path was resolved, the coordinator asks:

> "Check memory file `<MEMORY_FILE_PATH>` for updates from this run? (yes/no, default yes — most runs result in 'no update needed', so this is cheap to say yes to)"

On `no`: `memory_file` added to `stages_skipped`. Advance to Stage 17.

On `yes`, dispatch the subagent with `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `MEMORY_FILE_PATH`, `CHARACTER_LIMIT` (from config, default 40000), and `EXISTING_CONTENT` (current file text, or empty if it doesn't exist yet).

The subagent reads spec + plan + ADRs and decides whether anything in this run changes what's true at the project level. **"No update needed" is the most common and correct outcome** — it should not feel obligated to write just because a feature shipped. When it does write:

- One-line rules over prose. Bullet lists over paragraphs.
- Lead with the verb / rule ("MUST validate inputs via the schema layer")
- Cite the ADR/spec when relevant
- No timestamps, no narrative, no transient content
- Respect the character cap — at 90% it warns; over 100% it refuses (must prune first)

Three outcomes:

| Status | Coordinator action |
|---|---|
| `updated` | Commit the memory file (path-scoped). If `MEMORY_FILE_PATH` is outside the repo: no commit; inform the user. Update `.sublime-skills/state.json` with `memory_file_updated: true` (atomic write, no commit). |
| `no update needed` | No commit; advance. Set `memory_file_updated: false`. |
| `skipped` | No memory file configured/detected. Add `memory_file` to `stages_skipped`. |

**Why this isn't part of handoff generation:** the handoff doc captures THIS feature's context (transient); memory file captures the PROJECT's stable truth. Different goals, different content rules, different update cadence. Conflating them produces a bloated memory file.

---

## Stage 17 — Finishing

**Skill:** `ss-sdd-finishing` (inline)
**Output:** summary report; state file deleted (no commit — `.sublime-skills/state.json` is gitignored).

SDD V1 explicitly does NOT manage branches or merges. Stage 17 is just bookkeeping:

1. **Validate state.** Read `.sublime-skills/state.json`. Confirm `implementation_complete` is in `stages_completed`. If `test_status` is `failed_escalated` (or absent and testing wasn't skipped), ask the user "Tests aren't in a passing state. Finish anyway?" before proceeding. (**No** final test re-run — Stage 14 was the test gate.)

2. **Print summary.** A structured report including: feature_id, short_name, started_at, current branch, spec/plan/handoff paths, ADRs created (count + IDs), tasks completed, test_status, memory_file_updated.

3. **Delete state file.** Plain `rm` — the file is gitignored, so no `git rm` and no commit:

   ```bash
   rm .sublime-skills/state.json
   ```

After Stage 17: the user decides what to do with the feature branch (merge, PR, leave it). SDD is done.

---

## Stage-transition rules (across the whole pipeline)

- **State updates happen at stage boundaries, not mid-stage.** This makes interruption-recovery deterministic: if the state file says `current_stage: "implementing"` and `tasks: {T003: "in_progress"}`, the resume knows exactly what to do (continue T003).
- **Atomic writes** for every state file update: write to `state.json.tmp`, then `mv state.json.tmp state.json`.
- **Commits ride along** with stage transitions when there's a spec/plan/code change to commit. The state file is never committed — `.sublime-skills/state.json` is gitignored, so state deltas live entirely on disk and have no git history.

---

## What if you need to revise mid-pipeline?

The pipeline is forward-flowing by default, but you can iterate:

- **Spec changes during plan review (Stage 9-10)**: if the plan reviewer surfaces a spec gap, the coordinator can apply minor edits to the spec inline (re-running the spec validator) without going back through Stage 3. For substantive spec changes, the coordinator returns to Stage 8 (ss-sdd-writing-plans) after the spec is updated — Stage 7 was already approved; the spec change is treated as a fix not a redo unless the user requests otherwise.

- **Plan changes during implementation (Stage 13)**: if a task surfaces a plan-level issue (e.g., a required file doesn't exist as the plan said it would), the coordinator surfaces to the user. The user may want to revise the plan and re-enter Stage 8, or override the issue manually.

- **Mid-implementation spec changes**: rare but possible. Treat as: pause Stage 13, revise spec inline (re-validate), revise plan inline (re-validate), then resume Stage 13 from where it left off. The state file's `tasks` map is preserved.

The pipeline doesn't prescribe a clean "loop back to earlier stage" mechanism for every case — that's deliberate. Real iteration is messier than a strict state machine accommodates, and the coordinator's judgment (plus user input on big calls) handles it.

---

## Resume semantics in detail

The coordinator's resume protocol covers two cases:

- **Mid-stage interruption**: the state file's `current_stage` shows the in-progress stage; `stages_completed` doesn't yet include that stage. On re-invocation, the coordinator asks whether to resume and (on yes) re-runs that stage from the start — the stages's work is idempotent-ish (re-writing a spec.md or re-dispatching a reviewer is safe).

- **Mid-task interruption (Stage 13)**: the `tasks` map shows `T003: "in_progress"`. The coordinator re-dispatches T003 from the start. Per-task work is fully isolated; re-dispatching is safe.

Resume is designed for picking up an interrupted run inside the same conversation (or shortly after, with `state.json` on disk as the bridge). Cross-machine resumption, multi-run juggling, and branch-mismatch recovery are explicitly out of scope — they're rare in practice and add complexity that doesn't pay for itself.

See [state-and-config.md](state-and-config.md) for the full state file schema and lifecycle.
