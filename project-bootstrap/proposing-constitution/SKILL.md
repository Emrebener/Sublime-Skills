---
name: proposing-constitution
description: Use as a dispatched subagent to deeply analyze a project and propose a constitution (3-7 MUST/SHALL/SHOULD principles with rationales). Read-only. Returns findings + proposed markdown to the dispatching coordinator.
---

# Proposing Constitution

## Overview

You were dispatched by `bootstrapping-project` to analyze a project's codebase, conventions, and existing documentation, then propose content for `docs/constitution.md` — a list of 3-7 project-wide principles (MUST / SHALL / SHOULD rules) with one-line rationales each.

**Core principle:** Constitution principles must be *observed* in the codebase, not invented. If you can't point to evidence (a linter rule, a test pattern, a CI gate, a repeated convention in source), don't propose the principle.

**Operating mode:** STRICTLY READ-ONLY. You do NOT write files; you do NOT modify config; you do NOT interact with the user; you do NOT dispatch sub-subagents.

**Announce at start:** "I'm using the proposing-constitution skill to analyze this project."

## Hard Gates

- Do NOT write any file — return content to the controller; the controller writes
- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.
- Do NOT propose principles unsupported by codebase evidence — every principle cites what you observed
- Do NOT exceed 7 principles in your proposal — fewer is better; the goal is the load-bearing ones
- Do NOT include principles that are universal truisms ("write good code") — they have to be project-specific

## Inputs from the Dispatcher

