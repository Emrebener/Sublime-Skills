# The SDD Pipeline

The pipeline is a strict 12-stage sequence (Stages 0-11) with two optional stages the user gates explicitly. The coordinator (`ss-sdd-coordinator`) drives the sequence; specific work is delegated to phase-skills (loaded inline) or subagents (dispatched in fresh context).

This document explains each stage in detail: what runs, what it produces, how failure is handled, and what the next stage expects.

> All stage numbers are stable references throughout the SDD documentation. Stage 5 is "user spec approval"; that's true in this doc, in the coordinator skill, in the state file's `stages_completed` array, everywhere.

## At a glance

| # | Stage | Mechanism | Optional? | Writes to disk? |
|---|---|---|---|---|
| 0 | Preflight | Inline via `ss-sdd-preflight` | No | No (git state only) |
| 1 | Discovering requirements | Inline via `ss-sdd-discovering-requirements` | No | No (in-memory only) |
| 2 | Writing the spec | Inline via `ss-sdd-writing-specs` | No | `spec.md` (uncommitted), `.sublime-skills/state.json` (gitignored) |
| 3 | Auto spec-review | Subagent via `ss-sdd-reviewing-specs` | No | No (returns findings) |
| 4 | ADR maintenance | Subagent via `ss-sdd-maintaining-adrs` | No | `docs/adr/NNNN-*.md` (zero or more; uncommitted) |
| 5 | User spec approval | Inline (coordinator) | No | Updates ADR statuses to Accepted (uncommitted) |
| 6 | Writing the plan | Inline via `ss-sdd-writing-plans` | No | `plan.md` (uncommitted), `.sublime-skills/state.json` (gitignored) |
| 7 | Choosing feature branch + batch commit | Inline via `ss-sdd-choosing-feature-branch` | No | Optionally creates branch; batch-commits all SDD planning artifacts (spec, plan, ADRs) on the chosen branch |
| 8 | Implementation (sub-pipeline) | Per-task subagents + one final review | No | Code files and tests (committed per task); `state.json` updated atomically (never committed) |
| 9 | Feature testing | Subagent via `ss-sdd-testing-implementation` | **Yes** | `.sublime-skills/state.json` updated with test result (gitignored) |
| 10 | Memory file maintenance | Subagent via `ss-sdd-maintaining-memory-file` | **Yes** (auto-skips if no memory file configured/detected — no prompt in that case) | Possibly updates `CLAUDE.md` / `AGENTS.md` / etc. (often: no update) |
| 11 | Finishing | Inline via `ss-sdd-finishing` | No | Deletes `state.json` (no commit; gitignored) |

Subagent stages run with no inherited conversation context; the coordinator builds their prompts from scratch.

---

## Pipeline entry point

`ss-sdd-coordinator` is an LLM-driven state machine that runs end-to-end inside a single conversation. It starts at Stage 0 and advances through stages sequentially; conversation context tells it where it is, so there's no resume ceremony. The state file at `.sublime-skills/state.json` exists to carry data between stages and coordinate subagents — not to recover an interrupted run.

The coordinator drives progress through three sequential todo lists, each replacing the previous: (1) **pre-implementation** for Stages 0–7, built at Stage 0; (2) **per-task implementation** for Stage 8, where `ss-sdd-implementing-plans` replaces list 1 with one todo per plan task; (3) **post-implementation** for Stages 9–11, built when `ss-sdd-implementing-plans` returns. The post-implementation list includes its optional stages upfront — when the user opts out at a gate, the coordinator marks that todo `completed` and adds the stage to `stages_skipped`. This keeps each list focused on the work at hand rather than carrying stale stage bullets across the longest stage.

**Stage 0 is the single home for every pre-pipeline halt check** — config validation (`validate-config.sh`, HALT on non-zero), git repo presence, detached HEAD — plus a dirty-tree warning (proceed-or-abort confirmation, not an automatic abort). Once every check passes, Stage 0 creates `.sublime-skills/state.json` as a minimal shell (silently removing any orphan file from a dead prior pipeline first), then returns. After Stage 0 returns ready, the config is known-valid and the coordinator caches values (paths, `branching.branch_pattern`, memory file size budget) via `framework/get-config-value.sh` for use throughout the rest of the run.

