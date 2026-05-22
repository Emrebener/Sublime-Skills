# Sublime-Skills

A skill family for agent harnesses, grouped into category directories.
Each skill lives in its own directory with a `SKILL.md`; this file
summarizes what each one does. Designed to be adopted by individuals
and teams alike.

## Skills

### [architecture-review](engineering/architecture-review/)

Reviews a codebase for architectural friction and proposes concrete
refactoring opportunities — turning **shallow**, leaky modules into
**deep**, testable ones. Explores the code, applies the **deletion
test** to tell pass-through modules from ones earning their keep,
presents numbered candidates, then grills the chosen one into a settled
design (with a parallel sub-agent pattern for comparing alternative
interfaces). Design-only — it stops at an agreed design and doesn't
implement the change. Uses a project domain glossary and ADRs if they
exist, but requires neither.

### [browser-tools](web-utilities/browser-tools/)

Interactive Chromium browser automation and debugging over the Chrome
DevTools Protocol — a self-contained, MCP-free alternative to Puppeteer MCP
and Chrome DevTools MCP, for agent harnesses that can't run MCP servers.

A set of plain CLI scripts covering:

- **Named multi-sessions** — run isolated browsers in parallel.
- **Accessibility snapshot + element refs** — act on stable `@eN` refs
  instead of guessed CSS selectors.
- **Actionability waits** — interactions wait for elements to be visible,
  enabled, and stable.
- **Navigation & interaction** — click, type, hover, select, drag, scroll,
  key presses, tabs, dialogs, file uploads.
- **Debugging** — console and network capture, performance traces,
  page-content extraction, screenshots.

### [restrict-git-commands](workflow/restrict-git-commands/)

A baseline policy preventing destructive git operations (`push`,
`reset --hard`, `clean -f`, `branch -D`, `checkout .` / `restore .`) from
being run without explicit user authorization. Works via instruction —
load the skill at session start (or whenever about to run git commands)
and the agent commits to asking before any irreversible operation, with
the exact command and consequence named in each ask. A reference Claude
Code `PreToolUse` hook script is bundled at
`workflow/restrict-git-commands/scripts/block-dangerous-git.sh` as an
optional drop-in for users who want deterministic harness-level
enforcement on top of the instruction layer.

### [web-search](web-utilities/web-search/)

