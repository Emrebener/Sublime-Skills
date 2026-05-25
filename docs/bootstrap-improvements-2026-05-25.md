# Bootstrap pipeline improvements — design

**Date:** 2026-05-25
**Status:** Approved design, pending implementation plan
**Scope:** `skills/project-bootstrap/` and supporting framework scripts
**Related docs:** `docs/bootstrap.md` (current pipeline narrative), `docs/CONTEXT-FILES.md` (artifact responsibilities)

---

## TL;DR

The bootstrap pipeline today is **descriptive**: it scans the project, asks the user a few questions, and codifies what already exists into five convention files. This design adds a **prescriptive** capability — an evidence-grounded "suggestion pass" that flags anti-patterns and missing-but-typically-valuable patterns in each artifact, opt-in once at the coordinator level. It also adds two new artifacts (`docs/TESTING.md` and an agent memory file), a final cross-artifact coherence check before commit, and a sibling skill `ss-bs-auditing-project` for re-evaluating already-bootstrapped projects. The pipeline grows from 5 to 7 artifacts and from 9 to 11 coordinator steps; existing behavior is preserved when the suggestion pass is off.

---

## Table of contents

1. [Background](#1-background)
2. [Problem](#2-problem)
3. [Goals and non-goals](#3-goals-and-non-goals)
4. [Pipeline shape](#4-pipeline-shape)
5. [Coordinator flow](#5-coordinator-flow)
6. [Suggestion pass mechanic](#6-suggestion-pass-mechanic)
7. [New skill — `ss-bs-discovering-testing`](#7-new-skill--ss-bs-discovering-testing)
8. [New skill — `ss-bs-discovering-memory-file`](#8-new-skill--ss-bs-discovering-memory-file)
9. [New skill — `ss-bs-auditing-project`](#9-new-skill--ss-bs-auditing-project)
10. [Cross-artifact coherence check](#10-cross-artifact-coherence-check)
11. [Config and framework changes](#11-config-and-framework-changes)
12. [Affected files inventory](#12-affected-files-inventory)
13. [Trade-offs and rejected alternatives](#13-trade-offs-and-rejected-alternatives)
14. [Open questions for the implementation phase](#14-open-questions-for-the-implementation-phase)

---

## 1. Background

The current bootstrap pipeline is implemented in `skills/project-bootstrap/`:

- A coordinator skill (`ss-bs-bootstrapping-project`) walks the user through five convention files in a fixed order: constitution → architecture → glossary → domain → design.
- For each file, a dedicated `ss-bs-discovering-<topic>` skill is loaded inline (never as a subagent). Each follows a uniform 6-step shape: silent code scan → announce findings → targeted Q&A → draft → 3-iteration refine loop → atomic write.
- After all five files are settled, the coordinator creates supporting directories (`docs/adr/`, `docs/specs/`), copies the config scaffold to `.sublime-skills/config.yml`, validates it, ensures `.gitignore` is correct, and produces a single bundled commit.

The pipeline already handles many things well:
- Sequential per-file walk (user can reason about each artifact independently)
- Idempotent re-runs (safe to invoke repeatedly)
- Atomic writes (`.tmp` + `mv`)
- Per-skill iteration caps (no infinite refine loops)
- A todo list at the start (the user can follow along)
- Evidence-based candidate proposals (e.g. constitution scans linter configs, CI gates, source samples)
- Three modes per file: skip / extend / replace (matches "skip / improve / rewrite" in plain language)

What is missing is the spirit of the proposal phase. Discovering skills today describe what they find; they do not flag what is wrong with what they find or what should also be there.

## 2. Problem

The bootstrap today has two structural gaps and one behavioural gap.

**Behavioural gap — descriptive only.** Every discovering skill captures observed evidence and turns it into artifact content. None of them propose additions for things that are *missing* (gaps a typical healthy project would have) or *problematic* (anti-patterns visible in the code). A project with cross-module direct DB access, scattered hex literals instead of design tokens, or god entities will end up with artifacts that faithfully document those patterns. The bootstrap therefore enshrines the project's current state, including its problems, instead of nudging the project toward better convention.

**Structural gap — missing test-strategy artifact.** Testing conventions today have no clear home. Severity-bearing testing rules ("MUST hit ≥80% coverage") land in the constitution. Framework choice, test folder layout, fixture conventions, and mocking philosophy belong in the agent memory file. Anything that does not fit either bucket has nowhere to go. Users with substantial test strategy end up squeezing it into the constitution or scattering it across memory.

**Structural gap — agent memory file is not bootstrapped.** The agent memory file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.agents.md`) is the highest-traffic context file for any future agent session, yet bootstrap leaves it untouched. The existing `ss-sdd-maintaining-memory-file` only updates it incrementally during SDD spec runs. A user can finish bootstrap and start their first agent session with no memory file at all.

A secondary need surfaces once the prescriptive capability lands: a way to re-run the bootstrap on a project that has been live for a while, with focus on **drift**, **incoherence**, and **improvement opportunities** rather than initial setup. The current bootstrap is technically safe to re-run, but its UX is tuned for first-time use (sequential per-file create-or-extend prompts) and it does not detect drift between artifact content and current code state.

## 3. Goals and non-goals

**Goals:**

- Preserve all current behaviour when the prescriptive pass is off. A user running bootstrap with `SUGGEST=off` should see bit-for-bit the same flow as today.
- Add an evidence-grounded suggestion mechanism to each discovering skill, with strict guardrails that prevent it generating noise.
- Make the suggestion pass opt-in at the coordinator level — a single switch at the start of bootstrap, not five per-file decisions.
- Add `docs/TESTING.md` and an agent memory file as new artifacts, each produced by its own discovering skill that follows the existing 6-step shape.
- Add a cross-artifact coherence check that runs once at the end of bootstrap and at the start of audit, surfaces inconsistencies, and lets the user loop back into the relevant stages.
- Add a sibling skill `ss-bs-auditing-project` for re-evaluating already-bootstrapped projects. It re-uses the discovering skills via a new `MODE=audit`, runs prescriptive-by-default, and commits stage-by-stage so the user can accept some changes and decline others.

**Non-goals:**

- Auto-fixing problems in the codebase. The suggestion pass proposes additions to documentation; it does not edit project source code.
- Hard-blocking commits on coherence failures. Findings are surfaced with strong defaults but the user can always override.
- Maintaining multiple memory files in sync (e.g. CLAUDE.md and AGENTS.md side by side for teams using multiple harnesses). Bootstrap maintains exactly one memory file per project.
- Persisting coherence reports or audit reports to disk. Findings are surfaced in-conversation only.
- Changing the existing 6-step shape of discovering skills or the existing skill-loading mechanism. New behaviour is added as additional steps or modes, not by reshaping what is there.

## 4. Pipeline shape

The pipeline grows from 5 artifacts to 7, in this order:

| # | Artifact | Skill | Status |
|---|---|---|---|
| 1 | `docs/constitution.md` | `ss-bs-discovering-constitution` | Modified (add suggestion pass, drift check, audit mode) |
| 2 | `docs/ARCHITECTURE.md` | `ss-bs-discovering-architecture` | Modified (same) |
| 3 | `docs/TESTING.md` | `ss-bs-discovering-testing` | **NEW skill** |
| 4 | `docs/GLOSSARY.md` | `ss-bs-discovering-glossary` | Modified (same) |
| 5 | `docs/DOMAIN.md` | `ss-bs-discovering-domain-model` | Modified (same) |
| 6 | `docs/DESIGN.md` | `ss-bs-discovering-design` | Modified (same) |
| 7 | Memory file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.agents.md`) | `ss-bs-discovering-memory-file` | **NEW skill** |

**Ordering rationale:**

- **Constitution first.** Principles can be cited by every later artifact ("this architecture upholds principle X"). Doing it first means later stages have access to the agreed rules.
- **Architecture second.** System shape is context for everything else.
- **Testing right after architecture.** The test strategy depends on knowing the deployable units, data stores, and external integrations. Slotting testing between architecture and glossary makes that dependency natural.
- **Glossary before domain.** Domain entities use glossary terms; defining the vocabulary first means domain.md is consistent.
- **Design last among code-rooted stages.** Largely independent of the others.
- **Memory file last.** It synthesizes pointers to the other six. Running it last means it can reference paths the user just committed to.

## 5. Coordinator flow

The bootstrap coordinator's step list grows from 9 to 11. Additions are marked `[NEW]`; everything else is unchanged. A sub-step between Step 2 and Step 3 builds the user-visible todo list — analogous to the existing Step 1.5 in today's coordinator — and is not itself counted as a top-level step.

1. Detect existing setup
2. **[NEW]** Suggestion-pass opt-in switch — single question at the top of the run
   - *Sub-step:* build the todo list (now 14 items: 7 stages + supporting dirs + config copy + config edit + validate-config + coherence check + gitignore housekeeping + commit)
3. Per-file loop, now 7 stages in the order above; each discovering skill is invoked inline with `SUGGEST=on|off` from Step 2
4. Create supporting directories (`docs/adr/`, `docs/specs/`)
5. Copy config scaffold; create empty `.sublime-skills/config-local.yml`; create `.sublime-skills/.gitignore` if missing
6. Edit config to reflect reality (set `<name>_path: null` for skipped stages; update paths if non-default)
7. Validate config (cap of 3 fix-and-retry attempts; halt and surface on third failure)
8. **[NEW]** Cross-artifact coherence check; user can loop back into stages or accept-and-move-on
9. Gitignore housekeeping (idempotent append-if-missing for the two required entries)
10. Single bundled commit
11. Report and direct the user to `ss-sdd-coordinator`

The opt-in question in Step 2:

```
Before the per-file walkthrough, one preference question:

Do you want me to also propose improvements where I see opportunities,
or just document what exists?

  - Descriptive only (document what's there — fastest, safest)
  - Descriptive + suggestions (Recommended — flags anti-patterns and
    missing-but-typically-valuable patterns, cited from evidence)
  - Skip bootstrap and run audit mode instead (for established projects
    where you want the deeper read)
```

The third option routes to `ss-bs-auditing-project` and ends the bootstrap.

## 6. Suggestion pass mechanic

The central change. Same shape in every discovering skill (the existing five plus the two new ones), parameterized by what each skill knows how to diagnose.

### 6.1 Where it slots in

Each discovering skill's existing 6-step structure gains one new step and one new question:

```
Step 1   — Silent scan (observe what's there)              [existing]
Step 1.5 — Silent diagnose (find smells + gaps)            [NEW, only if SUGGEST=on]
Step 2   — Announce findings (observations + diagnoses)    [modified]
Step 3   — Targeted questions
   Q1    — Confirm observed candidates                     [existing]
   Q1.5  — Confirm suggested additions                     [NEW, only if SUGGEST=on]
   Q2-Q5 — (skill-specific questions, unchanged)
Step 4-6 — Draft, refine, atomic write                     [existing]
```

When `SUGGEST=off`, Steps 1.5 and Q1.5 are skipped entirely — no extra reads, no extra prompts, identical behaviour to today.

### 6.2 What "diagnose" means per skill

Diagnose categories are domain-specific. Every diagnose must cite specific evidence — no abstract best practices.

| Skill | Things it diagnoses |
|---|---|
| `discovering-constitution` | Missing principles where the project's stack implies one is needed; weak severity (e.g. `warn` lint rule that should be `error`); contradictions between stated principles and observed code |
| `discovering-architecture` | Cross-service direct DB access; synchronous chains where async would add resilience; shared mutable state across modules; missing boundaries / ownership rules for shared code; missing API gateways for public surfaces |
| `discovering-testing` | Missing test categories (only unit; no integration coverage of API layer); untested critical files; heavy mocking smells; CI gate gaps (tests run but no coverage threshold, or the threshold is `warn`) |
| `discovering-glossary` | Term inconsistencies (user / account / customer used as synonyms across N files); high-traffic acronyms with no definition; aliases that should be unified |
| `discovering-domain-model` | God entities (too many attributes / relationships); anemic models (no behaviour); missing aggregate roots; undocumented state machines visible in code |
| `discovering-design` | Hex literals scattered through CSS that should be tokenized; inconsistent spacing (no scale); only literal colors with no semantic roles; component variants present in code but absent from doc |
| `discovering-memory-file` | Missing pointers to artifacts that exist; stale conventions contradicting current code; rules better enforced as hooks than as memory lines |

### 6.3 Generation rules (hard guardrails)

Every suggestion MUST satisfy all of these or it does not surface:

1. **Cites specific evidence** — at least one file path, or a concrete count ("12 of 18 handlers"). No abstract "you should validate inputs".
2. **Names a concrete addition** — exact text for the artifact, not "consider adding something about X".
3. **Severity matches evidence quality:**
   - **MUST / SHALL** — only with strong observable harm (broken tests, security risk, observed bug pattern).
   - **SHOULD** — with consistent code-smell evidence.
   - **Informational** — for "consider declaring" or "nice to document" items.
4. **Hard cap: 5 suggestions per stage.** If diagnose finds more, rank by severity → evidence strength → impact and surface the top 5. The rest are dropped silently — they will return in the next audit if still relevant.
5. **No quota.** If diagnose finds zero strong suggestions, the list is empty and Q1.5 is skipped. This inherits the existing "no truisms / no padding" guardrail from `ss-bs-discovering-constitution`.

### 6.4 How Q1.5 looks to the user

After Q1 (confirm observed candidates), if `SUGGEST=on` AND diagnose produced ≥1 suggestion:

```
Q1.5: Here are some things I'd suggest adding even though they're not
currently codified. These are opinionated — pick any you want to include:

  - [suggestion · MUST · 12 files] Validate API inputs at boundary
    Evidence: src/api/{users,orders,payments,...}.ts consume req.body
    without schema validation (12 of 18 Express handlers).
    Proposed addition: "MUST validate all API inputs via Zod schema at
    the handler entry point before any business logic runs."

  - [suggestion · SHOULD · 3 files] Declare cross-service DB access policy
    Evidence: services/billing/src/invoice.ts:34, .../report.ts:88,
    .../sync.ts:12 read checkout.orders directly via shared Postgres.
    Proposed addition: "Cross-service data access SHOULD go through
    HTTP APIs, not shared schemas."

  - None of these — keep the doc descriptive only
```

The `[suggestion · severity · evidence-summary]` prefix makes the prescriptive nature visually distinct from Q1's observed candidates.

### 6.5 How accepted suggestions land in the artifact

An accepted suggestion becomes a regular entry in the output (principle, component, term, etc.), with a **provenance marker** noting it came from the suggestion pass:

```markdown
### Principle 4 — Input Validation Discipline

**Severity:** MUST

**Statement:** All API handlers MUST validate inputs at the boundary
using a schema validator (Zod, Ajv, etc.) before processing.

**Evidence:** Not currently enforced — added via bootstrap suggestion
pass (2026-05-25). Diagnose found 12 of 18 Express handlers consume
req.body without validation.

**Rationale:** Prevents type errors and injection attacks at the
boundary; centralizes input shape contracts.
```

The "Not currently enforced — added via bootstrap suggestion pass (YYYY-MM-DD)" line is the provenance hook. The audit skill reads it on re-runs to ask whether the principle is still aspirational or the code has caught up.

### 6.6 Per-skill diagnose budgets

Diagnose adds latency. To keep bootstrap fast and predictable:

- **Time budget per skill:** diagnose should complete within ~2 minutes of agent work. Documented in each skill's Hard Gates section.
- **Read budget per skill:** diagnose may read up to 10 additional files beyond what Step 1 read. If it needs more, it surfaces fewer suggestions instead of doing a deeper read.

These are soft caps that protect the bootstrap's overall pace. Exceeding them is a sign the skill should ship narrower suggestion logic, not a sign to widen the budget.

## 7. New skill — `ss-bs-discovering-testing`

**Target file:** `docs/TESTING.md` (configurable via `context.testing_path`).

**6-step shape** matches the existing discovering skills.

### 7.1 Step 1 substeps (silent scan)

| Substep | What it reads |
|---|---|
| 1a. Test directories | `tests/`, `test/`, `__tests__/`, `spec/`, `e2e/`, `integration/` |
| 1b. Runner config | `jest.config.*`, `vitest.config.*`, `pytest.ini`, `pyproject.toml [tool.pytest]`, `.rspec`, `go.mod` test deps, `Cargo.toml` dev-dependencies |
| 1c. Naming patterns | `*.test.ts`, `*_test.go`, `test_*.py`, `*Spec.kt` (sampled from one test dir) |
| 1d. CI test commands | Extracted from CI workflow files (`.github/workflows/*.yml`, etc.) |
| 1e. Coverage tooling | `c8`, `istanbul`, `coverage.py`, `simplecov` deps + their configs |
| 1f. Coverage thresholds | Configured threshold OR threshold gate in CI |
| 1g. Mocking framework signal | `jest.mock` imports, `sinon`, `unittest.mock`, `mockall`, `gomock` |
| 1h. Fixture / factory patterns | `factories/`, `fixtures/`, `factory_bot`, `faker` deps |
| 1i. Test categorization | Directory structure (`unit/` vs `integration/` vs `e2e/`) or tag/marker conventions |

### 7.2 Step 1.5 diagnose candidates (if `SUGGEST=on`)

- Missing test categories (only unit tests exist; no integration coverage of API layer).
- Large untested critical files (file in `src/` >200 LOC with no matching test file).
- Heavy mocking smells (e.g. DB mocked in >80% of tests).
- CI gap (tests run but no coverage gate, or gate exists as `warn` not `fail`).
- Naming inconsistency (mix of `*.test.ts` and `*.spec.ts`).

### 7.3 Step 3 questions beyond Q1 / Q1.5

- **Q2 — Canonical test commands** (multi-select from CI-extracted commands).
- **Q3 — Mocking philosophy** (multi-choice: *Mock as little as possible (real DB, real network with VCR)* / *Mock externals only (HTTP, queues), real DB* / *Mock liberally (fast unit tests, separate integration suite)*).
- **Q4 — Fixture / factory location** (free-form, defaulted from scan).
- **Q5 — (extend mode only)** resolve conflicts between existing TESTING.md content and scan findings.

### 7.4 Output template (sections)

```
# Testing

## Test categories           (unit / integration / e2e + commands)
## Runner & framework        (framework, config path, run commands)
## Coverage                  (tool, current %, target %, gated in CI?)
## Mocking philosophy        (one-paragraph rule from Q3)
## Fixtures & factories      (location + pattern)
## Conventions               (file naming, test-per-behavior vs test-per-file, etc.)
```

### 7.5 Edge case — empty project / no tests yet

When scan returns near-empty (e.g. a brand-new project), generating a wall of "add tests for X, Y, Z" suggestions would be noise. The skill detects this and shifts to **new-project mode**: instead of running diagnose, it walks the user through a short starter-strategy Q&A (what's the runner going to be, what categories to target, what coverage to aim for) and produces a starter TESTING.md.

## 8. New skill — `ss-bs-discovering-memory-file`

**Target file:** detected at `memory_file.path` (the existing SDD config key) OR, if null, auto-detected from `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md` in that order.

### 8.1 Step 0 (NEW substep before Step 1) — detect target file

- **No file exists, none configured:** ask which to create. Multi-choice from the four canonical filenames. `CLAUDE.md` highlighted as default; user can override.
- **One file exists:** use it.
- **Multiple files exist:** ask which is canonical for bootstrap maintenance. The others are left alone — bootstrap only maintains one memory file per project.

After Step 0, if the user creates a new file (or picks an existing one as canonical), the skill writes the chosen path back to `memory_file.path` in `.sublime-skills/config.yml` so subsequent SDD runs do not auto-detect.

### 8.2 Step 1 substeps (silent scan)

| Substep | What it reads |
|---|---|
| 1a. The 6 other artifacts | Whatever was written/skipped in this bootstrap run, read fresh from disk |
| 1b. Run commands | `package.json` scripts, `Makefile`, `justfile`, `Taskfile.yml`, `pyproject.toml` scripts — extract test, lint, build, run, dev |
| 1c. Existing memory file content | Extend mode only |
| 1d. Repo root README | First section as the project's one-line description |

### 8.3 Step 1.5 diagnose candidates (if `SUGGEST=on`)

- Missing pointers to artifacts that exist (e.g. memory says nothing about ARCHITECTURE.md even though it was just written).
- Stale entries (memory says "use Pytest" but code shows Vitest).
- Items better as hooks than as memory ("always run tests before commit" → suggest pre-commit hook).
- Rules creeping in that belong in the constitution (a "MUST" in memory has stronger home in the constitution).

### 8.4 Step 3 questions beyond Q1 / Q1.5

- **Q2 — Which canonical sections to include** (multi-select: *Project conventions* / *Domain vocabulary* / *NEVER-MUST* / *Pointers*; all recommended for non-trivial projects).
- **Q3 — Confirm auto-extracted pointers** (multi-select from the 6 artifact paths + `README.md` + `docs/adr/` + `docs/specs/`).
- **Q4 — Free-form additions for "project conventions"** (things the agent should know but aren't visible from the artifacts).
- **Q5 — Confirm NEVER/MUST list** (seeded from constitution's MUSTs; user can prune or add).

### 8.5 Output template (sections)

```
# <Project Name>             (one-liner from README)

## Project conventions       (3-7 stable patterns)
## Domain vocabulary         (short list + pointer to GLOSSARY.md)
## NEVER / MUST              (hard rules; seeded from constitution)
## Pointers                  (linkdump to docs/{constitution, ARCHITECTURE, TESTING, …})
## Commands                  (test, lint, build, run, dev)
```

### 8.6 Character budget

The skill respects `memory_file.character_limit` from `.sublime-skills/config.yml` (default 40000). If the synthesized draft exceeds 90% of the limit, the skill warns and asks which sections to trim before writing.

### 8.7 Relationship with `ss-sdd-maintaining-memory-file`

The two memory-file skills serve different lifecycle stages and do not conflict:

| Skill | Trigger | What it does |
|---|---|---|
| `ss-bs-discovering-memory-file` (this design) | Bootstrap or audit | Full draft / refresh, synthesizing pointers from the 6 artifacts |
| `ss-sdd-maintaining-memory-file` (existing) | SDD Stage 16 (after feature runs) | Incremental additions from ADRs and specs |

Both respect the same character budget.

## 9. New skill — `ss-bs-auditing-project`

A sibling skill to `ss-bs-bootstrapping-project`. Same per-file discovery skills underneath; different coordinator flow optimized for re-evaluation.

### 9.1 Purpose

Re-evaluate an already-bootstrapped project for drift, incoherence, and improvement opportunities. Distinct from bootstrap's "set up baseline" job. Run cases include quarterly project health checks, post-refactor sweeps, new-contributor onboarding prep, and ad-hoc "this doc feels stale" investigations.

### 9.2 What makes audit different from "bootstrap re-run with `SUGGEST=on`"

| Dimension | Bootstrap re-run | Audit |
|---|---|---|
| Default for `SUGGEST` | `ask` (preserves choice) | always `on` |
| Coherence check timing | Last (gate before commit) | **First** (drives the per-stage loop) |
| Commit shape | Single bundled commit | **One commit per stage** (selective acceptance) |
| Drift detection between artifact and code | No | **Yes** (third operation alongside observe and diagnose) |
| Assumes config + dirs exist | Idempotent — recreates if missing | Hard requirement — directs to bootstrap if missing |

### 9.3 New MODE — `audit`

The existing discovering skills accept `MODE = create | extend | replace`. Audit adds `MODE = audit`. When invoked with this mode, each discovering skill:

1. Reads the existing artifact (like `extend`).
2. Re-runs Step 1 silent scan.
3. **Runs Step 1.6 — Drift check (NEW for audit).** For each entry in the existing artifact, verify it still matches code:

    | Skill | Drift signal example |
    |---|---|
    | Constitution | Principle cites `no-any` rule in `.eslintrc.json` → rule no longer exists |
    | Architecture | Doc lists 3 services → repo now has 5 |
    | Testing | Doc says "Jest" → `package.json` shows Vitest |
    | Glossary | Term "Order" defined → renamed to "PurchaseOrder" in code |
    | Domain | Entity states `{Draft, Submitted, Shipped}` → code adds `Refunded` |
    | Design | Token `--color-primary: #3B82F6` → no longer in CSS |
    | Memory file | Pointer to `docs/X.md` → file deleted |

4. Runs Step 1.5 diagnose (always on in audit mode).
5. Step 3 questions reorganize: **Q0 — Drift resolution** comes first (per drift item: keep doc, update doc to match code, remove the entry). Then Q1 (observed) / Q1.5 (suggested) per the normal flow.

### 9.4 Coordinator flow

1. **Preflight.** Verify `.sublime-skills/config.yml` exists and validates. Verify at least one artifact exists per the configured paths. If neither, redirect: "This project isn't bootstrapped — run `ss-bs-bootstrapping-project` first."
2. **Cross-artifact coherence pass.** Read all 7 artifacts (skipping null-configured ones). Run the Tier 1 checks (Section 10). Surface findings to the user verbatim, do not summarize.
3. **User picks scope:**
    - *Fix the top N coherence findings stage-by-stage (Recommended)* — auto-orders stages by where findings cluster.
    - *I'll pick which stages to revisit* — multi-select from the 7 stages.
    - *Run a full audit on every stage* — invoke all 7.
    - *Skip — I just wanted the report*.
4. **Per-stage audit loop.** For each picked stage:
    - Load matching `discovering-X` skill with `MODE=audit`, `SUGGEST=on`.
    - Skill returns updated content (or "no changes recommended").
    - **Commit immediately** with descriptive message: `audit: update ARCHITECTURE.md — declare cross-service boundaries`.
5. **Final coherence re-check.** Re-run the coherence pass; report what's still outstanding (some findings may persist if the user declined a stage).
6. **Summary report (conversation-only):**
    ```
    Audit complete.

    Stages updated:
    - ARCHITECTURE.md — 2 drift items fixed, 1 suggestion accepted (committed: <sha>)
    - TESTING.md — 1 drift item fixed (committed: <sha>)

    Stages reviewed, no changes:
    - constitution.md — no drift, 0 suggestions accepted

    Stages declined:
    - DESIGN.md — user declined to revisit

    Remaining coherence findings:
    - GLOSSARY.md term "Order" no longer used in code
      (DOMAIN.md updated, glossary skipped)
    ```

### 9.5 Why per-stage commits

A single bundled commit forces the user into all-or-nothing acceptance. Audit findings are independent — accepting an architectural boundary change should not block accepting a testing-strategy update. Per-stage commits enable selective acceptance. The cost is commit log noise (a thorough audit could produce 7 commits), which is acceptable because audits are infrequent and each commit message is informative.

### 9.6 Why the report is conversation-only

Persisting a report (`docs/.audit-report-YYYY-MM-DD.md`) would mean: file lifecycle (when's it stale, who deletes), gitignore policy, naming convention, potential merge conflicts. All real costs for a report whose usefulness is highest at the moment it surfaces. If the user wants a record, they can copy from the conversation.

## 10. Cross-artifact coherence check

Runs at two points: **end of bootstrap (Step 8 in the coordinator flow)** and **start of audit (drives the per-stage loop)**.

### 10.1 Tier 1 — Structural / pointer checks (cheap, deterministic; runs in both bootstrap and audit)

| Check | Failure shape | Severity |
|---|---|---|
| Every file path mentioned in any artifact exists on disk | Memory file points to `docs/DESIGN.md` but file doesn't exist | CRITICAL |
| Memory file's Pointers section lists every other artifact that exists | `docs/TESTING.md` exists but memory has no pointer | WARNING |
| Every entity named in DOMAIN.md is defined in GLOSSARY.md (or is a proper-noun whitelist match) | `PurchaseOrder` defined in DOMAIN.md, missing from GLOSSARY.md | WARNING |
| Every architectural component in ARCHITECTURE.md is mentioned in TESTING.md | ARCHITECTURE.md lists "worker" component, TESTING.md doesn't address worker testing | INFO |
| Constitution principles that cite an evidence file → that file exists | Principle 3 cites `.eslintrc.json` which has since been deleted | CRITICAL |
| Constitution principles do not contradict each other within the file | Principle 1 says MUST use Result types; Principle 4 says MUST throw on validation errors | WARNING |
| Suggestion-pass provenance markers older than 6 months without resolution | Aspirational principle from 2025-11-20 still not enforced | INFO (audit-only) |

### 10.2 Tier 2 — Drift checks (audit-only)

Covered by the per-stage Step 1.6 in audit-mode discovering skills (Section 9.3). The audit coordinator surfaces drift findings here too, but they are produced per-stage during the audit loop, not as a top-level coherence pass.

### 10.3 Severity levels

| Level | Meaning | Default user action |
|---|---|---|
| **CRITICAL** | Something is structurally broken (an unresolvable path, missing evidence file). The artifact set is internally invalid. | Default: address now. User can override. |
| **WARNING** | Inconsistency that probably hurts (missing pointer, vocabulary gap). The artifact set works but seams are visible. | Default: acknowledge and commit. |
| **INFO** | Soft observation; nice to address but no harm in deferring. | Default: acknowledge and commit. |

### 10.4 Surface format

```
Coherence check complete. 3 findings (1 CRITICAL, 1 WARNING, 1 INFO).

[CRITICAL] memory file pointer
  CLAUDE.md → "[Design](docs/DESIGN.md)"
  docs/DESIGN.md doesn't exist
  Fix: re-run discovering-memory-file to update pointers, OR run
  discovering-design to create the missing artifact.

[WARNING] vocabulary gap
  DOMAIN.md uses term "PurchaseOrder" (3 occurrences)
  GLOSSARY.md doesn't define it
  Fix: run discovering-glossary in extend mode to add the definition.

[INFO] testing/architecture coverage
  ARCHITECTURE.md lists component "worker (services/jobs/)"
  TESTING.md doesn't mention worker testing
  Fix: run discovering-testing in extend mode to address.
```

Findings are surfaced verbatim, not summarized. Each includes: the inconsistency, the source citation, and the concrete fix.

### 10.5 User options after findings

```
How would you like to proceed?

  - Address findings now              ← Recommended if any CRITICAL
    (loops back into the relevant discovering-X skills, then re-runs
    coherence)

  - Acknowledge and commit as-is
    (proceed with current artifacts; findings are conversation-only)

  - Show details for one finding
    (pick one to expand)
```

"Address now" routes to the relevant discovering skills in extend mode, then re-runs coherence. Capped at 3 coherence loops to prevent a stubborn finding from trapping the user; after the third loop, the cap message offers (a) commit with remaining findings noted, (b) abort.

### 10.6 Why coherence is non-blocking

The user is the operator. CRITICAL findings get a strong default nudge (recommended option = address now), but the user can override — there are legitimate cases (e.g. the user just deleted DESIGN.md intentionally and will null out the config in a follow-up). Hard-blocking would be paternalistic and would also create a foot-gun: a bug in the coherence checker could permanently block bootstrap until patched.

## 11. Config and framework changes

### 11.1 Scaffold additions (`scaffolds/config.yml`)

Two additions.

**Testing artifact key in the `context:` block:**

```yaml
context:
  constitution_path: docs/constitution.md
  architecture_path: docs/ARCHITECTURE.md
  testing_path: docs/TESTING.md             # NEW
  glossary_path: docs/GLOSSARY.md
  domain_path: docs/DOMAIN.md
  design_path: docs/DESIGN.md
```

Slotted between architecture and glossary so the config layout mirrors the bootstrap stage order.

**Suggestion-pass default:**

```yaml
# ── Suggestion pass default ─────────────────────────────────
# How the bootstrap and audit coordinators handle the
# prescriptive diagnose pass per discovering-X skill.
suggest:
  # ask = coordinator asks once at bootstrap start
  # on  = always run diagnose; no question
  # off = never run diagnose
  default: ask
```

`default: ask` preserves current UX. Power users can set `suggest.default: on` in `.sublime-skills/config-local.yml` to skip the question on their machine.

### 11.2 Memory file — no new key

The existing `memory_file.path` and `memory_file.character_limit` are reused by `ss-bs-discovering-memory-file`. No `context.memory_file_path` is added; duplicate state would be a foot-gun. The discovering skill writes `memory_file.path` back to config on first creation.

### 11.3 Validator updates (`framework/validate-config.sh`)

1. Accept the new `context.testing_path` key (null or path-to-existing-file). The existing path-existence checks extend uniformly — no special-casing.
2. Accept the new `suggest.default` key with allowed values `ask`, `on`, `off`. Reject anything else.

### 11.4 Discovery script (`framework/discover-context.sh`)

Emit a `testing` key in the JSON output alongside the existing five. The bootstrap coordinator reads this on Step 1.

### 11.5 No changes needed elsewhere

`framework/state-schema.md`, `framework/get-config-value.sh`, and other framework helpers already handle arbitrary `context.<name>_path` keys generically. No edits required there.

## 12. Affected files inventory

**New files (skill SKILL.md authoring):**
- `skills/project-bootstrap/ss-bs-discovering-testing/SKILL.md`
- `skills/project-bootstrap/ss-bs-discovering-memory-file/SKILL.md`
- `skills/project-bootstrap/ss-bs-auditing-project/SKILL.md`

**Modified files:**
- `skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md` — add Step 2 (opt-in switch), expand todo list to 14 items, add Step 8 (coherence), add testing + memory-file stages to the per-file loop.
- `skills/project-bootstrap/ss-bs-discovering-constitution/SKILL.md` — add Step 1.5 (diagnose), Q1.5 in Step 3, suggestion-handling in Step 4/6, MODE=audit support, Step 1.6 (drift) for audit.
- `skills/project-bootstrap/ss-bs-discovering-architecture/SKILL.md` — same.
- `skills/project-bootstrap/ss-bs-discovering-glossary/SKILL.md` — same.
- `skills/project-bootstrap/ss-bs-discovering-domain-model/SKILL.md` — same.
- `skills/project-bootstrap/ss-bs-discovering-design/SKILL.md` — same.
- `skills/project-bootstrap/scaffolds/config.yml` — additions per Section 11.1.
- `skills/spec-driven-development/framework/validate-config.sh` — new key validation.
- `skills/spec-driven-development/framework/discover-context.sh` — emit `testing` key.

**Documentation updates:**
- `README.md` — entries for `ss-bs-discovering-testing`, `ss-bs-discovering-memory-file`, `ss-bs-auditing-project`.
- `docs/bootstrap.md` — narrative update for the 7-artifact pipeline and audit sibling.
- `docs/CONTEXT-FILES.md` — add TESTING.md and the agent memory file rows to the artifact inventory.

## 13. Trade-offs and rejected alternatives

### 13.1 Per-file opt-in vs single coordinator-level opt-in

**Considered:** asking the user per file whether suggestions should run for that file specifically.
**Rejected because:** 5+ extra decisions at the start of bootstrap is decision fatigue. A user's mood about "I want opinionated help" is consistent across the run. Single switch at the coordinator level is cleanest.

### 13.2 Always-on suggestion pass (no opt-out)

**Considered:** always run diagnose; cap tightly at 3 per skill; surface as a single multi-select per file.
**Rejected because:** users with simple or new projects often want bare-minimum descriptive bootstrap. The opt-out preserves their experience without adding cost.

### 13.3 Audit mode as a flag (`MODE=initial|audit`) on the existing skill

**Considered:** keeping one coordinator with a mode switch.
**Rejected because:** audit's flow differs meaningfully from bootstrap (coherence first, per-stage commits, prescriptive-by-default, no config-copy / dir-creation steps). Combining them into one skill would mean many `if audit` branches. A sibling skill is clearer.

### 13.4 Dedicated `ss-bs-auditing-X` skills per file

**Considered:** instead of `MODE=audit` on the existing discovering skills, write a parallel set of audit-specific discovery skills.
**Rejected because:** 90% of the work (silent scan, diagnose, Q&A shape, atomic write) is shared with existing modes. A `MODE=audit` value with one new substep (Step 1.6) and a reordered question flow is much less code than parallel skills.

### 13.5 Hard-blocking on CRITICAL coherence findings

**Considered:** refuse to commit if any CRITICAL is unresolved.
**Rejected because:** there are legitimate cases for a CRITICAL finding to be intentional (e.g. user just deleted a file and will null the config next). Hard-blocking is paternalistic and risks a coherence-checker bug trapping the user. Strong default nudge ("address now" recommended) achieves most of the safety with none of the foot-gun.

### 13.6 Persisting coherence and audit reports to disk

**Considered:** writing `docs/.audit-report-YYYY-MM-DD.md` after each audit run, and similarly for bootstrap coherence findings.
**Rejected because:** persistence creates lifecycle questions (when's it stale, who deletes, what's gitignored) for a report whose value is highest at the moment it surfaces. Conversation-only is simpler. Users can copy from the conversation if they want a record.

### 13.7 Maintaining multiple memory files in sync (CLAUDE.md + AGENTS.md + GEMINI.md)

**Considered:** bootstrap maintains all memory files that exist, keeping them content-equivalent.
**Rejected because:** cross-file sync is its own problem (concurrent edits, divergence, when does the bootstrap detect they're out of sync). Out of scope. Teams with multiple harnesses solve it themselves via symlink, sync script, or manual maintenance.

### 13.8 Codifying the testing split (constitution + memory) instead of a separate TESTING.md

**Considered:** instead of a new artifact, codify the existing split in the constitution and memory-file skills with explicit cross-references.
**Rejected because:** while cheaper, this leaves testing strategy fragmented across two files whose primary purposes are different. Projects with substantive test strategy end up squeezing it awkwardly. A dedicated TESTING.md gives test strategy a real home and the architecture pattern is already proven by the other discovering skills.

## 14. Open questions for the implementation phase

These do not block the design but should be resolved during plan-writing.

1. **Suggestion-pass evidence rules per skill.** Section 6.2 lists categories; the exact pattern-matching rules ("a god entity is N attributes, M relationships", "heavy mocking is >X%") need to be calibrated per skill. Start with conservative thresholds, tune based on use.
2. **Coherence-loop UX when a fix creates a new finding.** Bootstrap caps at 3 coherence loops. If the third loop produces a fresh CRITICAL (e.g. a fix introduced a new path that doesn't resolve), the message ("commit with remaining findings noted / abort") may need a third option. Defer to implementation.
3. **Audit on a partially-bootstrapped project.** Audit's preflight requires config + ≥1 artifact. What if the user has a config but every `context.*_path` is null? Probably redirect to bootstrap; confirm during implementation.
4. **New-project mode in `discovering-testing`.** Section 7.5 mentions a starter-strategy Q&A. The exact questions need defining; they should mirror the depth of the existing Step 3 questions.
5. **Provenance marker format.** Section 6.5 shows the marker as a sentence inside the `Evidence:` field. Different artifacts may need different syntactic homes (e.g. design tokens don't have an "Evidence" field). Resolve per-artifact during implementation.
6. **CHANGELOG / migration story.** This change is technically backward-compatible (existing projects work unchanged when `suggest.default: ask` is the default and they pick "descriptive only"), but the validator change rejects unknown keys. Need a "config-migration" step in the bootstrap re-run to add the new keys with safe defaults. Decide during implementation whether this happens automatically or via a user prompt.
