---
name: ss-bs-discovering-testing
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the testing slot. Scans test directories, runner configs, CI test commands, coverage tooling, naming patterns, mocking frameworks, and fixture patterns; then asks the user to confirm the setup, supply missing intent (canonical commands, mocking philosophy, fixture location), and — when SUGGEST=on — review testing-strategy improvements the code suggests but doesn't yet codify. Writes docs/TESTING.md (or the configured path) atomically. For new/pre-test projects, switches to a starter-strategy Q&A instead of a scan-and-confirm flow.
---

# Discovering Testing Conventions

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). Testing conventions come from two places — the code (what frameworks, commands, and patterns are already in use) and the user's head (what mocking philosophy is *intended*, whether coverage is aspirational or enforced, which test categories will be added). A subagent could extract the first half from one read pass but couldn't have the back-and-forth needed for the second. So this skill stays in the coordinator's context.

**Core principle:** Document the *intended* test strategy, not just what the code currently does. The scan reveals what's there; the questions surface what's meant and what's missing.

**Announce at start:** "I'm using the ss-bs-discovering-testing skill to draft your project's test strategy at docs/TESTING.md."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for testing.

## Inputs

The coordinator passes:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, `replace`, or `audit`. Audit invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3.
- `EXISTING_CONTENT` — verbatim current `docs/TESTING.md` content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/TESTING.md`; honors `context.testing_path` config override if non-default)
- **`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text only for genuinely open prompts (command overrides, fixture paths).
- Do NOT skip Step 1's silent scan even if you "already know" what the project uses. The scan grounds Step 2's announcement and Step 3's questions.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read. If you need more reads, surface fewer suggestions instead of widening the budget.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT run Step 1.5 when `SUGGEST=off`; skip it entirely — do not run-but-suppress.
- Do NOT run Step 1.5 when `new_project_mode = true`; use Step 3.NP instead.
- Do NOT write the artifact until the user has approved the draft (or accepted it as-is after the 3-iteration tweak cap).
- Do NOT overwrite an existing TESTING.md in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT loop past 3 tweak iterations without surfacing bail options to the user.
- Do NOT use severity MUST for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). This is documented in the Inputs section.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (test dirs, runner,    │
│             CI commands, coverage, mocking, fixtures)│
│   → Step 1.5: silent diagnose (if SUGGEST=on        │
│             AND not new-project mode)               │
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             Q2 commands, Q3 mocking, Q4 fixtures)   │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1 + Step 1.5 + read EXISTING_CONTENT       │
│   → Step 2: announce findings + gaps + diagnoses    │
│   → Step 3: questions on gaps + Q1.5 + Q5 conflicts │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 1: silent code scan                        │
│   → Step 1.5: silent diagnose (always on for audit) │
│   → Step 1.6: drift check vs EXISTING_CONTENT       │
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3: Q0 (drift resolution) → Q1 → Q1.5 → …  │
│   → Step 4-6: as usual                              │
├─────────────────────────────────────────────────────┤
│ NEW-PROJECT MODE (scan found <2 tests total)        │
│   → Skip Step 1.5 (no code to diagnose against)     │
│   → Step 2: announce "no tests yet"                 │
│   → Step 3.NP: starter-strategy Q&A (5 NP-Qs)       │
│   → Step 4-6: synthesize starter TESTING.md         │
└─────────────────────────────────────────────────────┘
```

## Step 1: Code Scan (Silent — No User Narration Yet)

Read all of the following that exist. Don't narrate progress to the user — this happens silently, then you announce findings once in Step 2.

### 1a. Test directories

Look for: `tests/`, `test/`, `__tests__/`, `spec/`, `e2e/`, `integration/`. For Go projects, note `*_test.go` files at any level. List each directory or pattern found with an approximate file count.

### 1b. Test runner config

Read whichever exist:

- **JavaScript/TypeScript:** `jest.config.*`, `vitest.config.*`, `playwright.config.*`, `karma.conf.*`, `.mocharc.*`
- **Python:** `pytest.ini`, `pyproject.toml` (`[tool.pytest.ini_options]`), `setup.cfg` (`[tool:pytest]`), `conftest.py`
- **Ruby:** `.rspec`, `spec/spec_helper.rb`
- **Go:** test-related dependencies in `go.mod` (testify, gomock)
- **Rust:** dev-dependencies in `Cargo.toml` (test libs, nextest config)
- **JVM:** `build.gradle` test configuration, `pom.xml` surefire/failsafe plugin config

Extract: framework name, config file path, parallelism settings if specified.

### 1c. Test naming patterns

Sample 5–10 test files from one test directory. Note the naming convention: `*.test.ts` vs `*.spec.ts`, `test_*.py` vs `*_test.py`, `*Spec.kt` vs `*Test.kt`. If both patterns exist in the same project, flag it — this is a naming inconsistency.

### 1d. CI test commands

Read CI workflow files: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`, `Jenkinsfile`, `buildkite/*.yml`. Extract: the command(s) invoked to run tests, any parallel sharding setup, OS or language-version matrix.

