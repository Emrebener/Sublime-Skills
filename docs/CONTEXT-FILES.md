# Context files reference

Bootstrap covers 7 convention artifacts (constitution, architecture, testing, glossary, domain, design, memory file) plus supporting directories (`docs/adr/`, `docs/specs/`) and machine-readable config (`.sublime-skills/config.yml`). This file is the index — for each, it documents the owner skill, what the file should/may contain, and what doesn't belong.

For the operational specs of how each file gets discovered and written, see the individual `ss-bs-discovering-<topic>` skills. For the bootstrap pipeline narrative, see [bootstrap.md](bootstrap.md).

---

## 1. `docs/CONSTITUTION.md` — the rules layer

**Owner skill:** `ss-bs-discovering-constitution`
**Authority:** Highest. MUST/SHALL/SHOULD principles cited by SDD reviewers.

**Should contain:**
- A short Overview (what kind of project, what the principles guard)
- A Principles section — 3-7 numbered principles, each with:
  - Name
  - Severity (MUST / SHALL / SHOULD)
  - Statement
  - Evidence / source (lint rule, CI gate, observed pattern)
  - Rationale
- An Amendment Procedure (how this file gets changed)

**May contain (testing-related):**
- Coverage thresholds with gates ("MUST maintain ≥80% line coverage — enforced by CI")
- TDD as a rule ("MUST write the failing test first") 
- Mocking prohibitions ("MUST NOT mock the database in integration tests")
- Lint/type-check severity ("MUST pass tsc --strict with no errors")
- Security gates ("SHALL pass npm audit with no high-severity findings")
- Input validation rules ("MUST validate API inputs at the boundary")

**Should NOT contain:** universal truisms ("write tests", "be consistent"), framework choices, file layout, vocabulary.

---

## 2. `docs/ARCHITECTURE.md` — the system shape layer

**Owner skill:** `ss-bs-discovering-architecture`
**Authority:** Reference for spec/plan writers when reasoning about where new code goes.

**Should contain:**

- System summary (1-paragraph elevator pitch)
- Components (named modules/services with one-line responsibilities)
- Runtime topology (what runs where, processes/services, how they talk)
- Data stores (DBs, caches, queues, blob stores)
- External integrations (third-party APIs, SaaS dependencies)
- Boundaries (in scope / out of scope)

**May contain:**

- Deployment model (single binary, serverless, k8s, edge)
- Async vs sync patterns
- Auth/authz topology
- Repo layout note (monorepo, polyrepo, multi-service)
- Diagram(s) — though the SDD pipeline itself bans them in specs/plans

**Should NOT contain:** code conventions (those go in constitution or memory), domain entities (those go in DOMAIN.md), per-feature designs (those live in docs/specs/).

---

## 3. `docs/TESTING.md` — the **test strategy** layer

**Owner skill:** `ss-bs-discovering-testing`
**Authority:** Reference for engineers writing new tests; consumed by SDD pipeline when verifying test coverage of new features.

**Should contain:**
- **Test categories** — unit / integration / e2e, with the command and path pattern for each
- **Runner & framework** — name, config path, run command, filtered-run command
- **Coverage** — tool, current %, target %, gated in CI?
- **Mocking philosophy** — one-paragraph rule (mock-as-little-as-possible / externals-only / liberal)
- **Fixtures & factories** — location + pattern
- **Conventions** — file naming, test-per-behavior, setup/teardown

**May contain:**
- CI matrix details (Node versions, OS, sharding)
- Performance budgets per test category
- Flaky test register + retry policy
- Test-data privacy rules

**Should NOT contain:** code conventions unrelated to tests (those go in constitution or memory); per-feature test plans (those live in `docs/specs/`).

---

## 4. `docs/GLOSSARY.md` — the vocabulary layer

**Owner skill:** `ss-bs-discovering-glossary`
**Authority:** Canonical definitions; spec/plan writers use these terms verbatim.

**Should contain:**

- Alphabetized terms, each with:
  - Definition (1-3 sentences, project-specific meaning)
  - Aliases / alternative names ("also called X in the legacy code")
  - Optional: example, link to deeper doc

**May contain:**

- Acronyms with expansions
- Disambiguation notes ("Order means X in checkout, Y in fulfillment")
- Deprecated terms with replacements