### Commit timing (important)

Through Stages 2–6, SDD writes files (spec, plan, ADRs) but does **not** commit them — they live uncommitted in the working tree. (`state.json` lives at `.sublime-skills/state.json` and is gitignored, so it's never committed in any stage.) The `ss-sdd-choosing-feature-branch` skill at Stage 7 batch-commits the spec/plan/ADRs on the user's chosen branch in two thematic commits. From Stage 8 onward, commits happen normally per stage.

**Why:** Stage 7 is where SDD settles the feature branch (silently when unambiguous, with a prompt otherwise). Committing earlier would force a branch decision before `short_name` is known, or land commits on `main`/wherever the user happened to be.

**Tradeoff:** if you `git stash`, `git restore`, or change branches mid-pipeline (Stages 0–6), the uncommitted SDD artifacts may be displaced. Don't do destructive git operations on a run that hasn't reached Stage 7 yet.

---

## Stage 0 — Preflight

**Skill:** `ss-sdd-preflight` (inline)
**Output:** validated `.sublime-skills/config.yml`, confirmed git repo, named branch, dirty-tree warning acknowledged (if applicable).

Stage 0 is a permissive validation gate followed by state-shell creation. It runs in this order:

1. `validate-config.sh` — config presence and validity
2. `git rev-parse --git-dir` — confirm we're in a git repo
3. `git branch --show-current` — must be non-empty (no detached HEAD)
4. `git status --porcelain` — if non-empty, show files and ask the user to confirm proceeding (SDD will only commit its own artifacts via path-scoped `git add`; their other dirty files stay untouched)
5. Create `.sublime-skills/state.json` as a minimal shell (only after all checks above pass; any pre-existing state file is treated as an orphan from a dead prior pipeline and silently removed first)

The abort matrix:

| Condition | Result |
|---|---|
| `.sublime-skills/config.yml` missing | **ABORT** with `config_missing` — direct user to `ss-bs-bootstrapping-project` |
| `.sublime-skills/config.yml` invalid (`validate-config.sh` exit 1) | **ABORT** with `config_invalid` — surface validator output verbatim |
| Not a git repo (`git rev-parse --git-dir` fails) | **ABORT** with `not_a_git_repo` — direct user to `git init` |
| Detached HEAD | **ABORT** with `detached_head` — no branch to commit to |
| Dirty working tree + user declines | **ABORT** with `user_declined` |

**Stage 0 does NOT:**
- Create or switch branches (that's Stage 7's job)
- Abort on a dirty working tree (it warns and asks; if the user wants SDD to run on top of in-progress work, that's allowed)
- Abort on which branch you're on — any named branch is fine

**State file:** created by preflight as the last step (after all validation passes), containing only the always-required fields — `started_at`, `updated_at`, `current_stage: "preflight"`, empty `stages_completed` / `stages_skipped`, empty `tasks`. Feature-identifying fields (`feature_id`, `short_name`, `work_type`, `spec_path`) are filled in by `ss-sdd-writing-specs` at Stage 2. Preflight outputs (current branch) and cached config values are also held by the coordinator in-memory for downstream use.

**On abort:** the coordinator surfaces the abort message to the user and exits cleanly. No state file is written on abort — it's the last step, deliberately, so a failed preflight leaves no trace.

---

## Stage 1 — Discovering requirements

**Skill:** `ss-sdd-discovering-requirements` (inline)
**Output:** shared understanding of the feature held in the coordinator's conversation context, plus a structured end-of-stage summary in the agent's final message.

This is the conversational stage. The skill drives a Q&A with the user — one question per message, multiple choice preferred where applicable, with a recommended answer when there's a clear best choice. It runs in **four phases** with four **cross-cutting rules** applied throughout.

### Phase 1 — Context

Loads project conventions (constitution / ADRs / architecture / glossary / domain / README) via `framework/discover-context.sh`. Runs the initial scope check — if the request describes multiple independent subsystems, recommends decomposition into separate SDD runs. Classifies work type (`feature` or `fix`); inferred from initial input, asked only if ambiguous.

### Phase 2 — Framing probe

Four fixed probes, in order, each skippable only under narrow explicit conditions:

| # | Probe | Purpose |
|---|---|---|
| F1 | Driver / timing — "What's prompting this now?" | Distinguishes urgency from background priority |
| F2 | Alternatives considered — "What did you consider, why this?" | Catches single-option framings; forcing function: if user considered none, agent proposes 2–3 before continuing, and the resolved decision is tagged as an ADR candidate immediately |
| F3 | Substitute behavior — "What do users do today without this?" | Reveals real stakes and the true substitute |
| F4 | Concrete walkthrough — "Walk me through one real scenario" | Forces commitment to specifics; establishes the baseline scenario |

Framing answers reshape the entire feature; CC-1 (playback gate) is applied aggressively here. Decisions resolved at F2 are tagged as ADR candidates and Phase 3 will not re-propose them.

### Phase 3 — Targeted dimension walk

The skill walks the 9-dimension coverage checklist:

| Dimension | What gets covered |
|---|---|
| Purpose | Problem and who feels it |
| Users | Roles + triggers |
| Scope (in) | Smallest valuable slice |
| Scope (out) | Explicit deferrals |
| Success | At least one measurable outcome |
| Key entities | Domain objects (if any) |
| Edge cases | Top 3 failure modes |
| Constraints | Tech/perf/security/compliance |
| Integration | External dependencies + failure modes |

Every dimension must end Phase 3 with a stated answer or `N/A — <Phase 1 or Phase 2 signal>`. Free-form N/A is rejected. Depth per dimension is driven by signals from Phase 1 (constitution / ADRs) and Phase 2 (especially F4's walkthrough), not by a fixed quota.

**Major design decisions** with non-obvious tradeoffs are presented as 2–3 options with the skill's recommendation and reasoning. The user picks. The chosen decision (with rejected options and reasoning) is tagged as an ADR candidate for Stage 4.

**Graceful-unknown protocol:** if a dimension can't be resolved after reasonable drilling, the skill surfaces it as an Open Question with a proposed default and lets the user pick (accept the default / defer to Assumptions / defer to a follow-up spec). This is the recovery mechanism that prevents the Phase 4 stop gate from looping.

### Phase 4 — Synthesis

Four sub-steps:

- **Stop-and-summarize gate:** the agent runs a self-check before summarizing — "can I write a single paragraph naming the primary user, their trigger, what success looks like, and the top 3 ways this could go wrong?" If no, return to Phase 3.
- **Section-by-section approval:** sections are presented in order (Goal & problem → Users & flows → Scope → Success → Key entities → Edge cases & constraints → Major decisions), each with explicit user approval required before moving on. The Goal section is framed with its F1 driver (and F3 substitute, when load-bearing) inline as a parenthetical, so framing drift is cheap to spot.
- **Final confirmation:** the agent restates the one-paragraph summary and asks "ready to write this up?"
- **Structured end-of-stage summary:** the agent's final message to the coordinator is a fixed-shape block (`=== DISCOVERY SUMMARY === / === END SUMMARY ===`) covering `short_name`, `work_type`, `framing` (driver/alternatives/substitute_behavior/walkthrough), `dimensions` (all 9), `major_decisions` (ADR candidates with title / chosen / rejected / reasoning), `open_questions` (with disposition), and `approved_sections`. The structured shape exists for the agent's own self-discipline (forces every dimension to be actually stated) and for cleaner coordinator state; it is **not** a parse contract with Stage 2. The coordinator's existing in-memory handoff to Stage 2 and existing `DECISIONS_CAPTURED` dispatch to Stage 4 absorb the structured material via the same channels as today; no new dispatch parameters are introduced.

### Cross-cutting rules

Apply throughout Phases 2–4 as their triggers fire (not sequential steps). Full definitions in the skill's SKILL.md.

| Rule | Trigger |
|---|---|
| CC-1 — Playback gate | After any non-obvious user answer; paraphrase the implication before the next question |
| CC-2 — Contradiction watch | When two user answers imply different systems; surface and resolve |
| CC-3 — Adjacent-scenario invitation | When a Phase 3 dimension is stuck on abstractions after ≥2 exchanges; ask for a scenario *distinct* from F4 |
| CC-4 — Mid-conversation scope re-check | When the user adds independent functionality mid-discovery; re-run Phase 1's scope check |

### Hard gate

The skill writes nothing to disk. The output is shared understanding in the coordinator's context plus the structured end-of-stage summary in the agent's final message. Stage 2 turns that understanding into the formal spec artifact.

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

**No commit.** The spec stays uncommitted; `ss-sdd-choosing-feature-branch` (Stage 7) batch-commits it on the chosen branch. The state file is at `.sublime-skills/state.json` (gitignored — never committed).

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
  - docs/CONSTITUTION.md (if present)
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

This is the single spec-review pass. The discovery stage collects requirements reliably enough that one rigorous auto-review is sufficient; there is no separate grill or second-pass review.

---

## Stage 4 — ADR maintenance

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

**No commit.** New/modified ADR files stay uncommitted; `ss-sdd-choosing-feature-branch` (Stage 7) batch-commits them.

ADRs are written with `Status: Proposed`. Stage 5's default behavior on approval flips them to `Accepted`.

---

## Stage 5 — User spec approval

**Inline (coordinator)**
**Output:** user approval; ADR statuses flipped (default) or kept (explicit opt-out) as in-place file edits (uncommitted — Stage 7 batch-commits them)

The coordinator tells the user:

> "Spec and ADRs are ready for your review:
> - Spec: docs/specs/NNN-<short-name>/spec.md
> - ADRs (currently `Proposed`): [list with paths]
>
> Please let me know one of:
> - **Approve** — flip ADRs to Accepted (in your working tree; commits happen at Stage 7) and proceed (default)
> - **Request changes** — tell me what to change"

All artifact updates from approval (ADR status flips, any inline spec edits from "request changes") stay uncommitted in the working tree. Stage 7 (`ss-sdd-choosing-feature-branch`) batch-commits them on the chosen branch.

The user reads the files and responds. Two possibilities:

- **Approve** (default flow): the coordinator flips every ADR file's status from `Proposed` to `Accepted` (file edits only — uncommitted), advances to Stage 6.
- **Request changes**: the coordinator applies the requested edits inline to spec and/or ADRs, re-runs `validate-spec.sh`, and re-asks for approval. Loops until approved. The pipeline does not backtrack to earlier stages and there is no iteration cap. If the user's feedback is too big to apply inline (e.g., they realize this is the wrong feature entirely), the coordinator says so and the user decides whether to abandon and start a fresh session.

**Why flip on approval:** leaving ADRs `Proposed` after a shipped feature creates stale statuses users forget to update. If a particular ADR genuinely needs more deliberation, the right move is **Request changes** on that ADR — not shipping a still-Proposed decision.

**Hard gate:** the coordinator does NOT advance to Stage 6 without explicit user approval. This is the pipeline's single approval gate — the spec is the load-bearing artifact, so it is the one that gets an explicit sign-off. The plan that follows is rendered directly from the approved spec and is not separately reviewed or approved (mirroring how a brainstorming-then-plan flow trusts the plan once the requirements are settled).

---

## Stage 6 — Writing the plan

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

**[NO-TDD] discipline:** see [operations.md](operations.md) for the strict criteria. The plan writer's own Step 6 self-review flags misuse — there is no separate plan reviewer.

**Atomic write:** the plan content is written to `<plan_path>.tmp` and atomically moved to the final path.

**Validator enforcement:** `ss-sdd-writing-plans` returns the validator's PASS line verbatim in its report. The coordinator re-runs `validate-plan.sh` — if the fresh run disagrees with the writer's report, the stage halts. Validator catches duplicate T### IDs, placeholders, missing required sections, and forbidden diagram syntax.

**No plan review, no plan approval.** Once the plan validates, the coordinator advances straight to Stage 7. The plan is the "how" — a mechanical rendering of the already-approved spec — so it does not get its own review pass or approval gate. Issues in the plan surface and get fixed during implementation (Stage 8), and egregious quality problems are caught by the final cross-cutting review at the end of Stage 8.

**No commit.** The plan stays uncommitted; `ss-sdd-choosing-feature-branch` (Stage 7) batch-commits it on the chosen branch. The state file is at `.sublime-skills/state.json` (gitignored — never committed).

---

## Stage 7 — Settle feature branch + batch commit

**Skill:** `ss-sdd-choosing-feature-branch` (inline)
**Output:** feature branch decided (and optionally created/switched); `branch_name` persisted to state; two thematic commits landing all SDD planning artifacts on that branch.

The skill applies an opinionated rule against the current branch (`git branch --show-current`):

- **`CURRENT == <derived-name>`** (e.g., already on `feat/<short-name>`): **silent stay.** The user is deliberately building on top of an earlier partial implementation on this branch.
- **`CURRENT == "main"`** and the derived branch doesn't exist: **silent `git checkout -b <derived-name>`.** The happy path.
- **`CURRENT == "main"`** and the derived branch already exists: prompt — switch to existing (default) / pick a different name / abort.
- **Anything else** (e.g., `feat/some-other-feature`, `develop`): prompt — stay on current / create derived from current / abort. The prompt includes a mandatory **"merged to `main` and deleted at Stage 11"** warning on both proceeding options, since picking "stay" on a long-lived integration branch would delete it at Stage 11.

The derived name comes from `branching.branch_pattern` (default `feat/{short-name}`) with `{short-name}` substituted; if `state.work_type == "fix"` and the pattern starts with `feat/`, it's swapped to `fix/`. Uncommitted spec/plan/ADR files travel with the working tree across any `git checkout` (this is just how git works); `.sublime-skills/state.json` is gitignored so it also stays put across the switch.

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

After commits, update `state.json` atomically with `current_stage: implementing`, `branch_chosen` appended to `stages_completed`, and `branch_name: "<chosen branch>"` (read by Stage 11 to know what to merge). Return to the coordinator.

**On abort** (`branch_creation_failed` / `checkout_failed` / `user_declined` / `commit_failed`): surface and halt. The user resolves (e.g., delete the conflicting branch, fix a pre-commit hook) and tells the coordinator to continue — Stage 7 re-runs because `branch_chosen` isn't yet in `stages_completed`.

---

## Stage 8 — Implementation (sub-pipeline)

**Skill:** `ss-sdd-implementing-plans` (inline; orchestrates subagents)
**Output:** code changes, commits, updated `state.json` per task

The skill drives the per-task loop. For each task in plan order:

**On entry:** the skill reads existing state. Step 2 is idempotent: if `tasks` is empty, initialize every task as `"pending"`; if `tasks` already has entries (a prior iteration of this skill ran in the same conversation), preserve `completed` and `in_progress` statuses and merge new plan tasks as `"pending"`. It then starts at the first `in_progress` task (its prior implementer subagent died before reporting completion — re-dispatch is safe), or the first `pending` task if none in-progress. Completed tasks are skipped.

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
   | DONE | Mark task complete and advance to the next task. |
   | DONE_WITH_CONCERNS | Read concerns. If about correctness/scope: re-dispatch implementer with concerns appended. If observations only: note and proceed to the next task. |
   | NEEDS_CONTEXT | Read the "What you need / tried / forced-guess" sections; provide the missing context inline (from spec/plan); re-dispatch a fresh implementer with the answer appended. If the controller can't answer without user input, surface to user. Never auto-decide on the "forced guess" without confirming. |
   | BLOCKED | Assess: more context, more capable model, smaller pieces, or escalate to user. If commit failure (hook rejection, signing, missing identity), surface the commit error per the Commit Failure Protocol — never bypass with `--no-verify`. |

3. **Mark task complete**: state file updates `tasks[T###]: "completed"` as soon as the implementer reports DONE (or DONE_WITH_CONCERNS for observations only). There is no per-task review — the implementer's own TDD and self-review handle per-task discipline.

After all tasks: dispatch a single **final code reviewer** (mandatory) using the self-contained `final-review-prompt.md` template with the branch-wide SHA range. The prompt carries the full review protocol — it expects a multi-file diff, prioritizes cross-cutting concerns (inconsistencies between tasks, integration points, cumulative drift), and de-prioritizes isolated per-task issues. It is prompt-driven and loads no skill.

Once the final review passes, write `final_review_completed: true` to the state file. If the final review finds issues, address them (dispatch a fresh implementer with the findings) and re-review — cap 3 iterations, then escalate to the user.

**Continuous execution:** the coordinator does NOT pause between tasks for human check-in. Only reasons to stop:
- A BLOCKED status that can't be resolved
- The final-review fix loop hit its 3-iteration cap
- The plan itself appears wrong
- All tasks complete and the final review passes

**Why fresh subagents per task?**
- No context pollution between tasks
- Per-task context budgets stay small
- Subagents can ask focused questions without scrolling through history

**Why no per-task review?**
- A spec-compliance + code-quality reviewer pair *per task* multiplies subagent dispatches by the task count — on a 35-task plan that's 70 extra review passes, token-prohibitive for the value returned.
- The implementer's own TDD + self-review handles per-task correctness and scope, and the single mandatory final cross-cutting reviewer at the end catches systemic issues (inter-task inconsistency, integration drift) that per-task review can't see anyway.

---

## Stage 9 — Feature testing (optional, user-gated)

**Skill:** `ss-sdd-testing-implementation` (inline; orchestrates subagents)
**Output:** test result in `state.json`

The coordinator asks:

> "Implementation complete. Run feature-level tests now? (yes/no, default yes — recommended for any feature with observable behavior)"

This is feature-level verification, distinct from per-task unit tests (those ran during implementation as part of TDD).

On `no`: `testing` added to `stages_skipped`. Advance to Stage 10.

On `yes`:

1. **Ask testing depth.** `ss-sdd-testing-implementation` asks the user to pick `quick` (P1 golden paths only, no edge cases) or `standard` (P1 + listed edge cases, P2/P3 if cheap — the default). Anything other than `quick` is treated as `standard`. The choice is per-invocation only — not persisted to `state.json`.

2. **Determine feature type** from the plan's file structure: UI-only / Backend-only / Library-or-CLI / Mixed. (If uncertain, classify as Mixed.)

3. **Dispatch tester subagent** with `tester-prompt.md`, passing the chosen depth. The subagent inventories what tools are actually available (browser MCP for UI, DB MCP for backend, project test runners always), picks a strategy:
   - **UI**: walk acceptance scenarios via browser MCP
   - **Backend**: run test runner + HTTP requests + DB state checks
   - **Library/CLI**: drive directly via Bash
   - **Mixed**: run both UI and backend strategies
   - **Fallback**: if no relevant MCP is available, report `MCP_UNAVAILABLE` with a manual test plan and code-review findings

4. **Handle the result:**

   | Status | Coordinator action |
   |---|---|
   | PASS | Update state, advance to Stage 10 |
   | FAIL | Dispatch fresh fixer subagent (using `fixer-prompt.md`) with the failure list. Re-test after fixes. Cap: 3 iterations. After 3, escalate to user. |
   | MCP_UNAVAILABLE | **CRITICAL: the coordinator MUST NOT try to test the feature itself.** Present the tester's manual test plan + code-review findings to the user. Ask whether to (a) run manual tests now, (b) skip testing and advance, (c) pause SDD so the user can configure the missing MCP. |

   This last rule is **load-bearing**: the ss-sdd-testing-implementation skill repeats it in five different places. Coordinators that have access to Bash/Playwright/curl will be tempted to "just check the feature works." That's not their job; testing is delegated.

---

## Stage 10 — Maintain memory file (optional, user-gated)

**Subagent:** fresh subagent invoking `ss-sdd-maintaining-memory-file`
**Output:** possibly an updated agent memory file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.agents.md`); often, no update

Most features don't change project-level truth. This stage exists because when they DO, keeping the memory file in sync is a real, valuable chore that's tedious to do manually — and a stale memory file actively misleads future agents.

The coordinator resolves `MEMORY_FILE_PATH` first:
1. `memory_file.path` in config if set
2. Otherwise auto-detect at repo root in order: `CLAUDE.md` → `AGENTS.md` → `GEMINI.md` → `.agents.md`; first match wins
3. If neither config nor auto-detect finds a path: auto-skip (`memory_file` → `stages_skipped`); **no prompt** — there's nothing to maintain.

If a path was resolved, the coordinator asks:

> "Check memory file `<MEMORY_FILE_PATH>` for updates from this run? (yes/no, default yes — most runs result in 'no update needed', so this is cheap to say yes to)"

On `no`: `memory_file` added to `stages_skipped`. Advance to Stage 11.

On `yes`, dispatch the subagent with `SPEC_PATH`, `PLAN_PATH`, `ADR_PATHS` (from `state.adr_results`), `MEMORY_FILE_PATH`, `CHARACTER_LIMIT` (from config, default 40000), and `EXISTING_CONTENT` (current file text). Preflight's `validate-config.sh` halts on a configured-but-missing memory file (orphan path), so by Stage 10 the file is on disk or the path is null; if it's somehow missing here (e.g., deleted mid-run), the maintainer refuses via its pre-check — see the outcome table.

The subagent reads spec + plan + ADRs and decides whether anything in this run changes what's true at the project level. **"No update needed" is the most common and correct outcome** — it should not feel obligated to write just because a feature shipped. When it does write:

- One-line rules over prose. Bullet lists over paragraphs.
- Lead with the verb / rule ("MUST validate inputs via the schema layer")
- Cite the ADR/spec when relevant
- No timestamps, no narrative, no transient content
- Respect the character cap — at 90% it warns; over 100% it refuses (must prune first)

Outcomes:

| Status | Coordinator action |
|---|---|
| `updated` | Commit the memory file (path-scoped). If `MEMORY_FILE_PATH` is outside the repo: no commit; inform the user. Update `.sublime-skills/state.json` with `memory_file_updated: true` (atomic write, no commit). |
| `no update needed` | No commit; advance. Set `memory_file_updated: false`. |
| `skipped (no path configured)` | No memory file configured/detected. Add `memory_file` to `stages_skipped`. |
| `skipped (file missing on disk)` | Configured path points to a missing file (mid-run deletion or preflight bypass). Add `memory_file` to `stages_skipped`; surface the maintainer's hint to re-run `ss-bs-bootstrapping-project` or `ss-bs-auditing-project` to re-author. |

---

## Stage 11 — Merge to `main` and finish

**Skill:** `ss-sdd-finishing` (inline)
**Output:** merge commit on `main`; feature branch deleted; summary report; state file deleted (no commit — `.sublime-skills/state.json` is gitignored).

Stage 11 closes the source-control loop with a fixed local-only workflow:

1. **Validate state.** Read `.sublime-skills/state.json`. Confirm `implementation_complete` is in `stages_completed` and `branch_name` is set. If `test_status` is `failed_escalated` (or absent and testing wasn't skipped), ask the user "Tests aren't in a passing state. Finish anyway?" before proceeding. (**No** final test re-run — Stage 9 was the test gate.)

2. **Print summary.** A structured report including: feature_id, short_name, started_at, feature branch (about to be merged + deleted), spec/plan paths, ADRs created (count + IDs), tasks completed, test_status, memory_file_updated.

3. **Merge to `main` and delete the feature branch.** Hardcoded workflow — no prompts, no configuration:

   ```bash
   git checkout main
   git merge --no-ff "$branch_name" -m "Merge branch '$branch_name'"
   git branch -d "$branch_name"   # safe-delete; refuses if not fully merged
   ```

   On merge failure (conflicts, hook rejection, signing failure): halt and surface git's output verbatim. Do NOT auto-`git merge --abort`. Do NOT delete the branch. Do NOT `rm` the state file. The user resolves manually (complete the merge commit or `git merge --abort` and investigate), then tells the coordinator to continue. Stage 11 is naturally idempotent — `git merge --no-ff` on an already-merged branch returns 0 with "Already up to date" and the run completes.

   On `git branch -d` failure (branch unexpectedly not fully merged): halt and surface; do NOT escalate to `git branch -D`.

4. **Delete state file.** Plain `rm` — the file is gitignored, so no `git rm` and no commit:

   ```bash
   rm .sublime-skills/state.json
   ```

After Stage 11: SDD is done. The user is on `main`, the merge commit is in history, the feature branch is gone. No push — that's the user's call.

---

## Stage-transition rules (across the whole pipeline)

- **State updates happen at stage boundaries, not mid-stage.** This keeps the orchestration record consistent: if the state file says `current_stage: "implementing"` and `tasks: {T003: "in_progress"}`, the implementer-dispatch loop knows exactly which task is next (re-dispatch T003).
- **Atomic writes** for every state file update: write to `state.json.tmp`, then `mv state.json.tmp state.json`.
- **Commits ride along** with stage transitions when there's a spec/plan/code change to commit. The state file is never committed — `.sublime-skills/state.json` is gitignored, so state deltas live entirely on disk and have no git history.

---

## What if you need to revise mid-pipeline?

The pipeline is strictly forward-flowing — there is no backtracking to earlier stages. Issues surfaced after a stage has completed are fixed inline within the current stage's loop, re-validated with the matching script, and the loop continues. If a fix is too big to apply inline, the run is abandoned and the user starts a fresh session.

- **Spec gap surfaced while writing the plan (Stage 6)**: if the plan writer notices the spec is underspecified, the coordinator edits the spec inline (re-running `validate-spec.sh`) and continues. No return to earlier stages.

- **Plan changes during implementation (Stage 8)**: if a task surfaces a plan-level issue (e.g., a required file doesn't exist as the plan said it would), the coordinator edits the plan inline (re-running `validate-plan.sh`) and continues the per-task loop. If the issue can't be resolved by an inline edit, surface to the user, who decides whether to abandon.

- **Mid-implementation spec changes**: rare but possible. Pause Stage 8, edit the spec inline (re-validate), edit the plan inline (re-validate), then continue Stage 8 from where it left off. The state file's `tasks` map is preserved.

The "no backtracking" rule is deliberate. Backtracking through a multi-skill pipeline with state files is error-prone for both the coordinator and the skills, and the everyday case is small tweaks — which inline editing handles cleanly. Big rethinks are rare enough that "abandon and start fresh" is the right escape valve.

---

## What the state file is for

SDD runs end-to-end in one conversation, so there's no resume protocol. The state file at `.sublime-skills/state.json` exists for two concrete reasons:

- **Subagent orchestration.** Dispatched subagents die after they return; the coordinator records their structured outputs (`adr_results`, `tasks` transitions, `memory_file_*`, `reviewer_pushbacks`, etc.) into state so later stages and later subagents see them.
- **Per-task coordination at Stage 8.** Each task is a fresh implementer subagent; the `tasks` map is how `ss-sdd-implementing-plans` decides which task to dispatch next (a task at `"in_progress"` means its prior subagent died before reporting completion — re-dispatch from the start, since per-task work is fully isolated).

Two stages — Stage 7 (batch commit) and Stage 11 (`git merge --no-ff`) — can halt the pipeline mid-run; state stays on disk so the user can resolve the underlying issue and tell the coordinator to continue. Both stages are naturally idempotent on the second pass.

Cross-conversation resume, cross-machine recovery, multi-run juggling, and branch-mismatch recovery are explicitly out of scope.

See [state-and-config.md](state-and-config.md) for the full state file schema and lifecycle.
