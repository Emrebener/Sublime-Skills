---
1. docs/constitution.md — the rules layer

Owner skill: ss-bs-discovering-constitution
Authority: Highest. MUST/SHALL/SHOULD principles cited by SDD reviewers.

Should contain:
- A short Overview (what kind of project, what the principles guard)
- A Principles section — 3-7 numbered principles, each with:
  - Name
  - Severity (MUST / SHALL / SHOULD)
  - Statement
  - Evidence / source (lint rule, CI gate, observed pattern)
  - Rationale
- An Amendment Procedure (how this file gets changed)

May contain (testing-related — answer to your earlier question):
- Coverage thresholds with gates ("MUST maintain ≥80% line coverage — enforced by CI")
- TDD as a rule ("MUST write the failing test first") 
- Mocking prohibitions ("MUST NOT mock the database in integration tests")
- Lint/type-check severity ("MUST pass tsc --strict with no errors")
- Security gates ("SHALL pass npm audit with no high-severity findings")
- Input validation rules ("MUST validate API inputs at the boundary")

Should NOT contain: universal truisms ("write tests", "be consistent"), framework choices, file layout, vocabulary.

---
1. docs/ARCHITECTURE.md — the system shape layer

Owner skill: ss-bs-discovering-architecture
Authority: Reference for spec/plan writers when reasoning about where new code goes.

Should contain:

- System summary (1-paragraph elevator pitch)
- Components (named modules/services with one-line responsibilities)
- Runtime topology (what runs where, processes/services, how they talk)
- Data stores (DBs, caches, queues, blob stores)
- External integrations (third-party APIs, SaaS dependencies)
- Boundaries (in scope / out of scope)

May contain:

- Deployment model (single binary, serverless, k8s, edge)
- Async vs sync patterns
- Auth/authz topology
- Repo layout note (monorepo, polyrepo, multi-service)
- Diagram(s) — though the SDD pipeline itself bans them in specs/plans

Should NOT contain: code conventions (those go in constitution or memory), domain entities (those go in DOMAIN.md), per-feature designs (those live in docs/specs/).

---
1. docs/GLOSSARY.md — the vocabulary layer

Owner skill: ss-bs-discovering-glossary
Authority: Canonical definitions; spec/plan writers use these terms verbatim.

Should contain:

- Alphabetized terms, each with:
  - Definition (1-3 sentences, project-specific meaning)
  - Aliases / alternative names ("also called X in the legacy code")
  - Optional: example, link to deeper doc

May contain:

- Acronyms with expansions
- Disambiguation notes ("Order means X in checkout, Y in fulfillment")
- Deprecated terms with replacements

