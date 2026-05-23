# Design Rationale

Why we built SDD this way. Each decision explained, with the alternatives we considered and why we chose what we did.

## Contents

- [Why an 18-stage pipeline](#why-an-18-stage-pipeline)
- [Why thin coordinator + many skills](#why-thin-coordinator--many-skills)
- [Why no external skill dependencies](#why-no-external-skill-dependencies)
- [Why abort-only preflight](#why-abort-only-preflight)
- [Why split discovery and spec-writing](#why-split-discovery-and-spec-writing)
- [Why per-task subagent dispatch](#why-per-task-subagent-dispatch)
- [Why two-stage review per task](#why-two-stage-review-per-task)
- [Why state file in git](#why-state-file-in-git)
- [Why ADRs over Constitution (initially)](#why-adrs-over-constitution-initially)
- [Why a handoff document](#why-a-handoff-document)
- [Why no diagrams](#why-no-diagrams)
- [Why strict `[NO-TDD]` criteria](#why-strict-no-tdd-criteria)
- [Why the coordinator doesn't test itself](#why-the-coordinator-doesnt-test-itself)
- [Why config-driven finishing](#why-config-driven-finishing)
- [Why a separate skill for receiving review findings](#why-a-separate-skill-for-receiving-review-findings)
- [Comparison: SDD vs spec-kit vs brainstorming vs Kiro](#comparison-sdd-vs-spec-kit-vs-brainstorming-vs-kiro)

---

## Why an 18-stage pipeline

An 18-stage pipeline sounds heavy (Stages 0-17). For trivial changes it might be overkill. We accepted that because the alternative — a flexible pipeline where stages can be skipped freely — fails predictably:

- AI agents tend to skip stages they shouldn't (especially review stages) when given the option
- Inconsistent application means inconsistent quality across features
- "Trivial" changes that turn out to be non-trivial don't get the rigor they need
- Optional stages compound: if every stage is optional, the pipeline degenerates to a chat

The pipeline as designed has **5 user-gated optional stages** (grill, 2nd spec-review, feature testing, handoff generation, memory file maintenance — Stages 4, 5, 13, 14, 15). Everything else is mandatory and requires editing the coordinator skill itself to bypass.

**Why this is OK in practice:** for genuinely small changes (a typo fix, a config bump), you wouldn't invoke SDD at all. SDD is for features that warrant structured development. The pipeline is calibrated for that scale.

---

## Why thin coordinator + many skills

The alternative would be one giant coordinator skill that contains all phase logic inline. We rejected this because:

- **Coordinator context bloat:** if every phase's instructions are loaded into the coordinator's context, the coordinator carries 5000+ lines of skill content at all times. Most of it is irrelevant to the current stage.
- **Coupling:** changes to phase logic require editing the coordinator, increasing risk of unintended side effects.
- **Reusability:** with phase logic in dedicated skills, individual skills (e.g., `writing-specs`, `reviewing-specs`) can be invoked outside the pipeline if needed.

The trade-off is more skill files to maintain (20 skills + 6 shared scripts + 2 schema files = 28 files) and the coordinator loading skills just-in-time. We judged this worth it.

**Concrete benefit:** the coordinator's SKILL.md is ~450 lines. The combined skills are ~5000 lines, but at any given moment only the active phase-skill is loaded. The coordinator stays a state machine + dispatcher.

---

## Why no external skill dependencies

The SDD family runs without any other skill family installed. We don't depend on `superpowers:*`, `kiro:*`, `skill-creator:*`, or anything else at runtime.

Reasons:
- **Portability:** users with different harness configurations can install just SDD without prerequisite chains.
- **Stability:** external skills can change in incompatible ways; we can't control that.
- **Clarity:** when something goes wrong, the failure mode is contained within SDD.

We did borrow design patterns extensively from external sources (Superpowers' two-stage review, spec-kit's user-story priorities, Kiro's EARS format option, `receiving-code-review`'s no-performative-agreement rule). But we re-implemented them inside SDD rather than calling them.

**Exception:** Phase 4 of the build process (using `superpowers:writing-skills` to review our own skills) is a one-time meta step, not part of the runtime SDD workflow. That's allowed.

---

## Why abort-only preflight

Earlier versions of preflight tried to be helpful: auto-commit dirty files, auto-stash, auto-switch from main to a feature branch. We changed to abort-only because:

- **"Helpful" magic backfires.** Auto-stashing dirty files seems convenient until the user's stash conflicts on restore.
- **User intent is opaque.** Dirty files might be in-progress work, accidentally-edited files, or merge conflicts. The coordinator can't tell.
- **Aborting forces explicit intent.** When the user re-invokes after cleaning up, they've consciously decided what to do with their working tree.
- **Safety > speed.** A 30-second clean-up by the user beats hours of debugging "where did my changes go?"

The downside is friction. First-time users will find it annoying ("just stash for me!"). We accept that — the friction is the point. It teaches the user that SDD requires a clean entry state, and they'll soon habitually `git stash` or `git commit` before invoking the coordinator.

---

## Why split discovery and spec-writing

Earlier versions had discovery and spec-writing in one stage. We split them because:

- **Different jobs need different skills.** Discovery is conversational Q&A with the user. Spec-writing is mechanical document generation. The methodologies don't overlap.
- **Reviewers see clearer work.** When `reviewing-specs` reviews the spec, it sees a freshly-written document with no conversational drift, not a doc built up over a long Q&A.
- **Clearer hand-off.** The discovery stage has an explicit "shared understanding approved by user" exit point. The spec-writing stage takes that understanding and renders it. Two stages, one job each.

The cost is a small amount of coordinator overhead (advance from Stage 1 to Stage 2). The benefit is two much cleaner skills.

---

## Why per-task subagent dispatch

For Stage 12 implementation, every task gets THREE fresh subagent dispatches: implementer, spec-compliance reviewer, code-quality reviewer.

This is expensive (subagent dispatch isn't free) and slow (sequential, not parallel). We do it because:

- **Context isolation.** Per-task subagents don't carry context from previous tasks. T002's design choices don't bleed into T003's work.
- **Smaller context budgets.** Each subagent's prompt + the relevant files fits comfortably in a small context window.
- **Focused review.** Reviewers focus on one task's diff, not the whole feature's diff (until the final review, which is a different mechanism).
- **Resilience.** A misbehaving subagent doesn't poison the rest of the pipeline.

The cost is dispatch overhead and inability to parallelize within a task (the three subagents must be sequential because the reviewers depend on the implementer's output).

We considered an alternative: dispatch one subagent per task that does implementation + self-review, with the coordinator doing the spec-compliance and code-quality checks itself. We rejected this because the coordinator's context would get polluted with task-level details over time.

---

## Why two-stage review per task

The implementer produces a diff. The reviewer evaluates it. We could have one reviewer that checks everything (compliance + quality). We chose two because they look at different things:

- **Spec-compliance:** did the implementer do exactly what the task said? Anything missing or added? This is a checklist-style review.
- **Code-quality:** is the code readable, idiomatic, secure, performant? This is a craft review.

Conflating them produces noisier, less actionable feedback. A reviewer that's looking for both ends up flagging style issues as if they were compliance gaps, or skipping over scope creep because the code "looks clean."

Two reviewers, with two different prompt templates, with explicit "stay in your lane" rules in each prompt. The cost is one more subagent dispatch per task; the benefit is consistently higher signal-to-noise.

**Per-task code-quality also distinguishes Critical / Important / Minor.** Critical and Important come back to the implementer for fixes; Minor is noted but doesn't block. This prevents the "every minor style suggestion is a re-dispatch" cycle.

---

## Why state file in git

Two alternatives we considered:
- **Gitignored state:** state file is local-only, doesn't get committed.
- **External state:** state in a `.sublime-skills-state/` directory or a database.

We chose committed state because:

- **Durability across interruptions.** The state file survives a fresh shell, a working-tree reset, or simply coming back to the project later — the coordinator globs it up and offers to resume.
- **Auditability.** Git log shows when state advanced, alongside the spec/plan changes that drove the advance.
- **Squash-merge eats the noise.** If the project squashes on merge, state file churn collapses into one final commit — no main-branch pollution.

The trade-off is per-stage commits include the state.json delta. Mild noise on the feature branch's history, which we accept.

We considered making state.json gitignored as an opt-in (`state.gitignore: true`), but it turned out not worth the configurability. Always-committed is simpler.

---

## Why ADRs over Constitution (initially)

`spec-kit` has a Constitution concept — a single file with project-wide principles. We considered including it but decided to start with ADRs only.

Reasons:
- **ADRs cover the same ground at finer grain.** Most "principles" are really "decisions" with broader scope.
- **Solo / small team scale.** Constitution is most useful when multiple developers need consistent guidance. For solo or small-team use, ADRs accumulate naturally.
- **Less governance ceremony.** Constitution requires authoring, versioning, propagation. ADRs are written one at a time.
- **`bootstrapping-project` does offer constitution authoring.** It's an opt-in artifact (with a dedicated `discovering-constitution` inline skill). Users who want it can add it; the pipeline reads it when present.

The pipeline reads constitution.md if it exists (in stages where alignment matters). It's just not required, and we don't have a separate `maintaining-constitution` skill — yet.

If a project starts repeating the same guidance in every spec, that's the signal to add a constitution. The bootstrap skill makes it easy. We can add a `maintaining-constitution` skill later if patterns emerge.

---

## Why a handoff document

The handoff doc is generated at Stage 15 (user-prompted, default yes). It's a redacted, summary-style document at `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<title>.md`.

Why have it:

- **PR iteration.** When you come back to address PR feedback in a new session, the handoff doc lets you orient without re-reading the whole spec + plan + ADR set.
- **Cross-session continuity.** If a different agent (or human) picks up the work, they have a self-contained starting point.
- **Auditability.** The handoff doc captures "what was actually built" alongside "what was supposed to be built" (the spec) and "how it was supposed to be built" (the plan).

Why it's a separate doc, not in the spec or plan:

- The spec and plan are pre-implementation; the handoff is post-implementation.
- The handoff includes git log highlights, test results, and observations from implementation — none of which fit in spec/plan.

Why it references rather than duplicates:

- ADRs and spec sections shouldn't be repeated; that's churn and drift waiting to happen.
- The handoff is a bridge, not a duplicate.

Why redaction:

- Handoff docs may be shared more freely than internal code (e.g., pasted into ticketing systems, attached to PRs, shared with consultants).
- Any secrets, API keys, tokens, or passwords that slipped into commits should NOT be in the handoff.

Why `validate-handoff.sh` checks for unredacted secrets:

- Defense-in-depth. The handoff generator does a redaction sweep; the validator catches anything that slipped through.
- Critical failures on unredacted patterns force the writer to fix or explicitly mark the false positive.

---

## Why no diagrams

Specs, plans, and handoffs are prose-only. No Mermaid, no C4, no PlantUML, no ASCII art.

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
- `reviewing-plans` flags misuse as CRITICAL

Why this strict:
- **TDD pays off most on logic changes.** That's exactly the case `[NO-TDD]` was being used to skip.
- **Misuse cascades.** If T003 is `[NO-TDD]` "for simplicity", T010 will be too, and the test coverage erodes.
- **The categories are deliberate.** Each is a case where TDD genuinely can't apply — there's no behavior to verify with a test.

If you're tempted to use `[NO-TDD]` outside these categories, write the test. The first time always feels like overkill; the second time you find a bug it would have caught.

---

## Why the coordinator doesn't test itself

When Stage 13 tester returns `MCP_UNAVAILABLE` (no browser MCP for UI testing, no DB MCP for backend testing, etc.), the coordinator is forbidden from testing the feature itself, even if it has Bash, Playwright, curl, etc., available.

This is the highest-risk rationalization point in the pipeline. The reasoning the coordinator might use:
- "I have Bash; let me just curl the endpoint"
- "I have Playwright access; let me check the UI quickly"
- "It would be silly to surface MCP_UNAVAILABLE when I can just do it"

We reject all of these because:

- **Testing requires specialized context.** The tester subagent knows the feature type, the strategy, the acceptance scenarios. The coordinator doesn't carry that.
- **Half-tested is worse than not tested.** If the coordinator does a partial test and reports PASS, the user trusts it. The user is much better served by an explicit "couldn't test; here's a manual plan" than by a half-baked self-test.
- **Slippery slope.** Once the coordinator tests, the tester subagent becomes optional. Then unused. Then deleted.

The `testing-implementation` skill repeats this rule in five different places. The coordinator skill repeats it twice. The redundancy is intentional — this is the rule we expect to be tempted to break.

---

## Why SDD doesn't manage branches or merges (V1)

The pipeline doesn't merge branches, create PRs, push to remotes, or delete the feature branch. Stage 17 (`finishing-sdd`) prints a summary and deletes `state.json`. That's it. The user decides what happens to the feature branch after SDD ends.

This is a deliberate V1 scoping choice:

- **Source control is the user's responsibility.** Teams have wildly different workflows (PR vs trunk vs fast-forward vs squash-merge vs rebase-and-merge, with or without `gh`, with or without protected branches, with or without draft PRs, with or without signed commits). The combinatorial surface is large; SDD trying to drive it leads to brittle, magic behavior that fails in surprising ways.
- **Tests already ran.** Stage 14 (feature testing) is the gate. A final test re-run at Stage 17 was redundant — it ran the same suite a second (sometimes third) time. We dropped it.
- **The artifacts are the durable record.** Spec, plan, ADRs, handoff doc, and per-task commits already exist on the feature branch by the time finishing runs. The user's git skills take it from there.

This also affects where branch creation happens: not in preflight (which is too early — the user doesn't yet know what they're building) but at Stage 12 (`choosing-feature-branch`), right before code starts landing. By that point the spec and plan exist and the user can decide branch policy with full context.

---

## Why a separate skill for receiving review findings

`receiving-review-findings` is loaded inline by the coordinator after every spec/plan reviewer subagent returns. It establishes how to evaluate findings: verify before fixing, push back when wrong, no performative agreement.

Why a separate skill (instead of inline in the coordinator):

- **Used in 4 places** (Stages 3, 5, 9, 10). DRY argument.
- **Borrowed wisdom.** `superpowers:receiving-code-review` codifies a lot of hard-won "how to receive feedback without theater" rules. Adopting them as a skill makes them load-bearing.
- **Anti-performative-agreement is non-obvious.** "You're absolutely right!" is the default for an LLM. Explicitly forbidding it requires explicit instruction.
- **Centralized push-back logic.** When the coordinator pushes back on a finding, the rationale is logged in `reviewer_pushbacks` in the state file. Consistent across stages.

We considered keeping it inline. Decided against because the rules are too specific and too important to inline-repeat across the coordinator's 4 review stages.

---

## Comparison: SDD vs spec-kit vs brainstorming vs Kiro

SDD borrows from all three. Here's how it differs:

### vs spec-kit (GitHub)

| Aspect | spec-kit | SDD |
|---|---|---|
| Coordination | None — user runs each command manually | `sdd-coordinator` drives the whole pipeline |
| Artifacts per feature | 7+ files (spec, plan, tasks, research, data-model, contracts, quickstart, checklists) | 2-3 (spec, plan, state file; ADRs and handoff at project level) |
| Constitution | First-class (`/speckit.constitution`) | Optional, opt-in via bootstrap |
| Per-task implementation | One sequential run | Fresh subagents per task with two-stage review |
| Resumability | None explicit | State file in git; coordinator reads first |
| Diagram policy | Allowed (templates have Mermaid) | Prohibited |
| Format prescriptiveness | Heavy templates with many placeholders | Lighter; structure prescribed, content not templated |

We borrowed: user-story priorities (P1/P2/P3), FR-### / SC-### IDs, the "checklists are unit tests for English" framing, the `[T###] [P] [US#]` task format, the cross-artifact consistency analysis idea (but we don't have a dedicated analyze stage — `reviewing-plans` covers that ground).

We dropped: the constitution as a first-class artifact, the proliferation of supporting files (research.md, data-model.md, etc. — we consolidate into spec or plan), the hooks/extensions YAML system.

### vs Superpowers brainstorming (Obra)

| Aspect | Brainstorming | SDD |
|---|---|---|
| Pipeline | brainstorming → writing-plans → using-git-worktrees → subagent-driven-development → finishing-a-development-branch | 18-stage pipeline with explicit stage boundaries |
| ADR step | None | Stage 6, dedicated skill |
| Optional grill | None | Stage 4, dedicated skill |
| 2nd review | None | Optional Stages 5 + 10 |
| State / resume | Harness todo tool for tasks, no explicit cross-session state | state.json in git, explicit resume protocol |
| Feature testing | Unit tests in each task; no dedicated feature-level test stage | Stage 13 with browser/DB MCP awareness |
| Handoff doc | None | Stage 14, dedicated skill |
| Self-containment | Family of skills that depend on each other (and on some that aren't always available) | No external skill dependencies |

We borrowed extensively: the per-task implementer + two-stage review, the implementer status protocol (DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT), the one-question-at-a-time conversation style, "continuous execution between tasks" rule, the finishing 4 options.

We added: the ADR step, the optional grill, the 2nd review pass, dedicated feature testing with MCP awareness, the handoff doc, explicit state file + resume protocol, abort-only preflight.

### vs Kiro-skill (feiskyer)

| Aspect | Kiro | SDD |
|---|---|---|
| Pipeline | requirements → design → tasks → execute | 18 stages |
| Format | EARS format for acceptance criteria | Given/When/Then default; EARS as opt-in option |
| Diagrams | Mermaid in design docs | Prohibited |
| Per-task gating | STOP after every task; wait for user | Continuous execution; user only involved at approval gates |
| Subagent isolation | None | Per-task fresh subagents |
| State / resume | Detected via filesystem (`.kiro/specs/` presence) | Explicit state file |

We borrowed: EARS format option, requirement-to-task traceability (we call it `**Requirements:** FR-###` instead of `_Requirements: 1.1_`).

We dropped: stop-after-every-task (too friction-heavy), the `.kiro/` directory naming (brand-leaky), the Mermaid diagrams.

### The synthesis

SDD takes the Superpowers shape (spec → plan → implementation with reviews), the spec-kit format conventions (user-story priorities, FR-### IDs, task format), the Kiro EARS option, and adds:

- ADR maintenance as a first-class stage
- Optional grill for spec hardening
- Handoff doc generation for continuity
- Explicit state file + resume protocol
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
- **Auto-clarify stage between discovery and spec.** Discovery + automated review + optional grill cover the same ground.
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
- MCP detection edge cases in `testing-implementation`
- ADR identification heuristics (over- or under-creating ADRs)
- The "no clean iteration path" between later stages and earlier ones
- Real secrets that the redaction patterns don't catch

These are expected. The intent is to fix them based on real usage, not predict every case in advance.