### 1e. Coverage tooling

Look for: `c8`, `nyc`, `istanbul` in JS; `coverage.py`, `pytest-cov` in Python; `simplecov` in Ruby; `tarpaulin` or `cargo-llvm-cov` in Rust in dependency files and config files (`.nycrc`, `.coveragerc`, `simplecov.rb`, etc.).

### 1f. Coverage thresholds

Look in coverage tool config files (e.g., `.nycrc` `statements` field, `[tool.coverage.report]` `fail_under`), and in CI workflow files for flags like `--lines 80` or a dedicated coverage-gate job. Note whether the threshold is **enforced** (fails the build) or **informational** (warning only).

### 1g. Mocking framework signal

Grep for imports or usages of common mocking tools:

- **JS/TS:** `jest.mock`, `vi.mock`, `sinon`, `nock`
- **Python:** `unittest.mock`, `pytest-mock`, `responses`, `vcrpy`
- **Go:** `gomock`, `testify/mock`
- **Rust:** `mockall`
- **JVM:** `mockito`, `WireMock`

Note the dominant style: heavy-mocking (module-level mocks at top of every test file), targeted-mocking (stubs in per-test setup), or no-mocking (real DB / containers / in-process fakes only).

### 1h. Fixture / factory patterns

Look for: `factories/`, `fixtures/` directories; `factory_bot` (Ruby), `factoryboy`/`factory_boy` (Python), `faker` (any), `fishery` (JS), `cypress/fixtures/`. Sample one factory file to understand the pattern (factory functions, static JSON files, library-based classes).

### 1i. Test categorization

Note structural signals: `unit/` vs `integration/` vs `e2e/` subdirectories inside the test root, or tag/marker conventions (`@pytest.mark.integration`, `describe.skip(...)`, `if (process.env.E2E)`, build tags in Go).

### 1j. Mode-specific reads

- **`create` / `replace`:** ignore `EXISTING_CONTENT`. Build candidates from scratch.
- **`extend`:** read `EXISTING_CONTENT`. Identify which sections of the canonical Output Template are missing, outdated, or incomplete. Note any conflicts between the existing doc and the current code (e.g., file says "Jest" but config shows Vitest).
- **`audit`:** read `EXISTING_CONTENT`. Then proceed to Step 1.6 for drift checks.

### 1k. Compile candidate sections in memory

Hold:
- Test categories observed, each with a one-line description and command hint
- Runner + framework name + config path
- Coverage tooling + current threshold + gating status (enforced / informational / absent)
- Mocking style (one of: heavy / targeted / no-mocking) plus a one-paragraph rationale based on what you saw
- Fixture/factory location + pattern name
- Naming convention(s) (and flag if inconsistent)

**If the scan found fewer than 2 test files total, set `new_project_mode = true`.** This disables Step 1.5 and routes Step 3 to the NP starter Q&A.

## Step 1.5: Silent Diagnose (only if `SUGGEST=on` AND `new_project_mode = false`)

If `SUGGEST=off` OR `new_project_mode = true`, skip this step entirely and proceed to Step 2.

Diagnose looks for testing-strategy gaps and smells. Every diagnose finding must be **evidence-cited** with specific file paths or concrete counts. Abstract "you should do X" findings are not allowed.

### 1.5a. Testing diagnose categories

For each category below, scan additional files if needed (within the budget — see Hard Gates). Scan each category for candidates. One strong candidate per category is the target; the aggregate cap of 5 is enforced in 1.5b after dropping unsupported candidates.