Should NOT contain: entity relationships (that's DOMAIN.md), procedural docs, full domain models.

---
1. docs/DOMAIN.md — the conceptual model layer

Owner skill: ss-bs-discovering-domain-model
Authority: Source of truth for entities, lifecycles, relationships when specs reason about behavior.

Should contain: per entity:

- Name + short description
- Key attributes (the concept-level ones, not every DB column)
- Lifecycle / states (with transitions if any)
- Relationships to other entities (with cardinality: 1:1, 1:N, N:M)
- Workflow exceptions / invariants
- A short Quote section — illustrative sentences from real product/team language

May contain:

- Aggregate roots / boundaries
- Ownership rules ("Order belongs to Customer; Items belong to Order")
- Domain events ("OrderPlaced", "PaymentFailed")
- Notes on derived/computed concepts

Should NOT contain: DB schema (live in code), implementation details, per-feature flows.

---
1. docs/DESIGN.md — the visual language layer

Owner skill: ss-bs-discovering-design
Authority: Frontend skills consult this; ignored for backend-only projects.

Should contain:

- Tokens — Colors (palette + semantic uses)
- Tokens — Typography (font families, type scale)
- Tokens — Spacing & Shapes (spacing scale, border radii, shadows)
- Surfaces (background/foreground roles, elevation)
- Components (button, input, card, etc. — purpose + variants)
- Do's and Don'ts (concrete visual rules)
- Layout (grid system, breakpoints, density)
- Imagery (photography, illustration, iconography style)
- Quick Start — paste-ready CSS custom properties (and Tailwind v4 block if applicable)

May contain:

- Motion / animation tokens
- Dark mode / theme variants
- Accessibility constants (focus rings, contrast minimums)
- Imported file path (when built via Import path, not Build path)

Should NOT contain: component implementation code, page-specific layouts.

---
1. CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md — the operating manual for agents

Owner skill: ss-sdd-maintaining-memory-file (incrementally; not the bootstrapper directly — but the bootstrapper should encourage it)
Authority: Loaded every conversation; tells the agent how to actually work in this repo.

Should contain (the four canonical sections):

- Project conventions — stable patterns (testing approach, error handling, logging style, naming, framework choices)
- Domain vocabulary — 3-15 critical terms (pointer to GLOSSARY.md if longer)
- NEVER / MUST — hard rules with real cost-of-violation
- Pointers — paths/URLs to the deeper docs (constitution, architecture, ADRs, dashboards, runbooks)

May contain (testing-related — answer to your earlier question):

- Test framework choice ("Vitest, not Jest")
- Test folder layout ("tests/ mirrors src/")
- Mocking philosophy ("prefer real DB; mock only third-party HTTP")
- Fixture/factory location and conventions
- Commands ("run pnpm test:unit before commit")

Should NOT contain:

- Things derivable from a file listing (ls)
- Code patterns visible by reading 3 files
- Things better enforced by a hook (memo: "Always run tests" → use a pre-commit hook instead)
- Ephemeral task state, recent changes (use git log)

---
1. docs/adr/NNNN-*.md — the decision log

Owner skill: ss-sdd-maintaining-adrs (incremental, per-feature)
Bootstrap responsibility: Just creates docs/adr/ with a stub README. Does not write ADRs.

Should contain (per ADR):

- Status (Proposed / Accepted / Superseded by NNNN / Deprecated)
- Context — the forces at play
- Decision — what was chosen
- Consequences — positive and negative
- Alternatives Considered — each with why-not

---
1. docs/specs/ and docs/specs/NNN-*/ — per-feature artifacts

Owner: Not bootstrap. Created by the SDD pipeline.
Bootstrap responsibility: Create the directory with a stub README explaining the NNN-kebab-name/{spec.md, plan.md} convention.

---
Should NOT contain:

- Things derivable from a file listing (ls)
- Code patterns visible by reading 3 files
- Things better enforced by a hook (memo: "Always run tests" → use a pre-commit hook instead)
- Ephemeral task state, recent changes (use git log)

---
1. docs/adr/NNNN-*.md — the decision log

Owner skill: ss-sdd-maintaining-adrs (incremental, per-feature)
Bootstrap responsibility: Just creates docs/adr/ with a stub README. Does not write ADRs.

Should contain (per ADR):

- Status (Proposed / Accepted / Superseded by NNNN / Deprecated)
Should NOT contain:
- Things derivable from a file listing (ls)
- Code patterns visible by reading 3 files
- Things better enforced by a hook (memo: "Always run tests" → use a pre-commit hook instead)
- Ephemeral task state, recent changes (use git log)

---
1. docs/adr/NNNN-*.md — the decision log

Owner skill: ss-sdd-maintaining-adrs (incremental, per-feature)
Bootstrap responsibility: Just creates docs/adr/ with a stub README. Does not write ADRs.

Should contain (per ADR):

- Status (Proposed / Accepted / Superseded by NNNN / Deprecated)
- Context — the forces at play
- Decision — what was chosen
- Consequences — positive and negative
- Alternatives Considered — each with why-not

---
1. docs/specs/ and docs/specs/NNN-*/ — per-feature artifacts

Owner: Not bootstrap. Created by the SDD pipeline.
Bootstrap responsibility: Create the directory with a stub README explaining the NNN-kebab-name/{spec.md, plan.md} convention.

---
1. .sublime-skills/config.yml — the machine-readable config

Owner skill: ss-bs-bootstrapping-project (verbatim copy of scaffolds/config.yml, then targeted edits)
Authority: Single source of truth for paths and per-stage behavior.

Contains:

- context.<name>_path for each of the five convention files (or null if skipped)
- branching.branch_pattern (e.g., feat/{short-name})
- grill.question_cap (soft cap on grill stage questions)
- memory_file.path (explicit path or null for auto-detect)
- memory_file.character_limit (default 40000)

Per-developer overlay: .sublime-skills/config-local.yml — gitignored; any scalar key shadows the matching key in config.yml.

---
Coverage gaps worth considering for the bootstrapper

A few things don't have a clear home today and might warrant either a new artifact or an explicit "goes in X" rule:

1. Testing strategy beyond what fits in constitution/memory — fixture conventions, complex mocking patterns, integration-test setup, CI-only tests. Currently scattered; could become a docs/TESTING.md or live as a constitution
principle + memory pointer.
2. Runbook / operations — on-call, incident response, deployment steps. Often valuable to agents fixing prod bugs; nothing in bootstrap covers it.
3. Security model / threat model — partial overlap with constitution but deeper. Currently no dedicated artifact.
4. API contracts — OpenAPI/protobuf/GraphQL schemas. Usually live in code, but a pointer in ARCHITECTURE.md or memory is sometimes missing.
5. The README itself — not covered, even though it's the highest-traffic context file for humans. Could merit a discovery skill that ensures the README is agent-readable (purpose, setup, dev commands).