The coordinator passes:
- `REPO_ROOT` — absolute path to the repository root
- `MODE` — one of `create`, `extend`, `replace`
- `EXISTING_CONTENT` — verbatim current content of `docs/constitution.md` (only when MODE is `extend` or `replace`; empty otherwise)
- `FILE_PATH` — where the file will be written (informational; you don't write it)

## Checklist

1. Read project context broadly (README, CONTRIBUTING, top-level configs)
2. Read linter / formatter / type-checker configs for codified rules
3. Read CI configs for hard gates
4. Sample source code for recurring patterns
5. Read security-relevant files for codified constraints
6. For `extend` mode: read EXISTING_CONTENT and note what's already covered
7. Synthesize findings (what you observed, grouped by category)
8. Draft the proposed content (or, for `extend`, the additions/refinements)
9. Return findings + proposed_content to the controller

## Step 1: Broad Project Read

Read these if they exist:

- `README.md` — project intro, often mentions conventions in passing
- `CONTRIBUTING.md` / `CONTRIBUTING.rst` — explicit contributor rules
- `CODE_OF_CONDUCT.md` — usually too generic to mine, but skim
- `SECURITY.md` — codified security policy
- `docs/` overview (skim `docs/README.md` or table of contents if present)
- Existing `docs/constitution.md` — for `extend`/`replace` modes (passed as EXISTING_CONTENT)

Note the project's stated values, target audience, and any "we do X this way" passages.

## Step 2: Codified Rules (Linters / Formatters / Type Checkers)

Read what's there:

- **JavaScript/TypeScript:** `.eslintrc*`, `eslint.config.*`, `tsconfig.json`, `.prettierrc*`, `biome.json`, `tslint.json`
- **Python:** `pyproject.toml` (ruff/black/mypy sections), `.flake8`, `mypy.ini`, `setup.cfg`, `pylintrc`
- **Rust:** `Cargo.toml` (lints section), `clippy.toml`, `rustfmt.toml`
- **Go:** `.golangci.yml`, `.golangci.toml`
- **Ruby:** `.rubocop.yml`
- **Java/Kotlin:** `checkstyle.xml`, `.editorconfig`, `detekt.yml`
- **Multi-language / generic:** `.editorconfig`, `.pre-commit-config.yaml`, `lefthook.yml`, `.husky/`

For each rule you find that's **strict** (errors, not warnings), consider whether it implies a principle. Examples:
- `no-any` in TS → "MUST avoid `any`; use explicit types or `unknown` with narrowing"
- `mypy strict` mode → "MUST type-annotate all public function signatures"
- `clippy::pedantic` → "SHOULD address all clippy::pedantic findings before merge"

## Step 3: CI Hard Gates

Read CI configs:
- `.github/workflows/*.yml`
- `.gitlab-ci.yml`
- `.circleci/config.yml`
- `azure-pipelines.yml`
- `buildkite/*.yml`, `Jenkinsfile`, etc.

Look for required checks: tests must pass, coverage thresholds, security scans, license checks, build verification. Each "fail the build on X" is potentially a principle.

## Step 4: Source Code Patterns

You don't need to read everything. Sample:

- Pick 3-5 source files from different parts of the tree (entry points, a service/module, a utility, a test)
- Look for: error handling style (exceptions vs Result types vs error returns), logging conventions (structured? plain?), dependency injection patterns, async patterns, naming conventions
- Look at how `tests/` is structured: are tests required for every change? Is there a TDD/BDD pattern visible (test files mirror source files, etc.)?

Patterns repeated across multiple files suggest a principle. Patterns inconsistent across files do NOT — those are gaps, not rules.

## Step 5: Security-Relevant Files

Specifically check:
- `.env.example` / `.env.sample` — what secrets does the project handle?
- Authentication code (search for `jwt`, `oauth`, `session`, `password` in source)
- Input validation (search for `validate`, `sanitize`, schema-validation library imports)
- Any `SECURITY.md` directives

These often surface MUST-level principles around secrets handling and input validation.

## Step 6: Mode Handling

**For `create` mode:** ignore EXISTING_CONTENT (it's empty). Build the proposal from scratch.

**For `extend` mode:** read EXISTING_CONTENT carefully. Your proposal should be **additions** that don't duplicate or contradict what's already there. If you find that an existing principle is wrong based on what the code actually does, note it in findings but don't unilaterally rewrite it — the user will decide.

**For `replace` mode:** ignore EXISTING_CONTENT. Build a fresh proposal as if no constitution existed.

## Step 7: Synthesize Findings

Structure findings by category. Keep it terse — bullets, not prose:

```
## Findings

### Linter / formatter
- `.eslintrc.json` has `no-any: error` and `no-floating-promises: error`
- `prettier.config.js` enforces 2-space indent, no semicolons

### CI gates
- `.github/workflows/test.yml` requires 80% coverage minimum
- `.github/workflows/security.yml` runs `npm audit` and fails on high-severity findings

### Source patterns
- All error handling uses `Result<T, E>` shape (saw in src/lib/auth.ts, src/lib/billing.ts, src/services/queue.ts)
- Tests live alongside source as `<file>.test.ts`
- Async code consistently uses async/await; no `.then()` chains seen

### Security
- `.env.example` lists STRIPE_SECRET_KEY, JWT_SECRET, DATABASE_URL — secret handling matters
- All input parsing goes through Zod schemas (saw in src/api/*.ts)

### Existing constitution (extend mode only)
- Covers 3 principles: testing required, conventional commits, semantic versioning
- Doesn't mention: error handling style, input validation, security posture
```

## Step 8: Draft Proposed Content

For `create` and `replace` modes, the full constitution template:

```markdown
# Project Constitution

**Version:** 1.0.0
**Adopted:** <leave for the controller to fill with today's date>

## Overview

A short paragraph describing the spirit of this document: these are the rules
every feature must comply with. Amendments require a version bump.

## Principles

### Principle 1 — <Name>

<MUST / SHALL / SHOULD statement.>

**Rationale:** <One line — why this is a rule for us.>

### Principle 2 — <Name>

...

## Amendment Procedure

- PATCH: clarification, wording, typo (no semantic change)
- MINOR: new principle added or guidance materially expanded
- MAJOR: backward-incompatible removal or redefinition

Record version + date on every change.
```

For `extend` mode, the proposed_content is just the new principles to insert under `## Principles` (not the whole file). Format them the same way; the controller will splice them in.

**Principle drafting guidelines:**

- Lead with the verb / rule: "MUST validate inputs via schema layer" not "Input validation is important"
- Each principle cites concrete evidence in the rationale (e.g., "Rationale: all source files already use Zod (src/api/*.ts); making this explicit prevents drift")
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

> ### Principle 3 — All inputs validated at the API boundary
>
> Every public API handler MUST validate its input through the Zod schema layer before any business logic runs.
>
> **Rationale:** observed in every route handler; an unvalidated handler would be a regression with security implications.

## Step 9: Return to the Controller

Output structure:

```
## Findings

<findings from Step 7>

## Proposed content

<for create/replace: the full constitution markdown>
<for extend: just the new principles to add>

## Notes for the controller

<anything the user should hear: caveats, low-confidence calls, places where
you couldn't gather enough evidence, suggested follow-ups>
```

That's your entire return value. The controller takes it from here.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Proposing principles not backed by codebase evidence | Every principle's rationale cites observed evidence (file paths, configs) |
| More than 7 principles | Trim — fewer load-bearing principles beat a long list of nice-to-haves |
| Universal truisms ("write tests", "be consistent") | Project-specific only; truisms add noise |
| Proposing extend additions that duplicate existing principles | Read EXISTING_CONTENT carefully; only propose net-new |
| Writing the file yourself | You return content; the controller writes |
| Inventing principles to fill a 7-slot quota | If you only have evidence for 3, propose 3 |
| Mixing MUST and SHOULD ambiguously | MUST/SHALL = non-negotiable; SHOULD = strong default; pick one per principle |

## Red Flags

- About to write a file → STOP; controller writes
- About to ask the user a question → STOP; controller handles user discussion
- About to dispatch a subagent → STOP; you are a leaf
- About to propose a principle and you can't name what file/pattern made you think of it → STOP; trim it
- About to propose more than 7 principles → STOP; reduce to load-bearing ones
- About to copy boilerplate from a generic constitution template → STOP; this must be project-specific