Web search for AI agents via a self-hosted
[SearXNG](https://docs.searxng.org/) instance — a self-contained, MCP-free
search tool for harnesses that can't run MCP servers.

A single dependency-free CLI script that queries SearXNG's JSON API and
returns ranked results (`title / url / snippet`, or JSON). Supports result
count, category (general/news/images/videos), time range, language/region,
and safe-search level. The SearXNG endpoint is configured via the
`SEARXNG_URL` environment variable or a local `config.json`.

### Spec-driven development

A 21-skill family for running structured, spec-driven feature development
end-to-end (plus a separate 6-skill `project-bootstrap/` family for
one-time project setup — see below). The pipeline: **preflight → discover
→ spec → reviews → ADRs → plan → reviews → per-task implementation →
optional feature testing → handoff doc → memory file → finish**. Coordinated
by `sdd-coordinator`, which is the only entry point the user invokes —
every other skill is loaded by the coordinator or dispatched as a
subagent. Designed to be self-contained (no dependencies on external
skill families), resumable across sessions via a per-feature state file
at `docs/specs/NNN-name/state.json`, and configurable via `.sublime-skills/config.yml`
(path overrides, finishing mode, harness tool names). Specs and plans
live at `docs/specs/NNN-short-name/`; ADRs at `docs/adr/`; handoff docs
at `docs/handoff/YYYY-MM-DD-<title>.md`.

Shared scripts at `spec-driven-development/scripts/`:
- `discover-context.sh` — reads project convention file paths from
  `.sublime-skills/config.yml` (`constitution.md`, `ARCHITECTURE.md`, `GLOSSARY.md`,
  `DOMAIN.md`, prior ADRs) and verifies each file exists, so skills can
  load relevant context from a single source of truth.
- `validate-config.sh` — validates `.sublime-skills/config.yml` end-to-end (YAML
  shape, required keys, context-path resolution, enum values). Used by
  `bootstrapping-project`'s fix-and-retry loop and by `preflight-checks`
  (Stage 0 of the SDD pipeline) to halt if the config is missing or
  invalid.
- `validate-spec.sh`, `validate-plan.sh`, `validate-handoff.sh` —
  schema-check the artifacts each writer skill produces. Catch gross
  format violations (missing sections, placeholders, forbidden diagram
  syntax, unredacted secrets) before the artifact is committed.

#### [sdd-coordinator](spec-driven-development/sdd-coordinator/)

Entry point for SDD runs. Thin state machine + dispatcher — knows the
16-stage pipeline, reads the per-feature state file first on every
invocation (via `inspecting-state`), resumes interrupted runs, loads
phase-skills inline for interactive stages, dispatches subagents for
fresh-context stages (reviews, ADR maintenance, per-task implementation,
testing, handoff). Holds state updates atomic at stage boundaries, never
mid-stage. Surfaces user-gated optional stages (grill, 2nd review pass,
feature testing). Critically: never tests the feature itself — if the
tester subagent reports MCP unavailability, the coordinator surfaces a
manual test plan rather than improvising.

#### [preflight-checks](spec-driven-development/preflight-checks/)

First stage of an SDD run. Inspects git state. **Abort-only on
problems:** if the working tree is dirty, or the current branch is
inappropriate (develop / release / random non-SDD branch), the skill
aborts and tells the user to clean up manually before re-invoking. Only
proceeds when on `main`/`master` (creates a feature branch from there),
or on a feature-like branch that has a matching active SDD state file
(resume case). Optionally creates a `.worktrees/<branch>` worktree when
configured.

#### [discovering-requirements](spec-driven-development/discovering-requirements/)

Interactive discovery conversation. One question at a time, multiple
choice with a recommended answer where possible. Walks the user through
purpose, scope, users, success criteria, key entities, edge cases,
constraints, and integration points — skipping dimensions already
covered. Surfaces 2-3 alternatives with recommendations for major design
decisions. Includes a scope check that catches and decomposes too-big
feature requests. Output is shared understanding in the coordinator's
context, not a written artifact — `writing-specs` renders it next.

#### [writing-specs](spec-driven-development/writing-specs/)

Renders the agreed understanding from discovery into `spec.md` at
`docs/specs/NNN-short-name/spec.md`. Opinionated structure: user stories
with P1/P2/P3 priorities + Given/When/Then acceptance scenarios,
FR-### functional requirements with story traceability, measurable
SC-### success criteria, key entities, edge cases, assumptions,
out-of-scope. EARS format allowed where precision matters. Initializes
the state file. Forbids Mermaid/C4/PlantUML/ASCII diagrams. Includes
automated schema validation (`validate-spec.sh`) followed by an inline
fresh-eyes pass before handing off to `reviewing-specs`.

#### [reviewing-specs](spec-driven-development/reviewing-specs/)

Subagent skill. Independent fresh-eyes review of a spec before plan
writing. Detection passes: completeness, internal consistency, clarity/
testability, constitution / ADR alignment, scope, YAGNI, vocabulary
drift. Findings categorized CRITICAL / HIGH / MEDIUM / LOW. Strict
read-only — does not modify files. Calibrated to approve unless there's
a real CRITICAL/HIGH finding (noisy reviewers get ignored). Used for
both the mandatory first pass and the optional second pass.

#### [grilling-specs](spec-driven-development/grilling-specs/)

Optional bounded grill that interviews the user about weak/unclear/
underspecified areas of the spec, with a recommended answer per
question. Every accepted answer is logged inline with an atomic
per-answer save; substantive answers also edit the affected spec
sections, while answers that just confirm the spec as-is are log-only —
the grill produces only actionable changes, no manufactured edits.
Stop conditions: user signals done, all high-impact areas resolved, or
hard cap (default 10, configurable, hard ceiling 20).

#### [maintaining-adrs](spec-driven-development/maintaining-adrs/)

Subagent skill. Reads the spec and existing ADRs, identifies decisions
that warrant new ADR records (architectural, with real alternatives,
where the reasoning matters), and writes them in a locked format
(Title / Status / Date / Spec link / Context / Decision / Consequences /
Alternatives Considered). Avoids duplicates against existing ADRs; marks
supersession explicitly when applicable. Returns 0 ADRs as a valid
outcome — not every spec needs new ADRs.

#### [writing-plans](spec-driven-development/writing-plans/)

Renders the approved spec into `plan.md` at
`docs/specs/NNN-short-name/plan.md`. Tasks are organized into phases by
user story (Setup → Foundational → Phase per story in priority order →
Polish), with `[T###]` IDs, optional `[P]` parallel markers, `[US#]`
story labels, exact file paths, and `**Requirements:** FR-###`
traceability. Each task has bite-sized TDD steps (2-5 min each) with
actual code, exact test commands with expected output, and commit
messages. `[NO-TDD]` opt-out marker is allowed ONLY for strict
categories (docs-only, config-only, asset-addition, dependency-bump,
mechanical-rename, lint-only); reviewer flags misuse as CRITICAL.
Forbids placeholders, Mermaid/C4/PlantUML/ASCII diagrams, and references
to things not defined in the plan or codebase. Includes automated schema
validation (`validate-plan.sh`).

#### [reviewing-plans](spec-driven-development/reviewing-plans/)

Subagent skill. Independent review of an implementation plan before
per-task execution. Detection passes: spec coverage (every FR has a
task), placeholder scan, type/name/path consistency across tasks, TDD
discipline, `[P]` correctness, story independence (MVP-first),
constitution/ADR alignment, granularity. Findings categorized
CRITICAL / HIGH / MEDIUM / LOW. Strict read-only.

#### [implementing-plans](spec-driven-development/implementing-plans/)

Per-task orchestration loop. For each task in plan order: dispatch
implementer subagent → handle status (DONE / DONE_WITH_CONCERNS /
BLOCKED / NEEDS_CONTEXT) → dispatch spec-compliance reviewer subagent →
loop fix-review until approved (cap 3) → dispatch code-quality reviewer
subagent → loop until approved (cap 3, Minor findings non-blocking) →
mark task complete. After all tasks: final code review on the full diff.
Continuous execution between tasks — no needless check-ins. Includes
three prompt templates as separate files (implementer-prompt.md,
spec-compliance-reviewer-prompt.md, code-quality-reviewer-prompt.md).

#### [implementing-task](spec-driven-development/implementing-task/)

Protocol skill loaded by implementer subagents when dispatched per task.
Covers scope discipline (with concrete in-scope vs out-of-scope
examples), TDD-by-default + strict `[NO-TDD]` handling, commit hygiene
(one task → one commit, Conventional Commits style with task ID
reference), the four-status reporting protocol (DONE / DONE_WITH_CONCERNS /
BLOCKED / NEEDS_CONTEXT), self-review checklist, and a rationalizations
table calling out the most common scope-creep traps. Includes the
"your work will be reviewed" priming that measurably improves output
quality.

#### [reviewing-task-compliance](spec-driven-development/reviewing-task-compliance/)

Protocol skill loaded by the first-stage per-task reviewer subagent.
Spec-compliance checks only: coverage + FR traceability, scope creep
(the dominant failure mode), test presence and meaningful coverage,
test verification by re-running tests (not trusting the implementer's
report), silent design decisions, commit hygiene, files-touched scope.
Outputs Approved | Issues Found with categorized findings. Strict lane
discipline — does NOT flag code quality, naming, or idiom (that's the
next reviewer). Calibrated to approve clean work and call out real
problems, not manufacture issues.

#### [reviewing-task-quality](spec-driven-development/reviewing-task-quality/)

Protocol skill loaded by the second-stage per-task reviewer subagent
after spec compliance is approved. Six-dimension code review:
readability, correctness around edges, idiom alignment with the rest of
the codebase, security (with specific scan anchors for SQL injection,
unsafe deserialization, secrets in logs, missing authz, custom crypto),
performance (O(n²), unbounded growth, N+1, missing indexes),
maintainability. Severity rubric: Critical (correctness/security/data),
Important (idiom/readability), Minor (style preferences). Style is
never Critical. Does NOT re-check spec compliance or re-run tests.

#### [testing-implementation](spec-driven-development/testing-implementation/)

Optional feature-level testing stage (user-gated, default yes).
Dispatches a tester subagent that chooses strategy based on the feature
type (UI / backend / library / mixed) and available MCPs (browser
automation for UI, DB MCP for data verification, project test runners
always). Three possible results: **PASS**, **FAIL** (triggers fix-loop
with hard cap of 3 iterations before escalating), **MCP_UNAVAILABLE**
(coordinator surfaces a manual test plan + code-review findings to user;
explicitly forbidden from testing itself). The tester and fixer
subagents load full protocol skills (`testing-feature` and
`fixing-test-failures` respectively); the prompts in this directory are
dispatch envelopes only.

#### [testing-feature](spec-driven-development/testing-feature/)

Protocol skill loaded by the tester subagent. Strategy selection by
feature type (UI / backend / library / mixed), explicit tool inventory
(browser MCPs / DB MCPs / project test runners / HTTP), per-story
execution against acceptance scenarios, three-status output (PASS / FAIL
with per-failure structure / MCP_UNAVAILABLE with manual test plan +
code-review fallback). P1 stories are mandatory floor; P2/P3 covered
when straightforward, marked "not exercised" otherwise. Hard rule
against fabricating results — if you can't run real tools, return
MCP_UNAVAILABLE.

#### [fixing-test-failures](spec-driven-development/fixing-test-failures/)

Protocol skill loaded by the fixer subagent. Narrow-scope fix discipline
(no adjacent refactors, no spec/plan edits), per-failure diagnose →
fix → verify via the tester's exact reproduction. Four-status protocol
(DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT) with the strict
rule that any unverified failure = BLOCKED, never DONE. One commit per
failure when separable, grouped by root cause when shared.

#### [finishing-sdd](spec-driven-development/finishing-sdd/)

Final stage. Verifies tests pass one more time, detects environment
(normal repo vs worktree vs detached HEAD), presents 4 options
(merge-local / PR / keep-as-is / discard — discard requires typed
confirmation) or short-circuits to a single mode based on
`.sublime-skills/config.yml`. Executes the choice, cleans up worktrees that
preflight created (provenance-checked via state file), and deletes the
state file (the spec, plan, ADRs, handoff doc, and git history are the
durable record).

#### [generating-handoff](spec-driven-development/generating-handoff/)

Subagent skill. Reads spec, plan, ADRs, state file, and git log to
produce a self-contained handoff document at
`docs/handoff/YYYY-MM-DD-<short-title>.md`. The handoff is a *bridge*
— it references the source artifacts (with one-line summaries) rather
than duplicating them. Includes a redaction sweep that catches OpenAI/
AWS/GitHub tokens, JWTs, private keys, URLs with credentials, and
sensitive env-var assignments before writing. Schema-validated via
`validate-handoff.sh`. Optimized for the "iterating on PR feedback in a
fresh session" use case.

#### [maintaining-memory-file](spec-driven-development/maintaining-memory-file/)

Subagent skill. After each SDD run, decides whether the project's agent
memory file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md` — auto-
detected or config-pinned) needs updating based on what was produced.
**"No update needed" is the most common outcome** — most features don't
change project-level truth. When an update IS warranted (a new ADR that
introduces a project-wide rule, a new convention, a hard constraint),
the skill writes one-line rules into the appropriate section,
respecting a configurable character cap (default 40000). Strict filters
keep memory files from accreting cruft: no timestamps, no narrative, no
duplicates of code-self-evident truths, no entries that need a paragraph
to explain. Includes a substantial Best Practices section on what
memory files are for, what they're NOT for, healthy size ranges, update
cadence, pruning, and anti-patterns to avoid.

#### [receiving-review-findings](spec-driven-development/receiving-review-findings/)

Inline skill loaded by the coordinator whenever a reviewer subagent
returns findings on a spec or plan (Stages 3, 5, 9, 10). Borrows from
superpowers' `receiving-code-review`: no performative agreement, verify
before fixing, push back with technical reasoning when the reviewer is
wrong, track push-backs in state file, surface to user when findings
need human judgment. Per-task reviews stay handled by
`implementing-plans` (different dynamic — fresh implementer re-dispatch).

#### [inspecting-state](spec-driven-development/inspecting-state/)

Read-only utility. Locates all SDD state files, validates each against
the schema, checks git for pre-state-file interruption signals, and
produces a structured report. Used by the coordinator as its very first
action on every invocation (replaces what used to be the coordinator's
inline resume-detection logic — cleaner separation). Also directly
invokable by the user to check status without entering the pipeline.

### project-bootstrap (separate family)

One-time project setup — a coordinator plus five inline conversational
discovering-X skills. Lives under
[`project-bootstrap/`](project-bootstrap/), separate from the SDD family.
Invoked manually by the user, not by the SDD coordinator.

For the full bootstrap walkthrough (steps, decision tree, re-run semantics,
troubleshooting), see [`docs/bootstrap.md`](docs/bootstrap.md).

#### [bootstrapping-project](project-bootstrap/bootstrapping-project/)

The coordinator. Walks the user through each convention file: detect
existing → ask `Skip / Extend / Replace` (or Create if missing) →
load the matching `discovering-<topic>` skill inline → the skill
handles its own scan, conversation, and atomic write.
Then creates `docs/adr/`, `docs/specs/`, `docs/handoff/` with stub
READMEs; copies the canonical config scaffold at
`project-bootstrap/scaffolds/config.yml` to `.sublime-skills/config.yml`; sets
`context.<name>_path` to `null` for skipped files; runs
`validate-config.sh` in a fix-and-retry loop until PASS; commits.

#### [discovering-constitution](project-bootstrap/discovering-constitution/), [discovering-architecture](project-bootstrap/discovering-architecture/), [discovering-glossary](project-bootstrap/discovering-glossary/), [discovering-domain-model](project-bootstrap/discovering-domain-model/)

Per-artifact inline conversational skills — loaded into the coordinator's
own context (NOT dispatched as subagents). Each does
a silent code scan (per-skill targets: linter / CI / source patterns for
the constitution; build files and infra config for the architecture;
source identifiers and inline comments for the glossary; schemas and
model files for the domain model), announces findings to the user, then
asks targeted questions about anything the code can't reveal (intent
principles, deliberate boundaries, alias confirmations, workflow
exceptions, lifecycle gaps). Each skill drafts, refines via a tweak
loop (cap 3), and atomically writes its file itself.

#### [discovering-design](project-bootstrap/discovering-design/)

Per-artifact inline conversational skill for the visual design system.
Unique among the five for offering an **Import** path in addition to the
standard **Build** path — the user can supply a path to an existing
DESIGN.md (from [styles.refero.design](https://styles.refero.design),
Specify, Tokens Studio, or hand-authored) and the skill verifies +
previews + atomically copies it. Build path runs a code scan (Tailwind
config, CSS custom properties, theme/token files, component libraries)
plus targeted user questions about theme intent, brand vibe, color role
rules, and do's-and-don'ts. Uses one-question-at-a-time structured
prompts with recommended options.

## Setup

What each skill needs before its tools will run:

### browser-tools

- **Node.js** 20, 22, or 24 LTS (Node 26 has a puppeteer extraction bug — see
  the skill's `SKILL.md`).
- **`npm install`** in the `web-utilities/browser-tools/` directory — this also downloads a
  private copy of Chromium (~150 MB, one-time), so no separate browser
  install is needed.

### web-search

- **Node.js** 18 or newer (for the built-in `fetch`). No `npm install` — the
  skill has no dependencies.
- **A reachable SearXNG instance** with the JSON format enabled (`json` listed
  under `search.formats` in its `settings.yml`).
- The instance URL configured via the `SEARXNG_URL` environment variable, or
  by copying `web-utilities/web-search/config.example.json` to
  `web-utilities/web-search/config.json` and setting `searxng_url`.