- **Missing test categories.** Only unit tests exist; no integration coverage of the API layer, repository layer, or service layer. Evidence: list the existing categories found in 1i, and which architectural components (from `docs/ARCHITECTURE.md` if it exists) are uncovered.
- **Large untested critical files.** Source files in `src/` (or equivalent) over 200 lines with no matching test file. Evidence: 3–5 specific file paths with approximate line counts.
- **Heavy mocking smell.** DB or other core dependency mocked in more than 80% of tests in a project where running a real DB is feasible. Evidence: mock-usage count + total test count (or file paths showing the pattern).
- **CI gate gap.** Tests run in CI but no coverage gate exists, OR a coverage gate exists as `warn`/informational rather than fail. Evidence: the CI file path + the relevant config block (or its absence).
- **Naming inconsistency.** Both `*.test.ts` and `*.spec.ts` (or an equivalent split) used in the same project. Evidence: counts of each pattern found in 1c.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar (typically SHOULD for testing; MUST only when a known-broken or known-flaky case exists; INFO for nice-to-haves)
- `title`: one-line headline (e.g., "Add integration test coverage for API layer")
- `evidence`: specific file paths or counts
- `proposed_addition`: exact markdown text to add to the relevant TESTING.md section

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence (no MUST without observable harm).

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more file paths / higher counts = stronger)
3. Impact (changes that prevent bugs > changes that improve consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3 is skipped silently.

## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each entry in `EXISTING_CONTENT` against current code state. The goal is to detect entries that have gone stale.

### 1.6a. Drift categories for testing

- **Runner / framework drift.** Doc says "Jest"; current `package.json` shows "Vitest". Evidence: dep diff.
- **Command drift.** Doc's "Run all: pnpm test"; current CI uses `pnpm test:ci`. Evidence: CI file path.
- **Coverage threshold drift.** Doc says "80% gate in CI"; current CI shows 60% or no gate. Evidence: CI file path.
- **Mocking philosophy drift.** Doc says "Mock externals only"; current tests show heavy DB mocking. Evidence: mock-usage count.
- **Category coverage drift.** Doc lists "unit + integration + e2e"; current repo has no `e2e/` directory. Evidence: directory listing.
- **Provenance re-evaluation.** Each suggestion-added category / coverage target / philosophy — has reality caught up? For each section carrying an "Added via bootstrap suggestion pass (YYYY-MM-DD)" marker, check whether the underlying evidence is still present:
  - If the original evidence pattern is STILL present, the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (the code has changed to match the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (runner-change / command-change / threshold-change / philosophy-change / category-added / category-removed / aspiration-met / aspiration-still-pending), `entry` (the doc text being challenged), `evidence` (file paths or counts showing the current code state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.

## Step 2: Announce Findings

One short message (3–6 sentences; 3–7 when `SUGGEST=on` extends with the diagnose-mention sentence). State what you scanned and the headline finding.

**Normal mode example:**
> "Here's what I picked up from the codebase: Vitest as the runner (`vitest.config.ts`), tests under `tests/{unit,integration}/`, naming `*.test.ts`, coverage via v8 (`c8`) with threshold gate at 80% in CI. Mocking is targeted via `vi.mock` (used in 14 of 87 tests). Fixtures live in `tests/fixtures/` as plain JSON. I'll ask a few targeted questions, then show you a draft."

**With `SUGGEST=on` and diagnose hits:**
> "…and I noticed a few testing-strategy gaps worth considering — I'll surface those after we confirm the observed setup."

**`extend` mode:**
> "Your existing TESTING.md covers [sections]. I scanned the codebase and found [gaps / conflicts]. I'll ask about those, then propose additions."

**`audit` mode:**
> "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X runner/command/threshold changes, Y category changes, Z provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual."

**New-project mode (`new_project_mode = true`):**
> "I didn't find a test suite — looks like this is a new or pre-test project. I can still draft a starter TESTING.md, but I'll need to ask you a few decisions about the strategy you want to set rather than scan for it. Want to continue?"

Wait for confirmation before proceeding to Step 3.NP.

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan already answered it definitively.

### Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)

Ask one question per drift finding (do NOT bundle — drift items often have nuanced individual resolutions):

```
Question: "Drift detected: <entry summary>. Current code state: <evidence>. What's the right resolution?"

Options:
  - "Update the doc to match code"
  - "Keep the doc — code is wrong / will be fixed"
  - "Remove the entry — no longer applies"
  - "Both — clarify scope (split into multiple entries)"
```

For **provenance re-evaluation** findings, the question is different:

```
Question: "Aspirational entry '<title>' was added on <date>. Evidence at that time: <original evidence>. Current code state: <current evidence>. Has this aspiration been realized?"

Options:
  - "Yes — code has caught up. Remove the provenance marker (promote to normal)."
  - "No — code still has the original problem. Keep as aspirational; refresh the marker date."
  - "Drop the entry — we've decided not to pursue this aspiration."
```

Record each resolution. Apply during Step 4 (Draft Synthesis).

### Q1 — Confirm observed test setup (multi-select)

```
Question: "Here's the testing setup I observed. Which should land in
TESTING.md as-is?"

Multi-select. List the scan candidates one-line each:
  - [observed] Test categories: unit, integration (+ paths)
  - [observed] Runner: Vitest (vitest.config.ts)
  - [observed] Coverage: v8 with 80% gate in CI
  - [observed] Mocking: targeted via vi.mock (14 of 87 tests)
  - [observed] Fixtures: tests/fixtures/ JSON files
  - [observed] Naming: *.test.ts
  - "All of the above (Recommended)"
```

Adapt the list to actual scan findings. Only present candidates the scan found evidence for.

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some things I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to
include:"

Options (multi-select, one option per Step 1.5 candidate, plus a "None" escape):
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>
  - ... (one option per remaining candidate, up to 5)
  - "None of these — keep TESTING.md descriptive only"

Use the harness's multi-select question tool. Do not present as plain text.
```

If the user picks none, treat as "no suggestions accepted" and proceed to Q2. Accepted suggestions are carried into Step 4 and rendered with provenance markers.

### Q2 — Canonical test commands (multi-select from CI extraction)

```
Question: "From CI, I extracted these test commands. Which should be
documented as canonical in TESTING.md?"

Multi-select with at least:
  - "Run all: <CI's primary test command>"
  - "Run filtered: <CI's pattern-filtered variant, if any>"
  - "Run with coverage: <CI's coverage variant, if any>"
  - "I'll specify (free-form)"
```

If CI extraction found no commands, ask the user to supply them free-form.

### Q3 — Mocking philosophy (single-select)

```
Question: "How does this project approach mocking? (One sentence summary
will land in TESTING.md.)"

Single-select:
  - "Mock as little as possible — real DB, real network (via VCR/wiremock),
    in-process fakes only for time/randomness"
    (Recommended for backend services with substantial integration coverage)
  - "Mock externals only — HTTP, queues, third-party SDKs. Real DB.
    Real internal modules."
  - "Mock liberally — fast unit tests over isolated functions; separate
    integration suite covers the wiring"
  - "Free-form (I'll describe)"
```

### Q4 — Fixture / factory location (free-form, scan default)

```
Question: "Where do test fixtures and factories live?"

Free-form text, pre-filled with the scan's finding (e.g., "tests/fixtures/").
Edit if different, or skip if the scan captured it correctly.
```

### Q5 — (extend mode only) Resolve conflicts

For each conflict between `EXISTING_CONTENT` and the current scan (e.g., file says "Jest" but config shows Vitest):

```
Question: "Your existing TESTING.md says '<X>', but the code shows '<Y>'.
What's right?"

Options:
  - "The doc is right — the code changed but the doc is correct intent"
  - "The code is right — update the doc"
  - "Both — they describe different cases; I'll clarify"
```

### Step 3.NP — New-Project Starter Q&A (only if `new_project_mode = true`)

Skip Q1, Q1.5, and Q5. Ask the following questions (one per turn), using the harness's multi-select / multi-choice question tool for each:

```
NP-Q1: "Which test categories will this project have?"
  Multi-select:
    - unit
    - integration
    - e2e (end-to-end)
    - property-based
    - load / performance
  Recommended: unit + integration for backend services;
               unit + e2e for frontend.

NP-Q2: "Which test runner / framework?"
  Multi-choice (options from the project's detected language stack):
    JS/TS:  Vitest (Recommended) / Jest / Mocha / Playwright (for e2e)
    Python: pytest (Recommended) / unittest
    Go:     standard library testing (Recommended) / Ginkgo
    Rust:   cargo test (Recommended) / nextest
    JVM:    JUnit 5 (Recommended) / TestNG / Spock

NP-Q3: "Coverage target?"
  Multi-choice: none / 60% / 70% / 80% (Recommended) / 90% / I'll set later

NP-Q4: "Mocking philosophy?" (same options as Q3 above)

NP-Q5: "Fixture / factory pattern?"
  Multi-choice:
    - Factory functions (Recommended for most stacks)
    - Static fixture files (JSON/YAML)
    - Library-based (factory_bot, factoryboy, fishery)
```

Skip a NP-Q only if the answer is already unambiguous from the project's existing language/framework choice.

## Step 4: Draft & Show to User

Synthesize the draft using:
- Q1 confirmations (observed setup)
- Accepted Q1.5 suggestions, rendered with provenance markers — **the markers must appear in the draft shown to the user at this Step 4**, not added silently at Step 6 write time; the user reviews and approves the full content including provenance
- Q2 canonical commands
- Q3 mocking philosophy paragraph
- Q4 fixture location
- (extend mode) Q5 conflict resolutions
- (new-project mode) NP-Q1 through NP-Q5 answers
- (audit mode) Q0 drift resolutions (per drift item: update / keep / remove / clarify)
- (audit mode) Q0 provenance re-evaluations (per aspirational entry: promote / refresh / drop)

Use the Output Template below. Show the full draft, then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip TESTING.md"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture the user's free-form notes; apply; re-show; re-ask Step 4. Cap at **3 iterations**:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip TESTING.md for now, or
> (c) supply the file yourself — you write the markdown, I'll save it?"

**On Start over:** restart Step 3 from Q1 (scan findings carry over; user answers reset).

**On Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 6: Atomic Write & Report Outcome

```bash
cat > "$FILE_PATH.tmp" <<'EOF'
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **extend** mode: merge `EXISTING_CONTENT` + new sections / refinements into a single document, then write atomically. Preserve existing accurate sections; replace or add only what changed.

Report to the coordinator one of:

- `created` (mode = create, full draft written — or "created via new-project starter" when new-project mode)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a new entry in the relevant TESTING.md section (a new test category, a stricter coverage target, a stricter mocking rule, etc.). Append a provenance line at the end of the section using three blockquote lines with self-contained italic spans:

```markdown
> _Added via bootstrap suggestion pass (YYYY-MM-DD)._
> _Evidence: <evidence summary from the Q1.5 candidate>._
> _Not currently enforced — declared here as an aspirational test-strategy improvement._
```

Replace `YYYY-MM-DD` with today's date. The three blockquote lines each carry a self-contained italic span (italic spans never cross blockquote line boundaries). The audit skill reads this marker on re-runs to ask whether the aspiration has been realized in code.

## Output Template

```markdown
# Testing

## Test categories

- **Unit** — `<command>` — `<path pattern>`
- **Integration** — `<command>` — `<path pattern>`
- (additional categories as observed/chosen)

## Runner & framework

- **Framework:** <name + version if known>
- **Config:** `<path>`
- **Run all:** `<command>`
- **Run filtered:** `<command pattern>`
- **Run with coverage:** `<command>`

## Coverage

- **Tool:** <name>
- **Current:** <% or "not measured"> (as of YYYY-MM-DD)
- **Target:** <%>
- **CI gate:** <yes — fails build at <threshold>% / no — informational only / not configured>

## Mocking philosophy

<One-paragraph rule from Q3 or NP-Q4. State the intent, not just the current state.>

## Fixtures & factories

- **Location:** `<path>`
- **Pattern:** <factory function | static fixture file | library-based (name)>

## Conventions

- **File naming:** `<pattern>` (e.g., `*.test.ts` alongside source)
- **One assertion per test / multiple OK:** <pick one>
- **Setup / teardown:** <pattern if notable>
- (additional conventions as observed or supplied by user)
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize aspirational entries; without it, drift detection breaks |
| Running Step 1.5 when `SUGGEST=off` | Skip Step 1.5 entirely when off; do not run-but-suppress |
| Running Step 1.5 in new-project mode | Skip diagnose when scan found <2 tests; use NP-Q&A instead |
| Skipping the mocking-philosophy question because "the scan tells me" | The scan reveals what's current; Q3 asks what's *intended*. Ask. |
| Writing run commands not present in CI | Q2 multi-selects from CI extraction; don't invent. If CI commands look wrong, ask the user. |
| Bundling multiple questions in one ask | One question per turn |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |

## Red Flags

- About to skip the silent scan because "I know this project uses Jest" → STOP; the scan grounds Step 2's claims
- About to run Step 1.5 when `SUGGEST=off` → STOP; skip entirely
- About to run Step 1.5 when `new_project_mode = true` → STOP; use Step 3.NP
- About to write the file before user approval → STOP; Step 4 approval is mandatory
- About to ask the user a question without using the harness's interactive tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing TESTING.md in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

Testing conventions have a code half (what frameworks, commands, and patterns are present) and a user half (what mocking philosophy is *intended*, whether coverage targets are aspirational or enforced, which test categories will be added for a new project). A subagent could extract the first half from one read pass but couldn't have the back-and-forth needed for the second. For new-project mode, the conversation is entirely about intent — nothing to scan, everything to decide. Routing that through a coordinator (subagent returns findings → coordinator paraphrases → user replies → coordinator re-dispatches) wastes turns and risks losing nuance.

So this skill stays inline. It scans the code itself, then asks the user about the things only they know. The six sibling skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`, `ss-bs-discovering-memory-file`) follow the same pattern for the same reason.
