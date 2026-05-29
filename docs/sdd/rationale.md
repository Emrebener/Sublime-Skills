# Design Rationale

Why we built SDD this way. Each decision explained, with the alternatives we considered and why we chose what we did.

## Contents

- [Why a 12-stage pipeline](#why-a-12-stage-pipeline)
- [Why thin coordinator + many skills](#why-thin-coordinator--many-skills)
- [Why no external skill dependencies](#why-no-external-skill-dependencies)
- [Why abort-only preflight](#why-abort-only-preflight)
- [Why split discovery and spec-writing](#why-split-discovery-and-spec-writing)
- [Why per-task subagent dispatch](#why-per-task-subagent-dispatch)
- [Why state file is gitignored](#why-state-file-is-gitignored)
- [Why ADRs over Constitution (initially)](#why-adrs-over-constitution-initially)
- [Why no diagrams](#why-no-diagrams)
- [Why strict `[NO-TDD]` criteria](#why-strict-no-tdd-criteria)
- [Why the coordinator doesn't test itself](#why-the-coordinator-doesnt-test-itself)
- [Why SDD owns the merge to `main` (closes the loop)](#why-sdd-owns-the-merge-to-main-closes-the-loop)
- [Why a separate skill for receiving review findings](#why-a-separate-skill-for-ss-sdd-receiving-review-findings)
- [Comparison: SDD vs spec-kit vs brainstorming vs Kiro](#comparison-sdd-vs-spec-kit-vs-brainstorming-vs-kiro)

---

## Why a 12-stage pipeline

A 12-stage pipeline sounds heavy (Stages 0-11). For trivial changes it might be overkill. We accepted that because the alternative — a flexible pipeline where stages can be skipped freely — fails predictably:

- AI agents tend to skip stages they shouldn't (especially review stages) when given the option
- Inconsistent application means inconsistent quality across features
- "Trivial" changes that turn out to be non-trivial don't get the rigor they need
- Optional stages compound: if every stage is optional, the pipeline degenerates to a chat

The pipeline as designed has **2 user-gated optional stages** (feature testing, memory-file maintenance — Stages 9, 10). Everything else is mandatory and requires editing the coordinator skill itself to bypass.

**Why this is OK in practice:** for genuinely small changes (a typo fix, a config bump), you wouldn't invoke SDD at all. SDD is for features that warrant structured development. The pipeline is calibrated for that scale.

---

## Why thin coordinator + many skills

The alternative would be one giant coordinator skill that contains all phase logic inline. We rejected this because:

- **Coordinator context bloat:** if every phase's instructions are loaded into the coordinator's context, the coordinator carries 5000+ lines of skill content at all times. Most of it is irrelevant to the current stage.
- **Coupling:** changes to phase logic require editing the coordinator, increasing risk of unintended side effects.
- **Reusability:** with phase logic in dedicated skills, individual skills (e.g., `ss-sdd-writing-specs`, `ss-sdd-reviewing-specs`) can be invoked outside the pipeline if needed.

The trade-off is more skill files to maintain (16 skills + 6 shared scripts + 2 schema files = 24 files) and the coordinator loading skills just-in-time. We judged this worth it.

**Concrete benefit:** the coordinator's SKILL.md is ~450 lines. The combined skills are ~5000 lines, but at any given moment only the active phase-skill is loaded. The coordinator stays a state machine + dispatcher.

---

## Why no external skill dependencies

The SDD family runs without any other skill family installed. We don't depend on `superpowers:*`, `kiro:*`, `skill-creator:*`, or anything else at runtime.

Reasons:
- **Portability:** users with different harness configurations can install just SDD without prerequisite chains.
- **Stability:** external skills can change in incompatible ways; we can't control that.
- **Clarity:** when something goes wrong, the failure mode is contained within SDD.

We did borrow design patterns extensively from external sources (Superpowers' per-task implementer dispatch, spec-kit's user-story priorities, Kiro's EARS format option, `receiving-code-review`'s no-performative-agreement rule). But we re-implemented them inside SDD rather than calling them.

**Exception:** Phase 4 of the build process (using `superpowers:writing-skills` to review our own skills) is a one-time meta step, not part of the runtime SDD workflow. That's allowed.

---

## Why abort-only preflight

Earlier versions of preflight tried to be helpful: auto-commit dirty files, auto-stash, auto-switch from main to a feature branch. We changed to abort-only because:

- **"Helpful" magic backfires.** Auto-stashing dirty files seems convenient until the user's stash conflicts on restore.
- **User intent is opaque.** Dirty files might be in-progress work, accidentally-edited files, or merge conflicts. The coordinator can't tell.
- **Aborting forces explicit intent.** When the user runs the coordinator again after cleaning up, they've consciously decided what to do with their working tree.
- **Safety > speed.** A 30-second clean-up by the user beats hours of debugging "where did my changes go?"

The downside is friction. First-time users will find it annoying ("just stash for me!"). We accept that — the friction is the point. It teaches the user that SDD requires a clean entry state, and they'll soon habitually `git stash` or `git commit` before invoking the coordinator.

---

## Why split discovery and spec-writing

Earlier versions had discovery and spec-writing in one stage. We split them because:

- **Different jobs need different skills.** Discovery is conversational Q&A with the user. Spec-writing is mechanical document generation. The methodologies don't overlap.
- **Reviewers see clearer work.** When `ss-sdd-reviewing-specs` reviews the spec, it sees a freshly-written document with no conversational drift, not a doc built up over a long Q&A.
- **Clearer hand-off.** The discovery stage has an explicit "shared understanding approved by user" exit point. The spec-writing stage takes that understanding and renders it. Two stages, one job each.

The cost is a small amount of coordinator overhead (advance from Stage 1 to Stage 2). The benefit is two much cleaner skills.

---

## Why per-task subagent dispatch

For Stage 8 implementation, every task gets one fresh implementer dispatch. After the last task, a single mandatory final cross-cutting code-quality review runs once over the whole branch diff.

The fresh-subagent pattern itself is expensive (subagent dispatch isn't free) and slow (sequential, not parallel). We use it because:

- **Context isolation.** Per-task subagents don't carry context from previous tasks. T002's design choices don't bleed into T003's work.
- **Smaller context budgets.** Each subagent's prompt + the relevant files fits comfortably in a small context window.
- **Resilience.** A misbehaving subagent doesn't poison the rest of the pipeline.

The cost is dispatch overhead and inability to parallelize within a task.

We considered an alternative: dispatch one subagent per task that does implementation + self-review, with the coordinator doing quality checks itself. We rejected this because the coordinator's context would get polluted with task-level details over time.

**Why no per-task review.** Each task gets no separate reviewer subagent. The implementer's own self-review (`ss-sdd-implementing-task` walks it through scope, tests, and commit hygiene before reporting DONE) plus the single mandatory final cross-cutting code-quality review at end of Stage 8 are the safety net. Per-task reviewers would double or triple Stage 8's wall-clock time for marginal gain — systemic issues (inconsistencies between tasks, integration drift, cumulative quality problems) show up at end-of-stage anyway, and a per-task reviewer can't see them. The final review is driven by a self-contained prompt template (`skills/spec-driven-development/ss-sdd-implementing-plans/final-review-prompt.md`) that loads no skill.

---

## Why state file is gitignored

The state file at `.sublime-skills/state.json` is never committed at any stage. It exists only in the working tree during an active SDD run and is deleted by `ss-sdd-finishing` via plain `rm` (no `git rm`, no commit).

Alternatives considered and rejected:

- **Committed state (original design).** We previously committed state.json from Stage 7 onward, with a deletion commit at Stage 11. Reasons cited at the time: durability across interruptions, git-log auditability of stage progression, and squash-merge collapsing the churn.
- **External state** (e.g., a database or a per-host `~/.sublime-skills-state/` directory). Adds storage management and decouples state from the per-project working tree.

Why the committed-state arguments don't hold under the project's actual design philosophy:

- **Durability across interruptions** — moot. SDD runs end-to-end inside one conversation; there's no resume case to make durable. The state file just needs to live on disk during the run as the data-carrier between stages. Cross-session, cross-machine, and post-reboot recovery are explicitly NOT supported.
- **Auditability** — marginal. The state-progression chore commits were never read by anyone; they were pure noise.
- **Squash-merge eats the noise** — not a benefit, just a neutralizer of cost. If state is never committed, there's no noise to eat.

Net benefit of gitignored state:

- Two pure-state chore commits eliminated per SDD run (Stage 8 implementation-complete chore, Stage 11 deletion chore).
- Two stage commits lose their state ride-along (Stage 7 spec+plan; Stage 10 memory file).
- Five stage-boundary commit-failure surfaces collapse to zero (no commit, no failure).
- Stages 2-6's "uncommitted state" rule extends to all stages — one rule, no exceptions.
- Branch operations no longer disturb state — gitignored files don't move with `git checkout`, and `git stash -u` skips them by spec.

The trade-off: no git-log marker for "SDD finished here." The committed spec / plan / ADRs ARE the artifact; the absence of a chore commit isn't a loss.

---

## Why ADRs over Constitution (initially)

`spec-kit` has a Constitution concept — a single file with project-wide principles. We considered including it but decided to start with ADRs only.

Reasons:
- **ADRs cover the same ground at finer grain.** Most "principles" are really "decisions" with broader scope.
- **Solo / small team scale.** Constitution is most useful when multiple developers need consistent guidance. For solo or small-team use, ADRs accumulate naturally.
- **Less governance ceremony.** Constitution requires authoring, versioning, propagation. ADRs are written one at a time.
- **`ss-bs-bootstrapping-project` does offer constitution authoring.** It's an opt-in artifact (with a dedicated `ss-bs-discovering-constitution` inline skill). Users who want it can add it; the pipeline reads it when present.

The pipeline reads CONSTITUTION.md if it exists (in stages where alignment matters). It's just not required, and we don't have a separate `maintaining-constitution` skill — yet.

If a project starts repeating the same guidance in every spec, that's the signal to add a constitution. The bootstrap skill makes it easy. We can add a `maintaining-constitution` skill later if patterns emerge.

---

## Why no diagrams

Specs and plans are prose-only. No Mermaid, no C4, no PlantUML, no ASCII art.

Reasons:
- **Diagrams encode information for human eyes.** LLMs read them as text and often miss the structure they're meant to convey.
- **Diagrams rot.** Mermaid blocks fall out of sync with the prose around them when one is updated and the other isn't.
- **ASCII art is a smell.** When someone reaches for ASCII art to explain a structure, they usually should be decomposing into smaller named pieces in prose.
- **"Show vs tell" is overrated for our use case.** The reader is an LLM (or a human reading code). Both benefit more from clear prose than from a diagram.

We considered allowing diagrams as opt-in. Decided against because:
- Once allowed, they'd be added widely
- Maintenance burden would grow
- No clear benefit for the LLM consumer of these docs

If you genuinely want a visual, put it in a separate file (e.g., `docs/architecture/auth-flow.svg`) and link to it from prose. Just don't embed it.

---

## Why strict `[NO-TDD]` criteria

`[NO-TDD]` is an opt-out marker for test-driven development. Without strict criteria, agents (and humans) tend to over-use it ("this test would be tedious; let me skip").

Strict criteria:
- Only 6 allowed categories: `docs-only`, `config-only`, `asset-addition`, `dependency-bump`, `mechanical-rename`, `lint-only`
- The reason line must match one of these labels
- The plan writer's own self-review flags `[NO-TDD]` misuse

Why this strict:
- **TDD pays off most on logic changes.** That's exactly the case `[NO-TDD]` was being used to skip.
- **Misuse cascades.** If T003 is `[NO-TDD]` "for simplicity", T010 will be too, and the test coverage erodes.
- **The categories are deliberate.** Each is a case where TDD genuinely can't apply — there's no behavior to verify with a test.

If you're tempted to use `[NO-TDD]` outside these categories, write the test. The first time always feels like overkill; the second time you find a bug it would have caught.

---

## Why the coordinator doesn't test itself

When Stage 9 tester returns `MCP_UNAVAILABLE` (no browser MCP for UI testing, no DB MCP for backend testing, etc.), the coordinator is forbidden from testing the feature itself, even if it has Bash, Playwright, curl, etc., available.

This is the highest-risk rationalization point in the pipeline. The reasoning the coordinator might use:
- "I have Bash; let me just curl the endpoint"
- "I have Playwright access; let me check the UI quickly"
- "It would be silly to surface MCP_UNAVAILABLE when I can just do it"

We reject all of these because:

- **Testing requires specialized context.** The tester subagent knows the feature type, the strategy, the acceptance scenarios. The coordinator doesn't carry that.
- **Half-tested is worse than not tested.** If the coordinator does a partial test and reports PASS, the user trusts it. The user is much better served by an explicit "couldn't test; here's a manual plan" than by a half-baked self-test.
- **Slippery slope.** Once the coordinator tests, the tester subagent becomes optional. Then unused. Then deleted.

The `ss-sdd-testing-implementation` skill repeats this rule in five different places. The coordinator skill repeats it twice. The redundancy is intentional — this is the rule we expect to be tempted to break.

---

## Why SDD owns the merge to `main` (closes the loop)

Stage 11 (`ss-sdd-finishing`) does more than print a summary and delete `state.json` — it runs `git checkout main && git merge --no-ff $branch_name`, and on success `git branch -d $branch_name`. No push, no PR, no prompts.

This is an opinionated, single-workflow choice — this repo is for the maintainer's personal use, not a multi-team library — so we close the loop in the pipeline rather than handing branch management back to the user. The three arguments that originally pushed this out of scope:

- **Workflow diversity.** Was the original blocker: teams have wildly different workflows (PR vs trunk, fast-forward vs no-ff vs squash, with/without `gh`, with/without protected branches, signed commits). The combinatorial surface is large. *Moot here* — one user, one workflow (`--no-ff` merge to `main`, safe-delete, local-only). The branching surface collapses to a constant.
- **Tests already ran.** Still true. Stage 9 is the test gate; Stage 11 does not re-test. The merge happens on already-tested commits.
- **Artifacts are durable.** Still true. The merge just propagates the spec / plan / ADRs / per-task commits / memory-file commit from the feature branch onto `main` as a single merge commit, making the feature easy to find later via `git log --first-parent main`.

Why this works without becoming brittle:

- The merge strategy is a constant (`--no-ff`), not a configurable. No surprise behavior.
- Safe-delete (`git branch -d`, not `-D`) is a second safety net — git refuses if the branch isn't fully merged, so we'd halt rather than destroy work in a weird intermediate state.
- The merge step is naturally idempotent (`git merge --no-ff <already-merged>` returns 0 with "Already up to date"), so continuing Stage 11 after a manual conflict resolution just works.
- Push is still the user's call. SDD never touches the remote.

Branch creation still happens at Stage 7 (`ss-sdd-choosing-feature-branch`), not preflight — by then the spec and plan exist and `short_name` is known, so the feature branch can be derived from `branch_pattern`. Preflight stays branch-agnostic on purpose: starting SDD on an existing feature branch (to build on top of a partial implementation) is a supported path, and Stage 7's silent "already on derived name" case handles it.

---

## Why a separate skill for receiving review findings

`ss-sdd-receiving-review-findings` is loaded inline by the coordinator after the spec reviewer subagent returns (Stage 3). It establishes how to evaluate findings: verify before fixing, push back when wrong, no performative agreement.

Why a separate skill (instead of inline in the coordinator):

- **Used at Stage 3** (after the spec reviewer returns). The rules are too specific to inline.
- **Borrowed wisdom.** `superpowers:receiving-code-review` codifies a lot of hard-won "how to receive feedback without theater" rules. Adopting them as a skill makes them load-bearing.
- **Anti-performative-agreement is non-obvious.** "You're absolutely right!" is the default for an LLM. Explicitly forbidding it requires explicit instruction.
- **Centralized push-back logic.** When the coordinator pushes back on a finding, the rationale is logged in `reviewer_pushbacks` in the state file. Consistent across stages.

We considered keeping it inline. Decided against because the rules are too specific and too important to bury in the coordinator's spec-review handling.

---

## Comparison: SDD vs spec-kit vs brainstorming vs Kiro

SDD borrows from all three. Here's how it differs:

### vs spec-kit (GitHub)

| Aspect | spec-kit | SDD |
|---|---|---|
| Coordination | None — user runs each command manually | `ss-sdd-coordinator` drives the whole pipeline |
| Artifacts per feature | 7+ files (spec, plan, tasks, research, data-model, contracts, quickstart, checklists) | 2-3 (spec, plan, state file; ADRs at project level) |
| Constitution | First-class (`/speckit.constitution`) | Optional, opt-in via bootstrap |
| Per-task implementation | One sequential run | Fresh subagent per task + one final cross-cutting review |
| Resumability | None explicit | State file in git; coordinator reads first |
| Diagram policy | Allowed (templates have Mermaid) | Prohibited |
| Format prescriptiveness | Heavy templates with many placeholders | Lighter; structure prescribed, content not templated |

We borrowed: user-story priorities (P1/P2/P3), FR-### / SC-### IDs, the "checklists are unit tests for English" framing, the `[T###] [P] [US#]` task format, the cross-artifact consistency analysis idea (but we don't have a dedicated analyze stage — the plan writer's own self-review covers granularity and coverage).

We dropped: the constitution as a first-class artifact, the proliferation of supporting files (research.md, data-model.md, etc. — we consolidate into spec or plan), the hooks/extensions YAML system.

### vs Superpowers brainstorming (Obra)

| Aspect | Brainstorming | SDD |
|---|---|---|
| Pipeline | brainstorming → ss-sdd-writing-plans → using-git-worktrees → subagent-driven-development → finishing-a-development-branch | 12-stage pipeline with explicit stage boundaries |
| ADR step | None | Stage 4, dedicated skill |
| State file | Harness todo tool for tasks, no explicit state file | Gitignored `state.json` as data-carrier between stages + per-task orchestration record (no resume protocol — same-conversation only) |
| Feature testing | Unit tests in each task; no dedicated feature-level test stage | Stage 9 with browser/DB MCP awareness |
| Self-containment | Family of skills that depend on each other (and on some that aren't always available) | No external skill dependencies |

We borrowed extensively: the per-task implementer, the implementer status protocol (DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT), the one-question-at-a-time conversation style, "continuous execution between tasks" rule, the finishing 4 options.

We added: the ADR step, dedicated feature testing with MCP awareness, an explicit state file for between-stage data and per-task orchestration, abort-only preflight.

### vs Kiro-skill (feiskyer)

| Aspect | Kiro | SDD |
|---|---|---|
| Pipeline | requirements → design → tasks → execute | 12 stages |
| Format | EARS format for acceptance criteria | Given/When/Then default; EARS as opt-in option |
| Diagrams | Mermaid in design docs | Prohibited |
| Per-task gating | STOP after every task; wait for user | Continuous execution; user only involved at approval gates |
| Subagent isolation | None | Per-task fresh subagents |
| State file | Detected via filesystem (`.kiro/specs/` presence) | Explicit gitignored `state.json` (data-carrier between stages; not a resume mechanism) |

We borrowed: EARS format option, requirement-to-task traceability (we call it `**Requirements:** FR-###` instead of `_Requirements: 1.1_`).

We dropped: stop-after-every-task (too friction-heavy), the `.kiro/` directory naming (brand-leaky), the Mermaid diagrams.

### The synthesis

SDD takes the Superpowers shape (spec → plan → implementation with reviews), the spec-kit format conventions (user-story priorities, FR-### IDs, task format), the Kiro EARS option, and adds:

- ADR maintenance as a first-class stage
- Explicit state file for between-stage data and per-task orchestration (no resume protocol — same-conversation only)
- Receiving-review-findings skill for consistent handling across stages
- Abort-only preflight for safety
- Validation scripts (`validate-*.sh`) for schema correctness
- Stricter `[NO-TDD]` criteria
- No-diagrams policy

The result is heavier than brainstorming, lighter than spec-kit, and more strict than Kiro. It's calibrated for a single solo developer (or small team) using AI agents for feature development with reliability as the top priority.

---

## Things we deliberately didn't do

A handful of things we considered and rejected:

- **`maintaining-constitution` as a first-class skill.** ADRs cover the immediate need. We can add it later if patterns emerge.
- **Auto-clarify stage between discovery and spec.** Discovery + the automated spec-review cover the same ground.
- **Pressure-testing skills (writing-skills TDD methodology).** Expensive; pays off most for discipline skills like TDD. Our skills are procedural; structural review catches what matters.
- **Description optimization for skill discovery.** The coordinator invokes skills by name, so auto-discovery isn't load-bearing. Optimizing descriptions is token-heavy and slow.
- **Real-time multi-implementer parallelism.** Sequential per-task is fine. Parallel adds conflict-resolution complexity for marginal speedup.
- **Per-task state persistence with sub-step granularity.** State at task level is sufficient; sub-step granularity would balloon state.json and complicate atomic writes.
- **Visual companion (browser-rendered mockups during discovery).** Brainstorming has it; we judged it unnecessary for SDD's text-only flow.

If usage reveals one of these is actually needed, we can add it. The current shape is calibrated for "common case useful, exceptional case manageable."

---

## What the design is NOT optimized for

Honesty matters here:

- **Extremely large features.** SDD's spec/plan structure assumes one feature per pipeline. Multi-month epics are out of scope; decompose them.
- **Pure refactors with no behavior change.** Most stages still apply, but the spec writes itself ("change the structure without changing behavior"). Pipeline overhead is high for the work.
- **Documentation-only changes.** `[NO-TDD]` exists for this, but the full pipeline is heavyweight for a typo fix. Don't invoke SDD for trivial changes.
- **One-line bug fixes.** Same as above. SDD is for features and substantive fixes.
- **Exploratory spikes.** SDD wants up-front design. Spikes by nature don't have that. Don't shoehorn.
- **Cross-team coordination.** SDD assumes a single user (with possibly multiple AI sessions) driving the work. Team workflows with multiple human collaborators add coordination needs SDD doesn't address.

If your work doesn't fit, don't invoke SDD. Use a lighter workflow.

---

## Final note: paper-tested, not battle-tested

As of this writing, the SDD skill family has been carefully designed, structurally reviewed, and iterated through multiple rounds of refinement. It has NOT been used end-to-end on a real feature.

The first few real runs will surface things this design didn't anticipate. Likely areas of friction:

- Subagent prompt calibration (reviewers either too noisy or too lenient)
- MCP detection edge cases in `ss-sdd-testing-implementation`
- ADR identification heuristics (over- or under-creating ADRs)
- The "no clean iteration path" between later stages and earlier ones
- Real secrets that the redaction patterns don't catch

These are expected. The intent is to fix them based on real usage, not predict every case in advance.
