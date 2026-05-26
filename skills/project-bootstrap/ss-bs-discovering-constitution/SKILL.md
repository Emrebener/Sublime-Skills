---
name: ss-bs-discovering-constitution
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the constitution slot. Reads linters, CI configs, security files, and source patterns; then asks the user targeted questions to confirm principles, set MUST/SHOULD severity, and capture intent that the code can't reveal. Writes docs/CONSTITUTION.md (or the configured path) atomically.
---

# Discovering Constitution

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). Constitution principles are a mix of two things — codified rules already living in the project (linters, CI gates, security configs, source patterns) and intent the user holds in their head ("we never deploy on Fridays", "explicit failure beats silent fallbacks"). The code can show the first kind; only the user can confirm the second. So this skill stays in the coordinator's context and has a real conversation.

**Key principle:** Constitution principles must be either *observed* in the codebase OR *explicitly stated* by the user. If a principle can't be cited to one of those two sources, drop it. Don't propose universal truisms ("write good code"), don't pad to hit a quota.

**Announce at start:** "I'm using the ss-bs-discovering-constitution skill to build docs/CONSTITUTION.md with you."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for constitution. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, `replace`, or `audit`. Audit invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3.
- `EXISTING_CONTENT` — verbatim current `docs/CONSTITUTION.md` content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/CONSTITUTION.md`; honors `context.constitution_path` config override if non-default)
- **`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask. The user reads one thing, decides one thing, moves on.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text input is reserved for genuinely open prompts (project-specific intent principles, alias notes, etc.).
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax in the proposed constitution — text only.
- Do NOT dispatch subagents. You're inline — you do the work.
- Do NOT propose principles unsupported by codebase evidence OR explicit user input. Every principle traces to one or the other.
- Do NOT exceed 7 principles in the final draft — fewer load-bearing ones beat a long list.
- Do NOT include universal truisms ("write good code", "be consistent") — project-specific only.
- Do NOT overwrite an existing constitution in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT loop past 3 tweak iterations without surfacing bail options to the user.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT use severity MUST for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). This is documented in the Inputs section.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan                        │
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             then Q2-Q4)                             │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings + gaps + diagnoses    │
│   → Step 3: targeted questions on gaps + Q1.5       │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 1: silent code scan                        │
│   → Step 1.5: silent diagnose (always on for audit) │
│   → Step 1.6: drift check vs EXISTING_CONTENT       │
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3: Q0 (drift resolution) → Q1 → Q1.5 → ...│
│   → Step 4-6: as usual                              │
└─────────────────────────────────────────────────────┘
```

## Step 1: Code Scan (Silent — No User Narration Yet)

Read all of the following that exist. Don't narrate progress to the user — this happens silently in your head, then you announce findings once in Step 2.

### 1a. Broad project read

- `README.md` — project intro, often mentions conventions in passing
- `CONTRIBUTING.md` / `CONTRIBUTING.rst` — explicit contributor rules
- `CODE_OF_CONDUCT.md` — usually too generic to mine, but skim
- `SECURITY.md` — codified security policy
- `docs/` overview (skim `docs/README.md` or table of contents if present)

Note the project's stated values, target audience, and any "we do X this way" passages.

### 1b. Codified rules (linters / formatters / type checkers)

Read what's there:

- **JavaScript/TypeScript:** `.eslintrc*`, `eslint.config.*`, `tsconfig.json`, `.prettierrc*`, `biome.json`, `tslint.json`
- **Python:** `pyproject.toml` (ruff/black/mypy sections), `.flake8`, `mypy.ini`, `setup.cfg`, `pylintrc`
- **Rust:** `Cargo.toml` (lints section), `clippy.toml`, `rustfmt.toml`
- **Go:** `.golangci.yml`, `.golangci.toml`
- **Ruby:** `.rubocop.yml`
- **Java/Kotlin:** `checkstyle.xml`, `.editorconfig`, `detekt.yml`
- **Multi-language / generic:** `.editorconfig`, `.pre-commit-config.yaml`, `lefthook.yml`, `.husky/`

For each rule that's **strict** (errors, not warnings), consider whether it implies a principle. Examples:
- `no-any` in TS → "MUST avoid `any`; use explicit types or `unknown` with narrowing"
- `mypy strict` mode → "MUST type-annotate all public function signatures"
- `clippy::pedantic` → "SHOULD address all clippy::pedantic findings before merge"

### 1c. CI hard gates

Read CI configs:
- `.github/workflows/*.yml`
- `.gitlab-ci.yml`
- `.circleci/config.yml`
- `azure-pipelines.yml`
- `buildkite/*.yml`, `Jenkinsfile`, etc.

Look for required checks: tests must pass, coverage thresholds, security scans, license checks, build verification. Each "fail the build on X" is potentially a principle.

### 1d. Source code patterns

You don't need to read everything. Sample:

- Pick 3-5 source files from different parts of the tree (entry points, a service/module, a utility, a test)
- Look for: error handling style (exceptions vs Result types vs error returns), logging conventions (structured? plain?), dependency injection patterns, async patterns, naming conventions
- Look at how `tests/` is structured: are tests required for every change? Is there a TDD/BDD pattern visible (test files mirror source files, etc.)?

Patterns repeated across multiple files suggest a principle. Patterns inconsistent across files do NOT — those are gaps, not rules.

### 1e. Security-relevant files

Specifically check:
- `.env.example` / `.env.sample` — what secrets does the project handle?
- Authentication code (search for `jwt`, `oauth`, `session`, `password` in source)
- Input validation (search for `validate`, `sanitize`, schema-validation library imports)
- Any `SECURITY.md` directives

These often surface MUST-level principles around secrets handling and input validation.

### 1f. Mode-specific reads

- **`create` mode:** ignore `EXISTING_CONTENT` (it's empty). Build candidate principles from scratch.
- **`extend` mode:** read `EXISTING_CONTENT` carefully. Note which categories are already covered; your candidate principles should focus on gaps. If you find that an existing principle is contradicted by what the code does now, flag it as a "conflict to discuss with the user" — don't unilaterally overrule it.
- **`replace` mode:** ignore `EXISTING_CONTENT`. Build candidates as if no constitution existed.

### 1g. Compile candidate principles in memory

For each candidate principle, hold:
- The proposed statement (verb-first: "MUST avoid `any`")
- The severity guess (MUST / SHALL / SHOULD)
- The evidence (file path + what you saw)

Keep this list to ≤10 candidates internally — you'll trim to 7 with the user.

## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 1.6 (if audit) or Step 2.

Diagnose looks for principles that the project's evidence suggests *should* exist but currently don't. Every diagnose finding must cite specific file paths or counts.

### 1.5a. Constitution diagnose categories

Scan each category for candidates. One strong candidate per category is the target; the aggregate cap of 5 is enforced in 1.5b after dropping unsupported candidates.

- **Missing principle where the stack implies one.** Example: the project has Stripe + Sentry + Auth0 integrations but no codified input-validation discipline. Evidence: list the integrations + count of unvalidated handlers.
- **Weak severity that should be stronger.** A lint rule is set to `warn` rather than `error`, a coverage threshold is logged but not gating merge, or a security check exists but doesn't fail the build. Evidence: file path + the exact "weak" config value.
- **Contradictions between an existing stated principle and observed code.** (Extend mode only.) The existing constitution claims X but the code does not-X consistently. Evidence: principle quote + file paths showing not-X.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline
- `evidence`: file paths or counts
- `proposed_addition`: exact markdown text for a new Principle entry

Drop unsupported candidates. If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more paths/higher counts = stronger)
3. Impact (changes that prevent bugs > consistency improvements)

Surface the top 5. If 0 candidates remain, Q1.5 is skipped silently.

## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each entry in `EXISTING_CONTENT` against current code state. The goal is to detect principles that have gone stale.

### 1.6a. Drift categories for constitution

- **Evidence-file removed.** A principle's `**Evidence:**` field cites `<path>` (e.g. `.eslintrc.json`); that file no longer exists. Evidence: the principle title + the missing path.
- **Evidence-rule weakened or removed.** A principle cites a lint rule "no-any: error"; current `.eslintrc.json` shows `no-any: warn` or omits it. Evidence: the principle + the current rule state.
- **Code now contradicts a stated principle.** A MUST principle says "API handlers MUST validate via Zod"; current `src/api/*.ts` shows N handlers without Zod calls. Evidence: handler counts.
- **Provenance re-evaluation.** Each principle marked "Added via bootstrap suggestion pass (YYYY-MM-DD)" → has the underlying evidence (the unenforced pattern) been remedied?
  - If the original evidence pattern is STILL present, the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (the code has changed to match the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (evidence-file-removed / rule-weakened / code-contradicts-principle / aspiration-met / aspiration-still-pending), `entry` (the principle being challenged), `evidence` (file paths or counts showing the current code state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.

## Step 2: Announce Findings

One short message (3-6 sentences; 3-7 when SUGGEST=on extends with the diagnose-mention sentence). State what you scanned and the headline finding. Example:

> "Here's what I picked up from the codebase: TypeScript with `no-any` and `no-floating-promises` set to error in `.eslintrc.json`; a CI gate requiring 80% test coverage in `.github/workflows/test.yml`; `Result<T, E>` error returns used consistently across `src/lib/`; all API handlers validate via Zod. I have 6 candidate principles ready. I'll ask you a few targeted questions, then show you the draft."

If `create` mode and the scan found very little evidence:
> "I didn't find much codified — no linter config, no CI gates, sparse source patterns. We can still build a constitution from your stated intent, but it'll lean heavily on what you tell me. Want to continue, or skip?"

If `extend` mode:
> "Your existing constitution covers [N] principles: [brief list]. I scanned the codebase and found gaps around [areas]. I'll ask about those, then propose additions."

If `SUGGEST=on` AND Step 1.5 produced ≥1 candidate, extend the announcement with: "…and I noticed a few principles worth declaring even though they're not currently codified. I'll surface those after we confirm the observed ones."

If `MODE=audit`: "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X evidence-file removals, Y rule weaknesses, Z provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan and (for extend mode) the existing file already answered it.

### Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)

Ask one question per drift finding (do NOT bundle — drift items often have nuanced individual resolutions):

```
Question: "Drift detected: <principle summary>. Current code state: <evidence>. What's the right resolution?"

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

### Q1 — Confirm scanned candidate principles (multi-select)

```
Question: "Here are the candidate principles I picked up from the codebase. Which should land in the constitution?"

Multi-select. List your candidates with one-line rationale each. Always include
"All of the above" as the recommended option when ≤7 candidates exist.

Example option list:
- "MUST avoid `any` — from eslint no-any: error"
- "MUST return Result<T, E> from fallible library functions — observed across src/lib/"
- "MUST validate API inputs via Zod — observed in every src/api/ handler"
- "SHOULD maintain ≥80% test coverage — from CI gate"
- "SHALL pass `npm audit` with no high-severity findings — from CI security workflow"
- "MUST use 2-space indent, no semicolons — from prettier.config.js"
- "All of the above (Recommended)"
```

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some principles I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to include:"

Options (multi-select, one option per Step 1.5 candidate, plus a "None" escape):
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>
  - ... (one option per remaining candidate, up to 5)
  - "None of these — keep the constitution descriptive only"

Use the harness's multi-select question tool. Do not present as plain text.
```

Accepted suggestions are carried into Step 4 with provenance markers per Step 6's format. The provenance markers must appear in the Step 4 draft shown to the user, not added silently at Step 6 write time.

### Q2 — MUST vs. SHOULD ranking (per borderline principle)

Only ask for principles where the scan didn't make severity obvious (e.g., a lint rule set to `warn` rather than `error`, a coverage threshold listed but not gating merge, etc.). Skip entirely if all confirmed principles have clear severity from the scan.

```
Question: "How strong is the rule '<principle>'?"

Options:
  - "MUST — non-negotiable"
  - "SHALL — non-negotiable (formal phrasing)"
  - "SHOULD — strong default, exceptions allowed"
  - "Drop this principle"
```

### Q3 — Project-specific intent principles (free-form)

```
Question: "Are there any principles you'd add that aren't visible from the code?
Things like:
- 'Never deploy on Fridays'
- 'Keep PRs under 200 LOC'
- 'We prefer explicit failure over silent fallbacks'
- 'Documentation changes require a screenshot of the rendered output'

Free-form text. Skip if there are none."
```

Cap the final list at **7 principles**. If the user confirms more than 7, ask which to drop — don't unilaterally trim.

### Q4 (extend mode only) — Resolve conflicts

If Step 1f flagged any contradiction between existing principles and current code behavior, ask the user how to resolve each:

```
Question: "Your existing constitution says '<existing principle>', but the code currently does '<observed behavior>'. What's the right resolution?"

Options:
  - "The principle is right — the code is in violation"
  - "The code is right — update the principle"
  - "Drop the principle — it no longer applies"
  - "Keep both — they describe different cases (I'll clarify in the principle)"
```

## Step 4: Draft & Show to User

Synthesize the draft using:
- The confirmed candidates from Q1
- Accepted Q1.5 suggestions, rendered as additional Principle entries with provenance markers (format defined in Step 6's provenance subsection). **The provenance markers must appear in the draft shown to the user at this Step 4**, not added silently at Step 6 write time.
- Severity choices from Q2
- Free-form intent additions from Q3
- (For extend mode) Conflict resolutions from Q4
- Q0 drift resolutions (per drift item: update / keep / remove / clarify)
- Q0 provenance re-evaluations (per aspirational entry: promote / refresh / drop)

Cap the final principles list at 7 total. If observed + accepted suggestions exceed 7, ask the user which to drop.

Use the canonical template (see Output Template section). Show the full draft to the user, then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip this file"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture the user's free-form notes; apply them to the draft; re-show; re-ask Step 4. Cap at **3 iterations**. After 3:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip constitution for now, or
> (c) supply the file yourself — you write the markdown, I'll save it?"

**On Start over:** restart Step 3 from Q1 (the code-scan findings carry over; the user's answers are reset).

**On Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 6: Atomic Write & Report Outcome

```bash
cat > "$FILE_PATH.tmp" <<EOF
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **extend** mode: merge `EXISTING_CONTENT` + the new principles into a single document, then write atomically. Preserve the existing version number and adoption date unless the user changes them; bump the version per the amendment procedure (PATCH for clarification, MINOR for new principles, MAJOR for breaking changes).

Report to the coordinator one of:

- `created` (mode = create, full draft written)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a new Principle entry. Render the provenance inline within the Principle's `**Evidence:**` field:

```markdown
### Principle N — <Title>

**Severity:** <MUST | SHOULD>

**Statement:** <statement text>

**Evidence:** Not currently enforced — Added via bootstrap suggestion pass (YYYY-MM-DD). <evidence summary from the Q1.5 candidate>.

**Rationale:** <rationale text>
```

Replace `YYYY-MM-DD` with today's date. The audit skill reads this marker on re-runs to ask whether the principle is still aspirational or the code has caught up.

## Output Template

Canonical structure (omit empty sections — e.g., if no SHOULD principles exist, don't include a sub-heading for them):

```markdown
# Project Constitution

**Version:** 1.0.0
**Adopted:** <today's date, YYYY-MM-DD>

## Overview

A short paragraph describing the spirit of this document: these are the rules
every feature must comply with. Amendments require a version bump.

## Principles

### Principle 1 — <Name>

<MUST / SHALL / SHOULD statement.>

**Rationale:** <One line — why this is a rule for us. Cite evidence: file path
the principle came from, or "captured from project intent" for user-supplied
ones.>

### Principle 2 — <Name>

...

## Amendment Procedure

- PATCH: clarification, wording, typo (no semantic change)
- MINOR: new principle added or guidance materially expanded
- MAJOR: backward-incompatible removal or redefinition

Record version + date on every change.
```

**Principle drafting guidelines:**

- Lead with the verb / rule: "MUST validate inputs via schema layer" not "Input validation is important"
- Each principle cites concrete evidence in the rationale (file path + observation, or "captured from project intent" for user-supplied)
- 3-7 principles total — fewer is better. Aim for the load-bearing rules, not every nice-to-have.
- MUST / SHALL for non-negotiable; SHOULD for strong default with rare exceptions
- Each principle should be enforceable. "Write good code" is not enforceable. "MUST not use `any` in TypeScript source" is enforceable.

**Examples of good principles (illustrative — adapt to your findings):**

> ### Principle 1 — Strict typing
>
> All TypeScript source files MUST avoid `any`; use `unknown` with explicit narrowing where the type is genuinely unknown at compile time.
>
> **Rationale:** `.eslintrc.json` has `no-any: error`; relying on the linter alone has missed cases in `// eslint-disable-next-line` comments — promoting this to a principle makes the rule visible at review time.

> ### Principle 2 — Result-shaped error returns
>
> Library functions that can fail SHALL return `Result<T, E>` rather than throwing exceptions.
>
> **Rationale:** consistent across the codebase (src/lib/{auth,billing,queue}.ts); throwing in the same layer would be surprising for callers.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Asking the user to confirm principles the scan didn't find any evidence for | Skip evidence-free principles; ask Q3 only for intent the user wants to add |
| Bundling multiple questions in one ask | One question per turn |
| Proposing >7 principles | Trim with the user; never silently |
| Universal truisms ("write tests", "be consistent") | Project-specific only |
| Inventing principles to fill a 7-slot quota | If you only have evidence for 3, propose 3 |
| Mixing MUST and SHOULD ambiguously | MUST and SHALL are both non-negotiable; SHOULD = strong default with exceptions; pick one per principle |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Citing external authorities ("Google style guide says...") | Describe THIS project; lineage is irrelevant |
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize aspirational entries; without it, drift detection breaks |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off; do not run-but-suppress |
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |

## Red Flags

- About to ask the user a question without using the question tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to start writing the file before showing a draft → STOP; show first, write second
- About to dispatch a subagent → STOP; you're inline, you do the work
- About to propose a principle and you can't name what file/pattern or user statement made you think of it → STOP; trim it
- About to propose more than 7 principles in the final draft → STOP; ask the user which to drop
- About to copy boilerplate from a generic constitution template → STOP; this must be project-specific
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing constitution in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

Constitution principles are a 50/50 mix of code-derivable rules (linters, CI gates, source patterns) and user-held intent (deployment culture, error-handling philosophy, contributor norms). A subagent can extract the first half from one read pass and return — but the second half requires conversation, and a subagent that returns once can't have one. Routing the conversation through the coordinator (subagent returns findings → coordinator paraphrases to user → user replies → coordinator re-dispatches with notes) is wasteful: every paraphrase is a chance for the intent to drift, and re-dispatch with appended notes is a poor substitute for a real conversation.

So this skill stays inline. It scans the code itself, then talks to the user directly about the principles the code can't reveal. The four sibling skills (`ss-bs-discovering-architecture`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`) follow the same pattern for the same reason.
