---
name: writing-plans
description: Use during the plan-drafting stage of an SDD pipeline run, after the spec is committed and approved. Renders the approved spec into a detailed implementation plan.md with bite-sized TDD tasks organized by user story.
---

# Writing Plans

## Overview

Convert an approved spec into an implementation plan that a per-task implementer subagent can execute without re-deriving intent. Tasks are bite-sized (2-5 minutes each), strictly ordered, and organized by user story to enable MVP-first delivery.

**Core principle:** Every step contains the actual content the implementer needs — exact file paths, complete code, exact commands with expected output. No placeholders, no "similar to above," no "TODO".

**Announce at start:** "I'm using the writing-plans skill to render the implementation plan."

## Hard Gates

- Do NOT include placeholders ("TBD", "fill in", "add appropriate error handling", "write tests for the above")
- Do NOT use Mermaid, C4, PlantUML, ASCII art, or any other diagram syntax. The plan is prose + code + commands. The validator catches labeled diagram syntaxes (Mermaid/PlantUML/C4); ASCII art is on honor system — don't sneak it in.
- Do NOT reference functions, types, or methods you didn't define in this plan or that don't exist in the codebase
- Do NOT introduce new design decisions. If a gap appears, stop and surface it to the coordinator — return to spec stage.

## Checklist

1. Read the spec
2. Load project context (constitution, ADRs, architecture, glossary)
3. Write the plan header (title, feature ID, spec link, goal, architecture, tech stack) — see Plan Structure below
4. Map out the file structure (which files get created/modified, with one-line responsibility each)
5. Decompose into tasks grouped by user story, with `[T###]`, optional `[P]`, `[US#]`, file paths, and concrete TDD steps with code + commands + commits
6. Run the inline self-review; fix issues inline
7. Save to `docs/specs/NNN-<short-name>/plan.md`
8. Update state file
9. Report

## Step 1: Read the Spec

Read `docs/specs/NNN-<short-name>/spec.md` in full. Note:
- Story priorities (P1/P2/P3) — Phase order follows these
- FR-### and SC-### IDs — tasks will reference them via `**Requirements:** FR-..., SC-...`
- Key entities — they'll map to data-layer tasks
- Edge cases — they'll map to dedicated tests
- Constraints — they shape technology choices in the plan

## Step 2: Load Project Context

Run the discovery script (skip re-Reads if these files are already in your working context from an earlier stage) and **Read every file it returns a non-null path for** before decomposing into tasks:

```bash
./spec-driven-development/scripts/discover-context.sh
```

Required reads when present (skip files the JSON returns as `null`):

- `constitution` — tasks MUST comply; violations are flagged CRITICAL by reviewing-plans (Stage 9)
- All `adrs` — especially the newly accepted ones from Stage 6 — tasks must reflect the chosen approaches; silent contradiction is CRITICAL
- `architecture` — fit the plan into the existing structure; follow established file/module patterns
- `glossary` / `domain` — use canonical terms in task descriptions and code identifiers

Plans written without these reads typically fail review on constitution/ADR alignment, or surface as NEEDS_CONTEXT from the per-task implementers asking questions the convention files would have answered.

**Empty-context case:** if every context field in the JSON comes back `null` (greenfield project; no constitution, ADRs, architecture, or glossary), that's a valid state — proceed without them. Do not halt; do not ask the user to produce files. The plan can still be written; the auto-review just won't have alignment checks to run against.

## Step 3: Write the Plan Header

See the Plan Structure section below for the full header template. The header includes title, feature ID, spec link, status, goal, architecture (2-3 sentences referencing ADRs), and tech stack. This is the first content written to the file; later steps add file structure, then tasks.

## Step 4: Map Out File Structure

Before defining tasks, list every file that will be created or modified, with a one-line responsibility:

```markdown
## File Structure

**New:**
- `src/auth/jwt.ts` — issue & verify JWTs
- `src/auth/middleware.ts` — Express auth middleware
- `tests/auth/jwt.test.ts` — JWT unit tests
- `tests/auth/middleware.test.ts` — middleware unit tests

**Modified:**
- `src/server.ts` — wire in auth middleware
- `src/routes/users.ts` — protect endpoints

**Dependencies:**
- Add: `jsonwebtoken`, `@types/jsonwebtoken`
```

This locks in decomposition decisions. Each file should have one clear responsibility. Files that change together live together — split by responsibility, not by technical layer.

## Step 5: Decompose Into Tasks

Tasks are organized into phases:

- **Phase 1: Setup** — project initialization, dependency installs, config (no story label, no `[US#]`)
- **Phase 2: Foundational** — blocking prerequisites used by multiple stories (no story label)
- **Phase 3+: Per-Story Phases** — one phase per user story in priority order (P1 first), with `[US1]`, `[US2]`, etc.
- **Final Phase: Polish** — cross-cutting concerns, integration tests, docs (no story label)