**Should NOT contain:** entity relationships (that's DOMAIN.md), procedural docs, full domain models.

---

## 5. `docs/DOMAIN.md` — the conceptual model layer

**Owner skill:** `ss-bs-discovering-domain-model`
**Authority:** Source of truth for entities, lifecycles, relationships when specs reason about behavior.

**Should contain:** per entity:

- Name + short description
- Key attributes (the concept-level ones, not every DB column)
- Lifecycle / states (with transitions if any)
- Relationships to other entities (with cardinality: 1:1, 1:N, N:M)
- Workflow exceptions / invariants
- A short Quote section — illustrative sentences from real product/team language

**May contain:**

- Aggregate roots / boundaries
- Ownership rules ("Order belongs to Customer; Items belong to Order")
- Domain events ("OrderPlaced", "PaymentFailed")
- Notes on derived/computed concepts

**Should NOT contain:** DB schema (live in code), implementation details, per-feature flows.

---

## 6. `docs/DESIGN.md` — the visual language layer

**Owner skill:** `ss-bs-discovering-design`
**Authority:** Frontend skills consult this; ignored for backend-only projects.

**Should contain:**

- Tokens — Colors (palette + semantic uses)
- Tokens — Typography (font families, type scale)
- Tokens — Spacing & Shapes (spacing scale, border radii, shadows)
- Surfaces (background/foreground roles, elevation)
- Components (button, input, card, etc. — purpose + variants)
- Do's and Don'ts (concrete visual rules)
- Layout (grid system, breakpoints, density)
- Imagery (photography, illustration, iconography style)
- Quick Start — paste-ready CSS custom properties (and Tailwind v4 block if applicable)

**May contain:**

- Motion / animation tokens
- Dark mode / theme variants
- Accessibility constants (focus rings, contrast minimums)
- Imported file path (when built via Import path, not Build path)

**Should NOT contain:** component implementation code, page-specific layouts.

---

## 7. Agent memory file — the operating manual for agents

**Owner skill (bootstrap / audit):** `ss-bs-discovering-memory-file` — for full draft / refresh during bootstrap or audit
**Owner skill (incremental):** `ss-sdd-maintaining-memory-file` — for incremental additions during SDD feature runs
**Authority:** Loaded every conversation; tells the agent how to actually work in this repo.

The agent memory file is the seventh and final stage of bootstrap. It synthesizes pointers to the other six artifacts.

**Should contain (the four canonical sections):**

- Project conventions — stable patterns (testing approach, error handling, logging style, naming, framework choices)
- Domain vocabulary — 3-15 critical terms (pointer to GLOSSARY.md if longer)
- NEVER / MUST — hard rules with real cost-of-violation
- Pointers — paths/URLs to the deeper docs (constitution, architecture, ADRs, dashboards, runbooks)

**May contain (testing-related):**

- Test framework choice ("Vitest, not Jest")
- Test folder layout ("tests/ mirrors src/")
- Mocking philosophy ("prefer real DB; mock only third-party HTTP")
- Fixture/factory location and conventions
- Commands ("run pnpm test:unit before commit")

**Should NOT contain:**

- Things derivable from a file listing (ls)
- Code patterns visible by reading 3 files
- Things better enforced by a hook (memo: "Always run tests" → use a pre-commit hook instead)
- Ephemeral task state, recent changes (use git log)

---

## 8. `docs/adr/NNNN-*.md` — the decision log

**Owner skill:** `ss-sdd-maintaining-adrs` (incremental, per-feature)
**Bootstrap responsibility:** Just creates `docs/adr/` with a stub README. Does not write ADRs.

**Should contain (per ADR):**

- Status (Proposed / Accepted / Superseded by NNNN / Deprecated)
- Context — the forces at play
- Decision — what was chosen
- Consequences — positive and negative
- Alternatives Considered — each with why-not

---

## 9. `docs/specs/` and `docs/specs/NNN-*/{spec.md, plan.md}` — per-feature artifacts

**Owner:** Not bootstrap. Created by the SDD pipeline.
**Bootstrap responsibility:** Create the directory with a stub README explaining the `NNN-kebab-name/{spec.md, plan.md}` convention.

---

## 10. `.sublime-skills/config.yml` — the machine-readable config

**Owner skill:** `ss-bs-bootstrapping-project` (verbatim copy of `scaffolds/config.yml`, then targeted edits)
**Authority:** Single source of truth for paths and per-stage behavior.

**Contains:**

- `context.<name>_path` for each of the **six** code-rooted convention files (constitution, architecture, testing, glossary, domain, design — or null if skipped)
- `branching.branch_pattern` (e.g., `feat/{short-name}`)
- `memory_file.path` (the seventh artifact's path lives in its own block, not under `context.*` — explicit path or null for auto-detect)
- `memory_file.character_limit` (default 40000)
- `suggest.default` (ask / on / off — controls the suggestion-pass opt-in UX)

**Per-developer overlay:** `.sublime-skills/config-local.yml` — gitignored; any scalar key shadows the matching key in `config.yml`.

---

## Coverage gaps addressed by the 7-artifact bootstrap pipeline

The bootstrap process now covers 7 core artifacts, each with a dedicated discovery skill. Together they establish:

- **Governance** (constitution) — what rules the code must obey
- **Structure** (architecture) — how the code is organized
- **Verification** (testing) — how code quality is proven
- **Communication** (glossary) — what words mean
- **Models** (domain) — what entities exist and relate
- **Aesthetics** (design) — how things look and behave
- **Memory** (agent file) — how to work in this repo

Supporting directories (`docs/adr/`, `docs/specs/`) provide granular decision logs and per-feature specs, while `docs/CONTEXT-FILES.md` (this file) is the index.
