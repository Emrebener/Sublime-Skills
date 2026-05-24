---
name: ss-bs-discovering-constitution
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the constitution slot. Reads linters, CI configs, security files, and source patterns; then asks the user targeted questions to confirm principles, set MUST/SHOULD severity, and capture intent that the code can't reveal. Writes docs/constitution.md (or the configured path) atomically.
---

# Discovering Constitution

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). Constitution principles are a mix of two things — codified rules already living in the project (linters, CI gates, security configs, source patterns) and intent the user holds in their head ("we never deploy on Fridays", "explicit failure beats silent fallbacks"). The code can show the first kind; only the user can confirm the second. So this skill stays in the coordinator's context and has a real conversation.

**Key principle:** Constitution principles must be either *observed* in the codebase OR *explicitly stated* by the user. If a principle can't be cited to one of those two sources, drop it. Don't propose universal truisms ("write good code"), don't pad to hit a quota.

**Announce at start:** "I'm using the ss-bs-discovering-constitution skill to build docs/constitution.md with you."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for constitution. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, or `replace`
- `EXISTING_CONTENT` — verbatim current `docs/constitution.md` content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/constitution.md`; honors `context.constitution_path` config override if non-default)

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

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan                        │
│   → Step 2: announce findings                       │
│   → Step 3: targeted questions                      │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 2: announce findings + gaps                │
│   → Step 3: targeted questions on gaps only         │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
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

## Step 2: Announce Findings

One short message (3-6 sentences). State what you scanned and the headline finding. Example:

> "Here's what I picked up from the codebase: TypeScript with `no-any` and `no-floating-promises` set to error in `.eslintrc.json`; a CI gate requiring 80% test coverage in `.github/workflows/test.yml`; `Result<T, E>` error returns used consistently across `src/lib/`; all API handlers validate via Zod. I have 6 candidate principles ready. I'll ask you a few targeted questions, then show you the draft."

If `create` mode and the scan found very little evidence:
> "I didn't find much codified — no linter config, no CI gates, sparse source patterns. We can still build a constitution from your stated intent, but it'll lean heavily on what you tell me. Want to continue, or skip?"

If `extend` mode:
> "Your existing constitution covers [N] principles: [brief list]. I scanned the codebase and found gaps around [areas]. I'll ask about those, then propose additions."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan and (for extend mode) the existing file already answered it.

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
- Severity choices from Q2
- Free-form intent additions from Q3
- (For extend mode) Conflict resolutions from Q4

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
| Mixing MUST and SHOULD ambiguously | MUST/SHALL = non-negotiable; SHOULD = strong default; pick one per principle |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Citing external authorities ("Google style guide says...") | Describe THIS project; lineage is irrelevant |

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