Each story phase should be a complete, independently testable increment. Completing only Phase 3 (US1) must yield a working MVP.

### Task Header Format

```markdown
### Task T012 [P] [US1]: Implement JWT issue/verify

**Files:**
- Create: `src/auth/jwt.ts`
- Test: `tests/auth/jwt.test.ts`

**Requirements:** FR-002, FR-003
```

- `[P]` — parallel marker, only include when this task is parallelizable (different files from other [P] tasks in the same phase, no dependency on incomplete tasks)
- `[US#]` — story label, only for Phase 3+ story tasks
- `[NO-TDD]` — TDD opt-out marker. **Strict criteria — see [NO-TDD] Criteria section below.** A reviewer will flag misuse as CRITICAL. Include a one-line reason on the line immediately after the task header.

### TDD Steps (default)

Every task uses Red-Green-Refactor steps unless marked `[NO-TDD]`:

````markdown
- [ ] **Step 1: Write the failing test**

```ts
// tests/auth/jwt.test.ts
import { issueToken, verifyToken } from '../../src/auth/jwt';

test('issueToken produces a verifiable token', () => {
  const token = issueToken({ userId: 'u1' });
  const claims = verifyToken(token);
  expect(claims.userId).toBe('u1');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/auth/jwt.test.ts`
Expected: FAIL — "Cannot find module '../../src/auth/jwt'"

- [ ] **Step 3: Write minimal implementation**

```ts
// src/auth/jwt.ts
import jwt from 'jsonwebtoken';
const SECRET = process.env.JWT_SECRET || 'dev-secret';

export function issueToken(claims: object): string {
  return jwt.sign(claims, SECRET, { expiresIn: '24h' });
}

export function verifyToken(token: string): any {
  return jwt.verify(token, SECRET);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/auth/jwt.test.ts`
Expected: PASS — 1/1 tests passing

- [ ] **Step 5: Commit**

```bash
git add src/auth/jwt.ts tests/auth/jwt.test.ts
git commit -m "feat(auth): JWT issue/verify (T012)"
```
````

### [NO-TDD] Criteria (strict)

`[NO-TDD]` is allowed ONLY when the task falls entirely into one of these categories. The reason line must match one of these labels (verbatim or close):

| Allowed category | Examples |
|---|---|
| `docs-only` | README updates, CHANGELOG, ADR text fixes, code comments only |
| `config-only` | JSON/YAML/TOML/INI data changes without logic — e.g., bumping a timeout value, adding a feature flag entry |
| `asset-addition` | Images, fonts, static files, fixtures with no consuming code |
| `dependency-bump` | package.json / Cargo.toml / requirements.txt version bumps without API changes |
| `mechanical-rename` | File renames or moves with all callers updated mechanically; no behavior change |
| `lint-only` | Whitespace, import sorting, formatter-driven changes |

`[NO-TDD]` is NOT allowed for:
- **Any change to logic** in code files (.ts/.js/.py/.go/.rs/.java/.c/.cpp/etc.) that adds or modifies behavior
- **Bug fixes** — these always need a failing test first
- **Refactors** that change or could change behavior
- **Anything that could plausibly be verified by writing a test**
- **"Trivial" changes the writer thinks don't need a test** — that's exactly when bugs slip in

If you find yourself reaching for `[NO-TDD]` because the test would be "tedious", you're in TDD territory; write the test.

The reviewing-plans skill checks `[NO-TDD]` usage and flags violations as CRITICAL.

### Non-TDD Step Format (when `[NO-TDD]` applies)

```markdown
- [ ] **Step 1: <Action>**

<Show the exact change — code/config/command. Same precision standard as TDD steps.>

- [ ] **Step 2: Verify**

Run: <command>
Expected: <output or behavior>

- [ ] **Step 3: Commit**

git add ... ; git commit -m "..."
```

## Step 6: Self-Review

### 6a. Schema validation (automated)

Run the validator script:

```bash
./spec-driven-development/scripts/validate-plan.sh docs/specs/NNN-<short-name>/plan.md
```

If it fails (exit code 1): fix every CRITICAL issue, then re-run until PASS. Common failures: missing required sections, T### IDs not on task headers, `[NO-TDD]` markers without a reason on the next line, placeholders, forbidden diagram syntax.

### 6b. Read with fresh eyes (manual)

After the validator passes, read the plan with fresh eyes:

1. **Spec coverage** — every FR-### and every story has at least one task. List gaps; add tasks for any that are missing.
2. **Type consistency** — function/method/property names match across tasks. `clearLayers()` in T003 and `clearFullLayers()` in T007 = bug.
3. **File path consistency** — paths used in later tasks match what earlier tasks created
4. **Dependency order** — tasks reference only things that earlier tasks have produced
5. **[P] correctness** — parallel-marked tasks don't share files with other [P] tasks in the same phase
6. **Story independence** — each story phase, on its own, produces a working increment
7. **[NO-TDD] usage** — every `[NO-TDD]` marker has a reason matching one of the allowed categories

Fix issues inline. The dedicated `reviewing-plans` reviewer will pass over this next.

## Step 7: Save

Save to `docs/specs/NNN-<short-name>/plan.md`. Use the same `NNN-<short-name>` directory established by the spec.

**Write atomically.** Compose the full plan content, write to `<plan_path>.tmp`, then `mv <plan_path>.tmp <plan_path>`. The atomic move prevents a half-written plan.md if the session dies mid-write.

## Step 8: Update State File

Update `state.json` using the atomic pattern (write to `state.json.tmp`, then `mv state.json.tmp state.json`):

```json
{
  "plan_path": "docs/specs/NNN-<short-name>/plan.md",
  "current_stage": "plan_writing",
  "updated_at": "<ISO-8601 timestamp>"
}
```

Leave `current_stage` as `"plan_writing"` and DO NOT append `"plan_written"` to `stages_completed` here. The coordinator advances and marks completion after this skill returns.

## Step 9: Report

Return to the coordinator. The report **must include the validator's PASS line verbatim** — the coordinator uses this as proof that validation actually ran and succeeded.

```
Plan written: docs/specs/NNN-<short-name>/plan.md
Phases: <N>
Tasks: <N>
Spec coverage: <FRs covered / total>

Validator output (last line):
PASS — N warning(s), 0 critical issues
```

If you cannot produce a PASS line from the validator, do NOT claim the plan is written. Report the failure with the validator's full output and which CRITICAL issues you couldn't resolve.

The coordinator will re-run the validator before committing — a mismatch aborts the stage.

## Plan Structure

```markdown
# Plan: <Title>

**Feature ID:** NNN-<short-name>
**Spec:** [spec.md](./spec.md)
**Created:** YYYY-MM-DD
**Status:** Draft

## Goal

<One sentence — what this builds.>

## Architecture

<2-3 sentences on the approach. Reference ADRs that govern key choices.>

## Tech Stack

<Key technologies/libraries used, in bullet form.>

---

## File Structure

**New:**
- `path/to/file.ext` — one-line responsibility

**Modified:**
- `path/to/existing.ext` — what changes about it

**Dependencies:**
- Add/remove: <package names>

---

## Phases

### Phase 1 — Setup

(Tasks with no `[US#]` label. Project init, dep installs, config.)

### Phase 2 — Foundational

(Tasks blocking multiple stories. No `[US#]` label.)

### Phase 3 — <Story 1 title> (US1)

(Tasks tagged `[US1]`. Completing this phase alone yields a working MVP increment.)

### Phase 4 — <Story 2 title> (US2)

(Tasks tagged `[US2]`.)

### ...

### Final Phase — Polish

(Cross-cutting concerns, integration tests, docs. No `[US#]` label.)
```

**Required sections (in order):** Header (title, feature ID, spec link, created, status), Goal, Architecture, Tech Stack, File Structure, Phases (1, 2, 3+, Final Polish).

**Optional sections** (include only if applicable, append after Phases): Open Questions, Risk Notes, Dependencies & Sequencing (only if cross-task ordering needs explaining beyond what the phase structure already implies).

If a section doesn't apply, omit it entirely — don't leave "N/A" placeholders.

## Acceptable vs Forbidden Step Contents

| Acceptable | Forbidden |
|---|---|
| Complete code block for the file or change being made | Code stub with `// implementation here` |
| Exact `pytest tests/x.py::test_y -v` command with expected output | "Run the tests" |
| `git add a.py b.py && git commit -m "..."` with the actual message | "Commit your changes" |
| "Reference: FR-005, FR-006" | "See spec" |
| Type signatures and imports | "Use the right types" |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Vague steps ("add error handling") | Show the exact error-handling code |
| "Similar to Task 3" without repeating the content | Repeat the code; implementers may read tasks out of order |
| Tasks that span multiple files when they should be split | One file's worth of change per task is the right granularity in most cases |
| Phase 3 (US1) doesn't produce a working increment | Re-decompose — MVP-first means Story 1 must stand alone |
| `[P]` on tasks that actually touch the same file | Drop `[P]` and sequence them |
| Forgetting `**Requirements:**` on tasks | Add traceability — reviewers and the coordinator both use it |

## Red Flags

- About to write tasks without having Read constitution + ADRs (when present) → STOP; reviewing-plans (Stage 9) checks task alignment with these and flags violations CRITICAL
- About to write a task that contradicts a newly-accepted ADR from Stage 6 → STOP; re-Read the ADRs and revise the task
- Plan is longer than ~1500 lines → likely too big; check if the spec needed decomposition
- Found a real spec gap → stop, return to coordinator, do not patch with assumptions
- Task is hard to write because the implementation is genuinely unclear → that's a sign the spec is underspecified; flag it to the coordinator rather than guessing
- Tempted to add a Mermaid diagram for the architecture → no; describe in prose, link to the relevant ADR
