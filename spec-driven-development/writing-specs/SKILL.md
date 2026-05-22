---
name: writing-specs
description: Use during the spec-drafting stage of an SDD pipeline run, immediately after discovering-requirements has produced a shared understanding. Renders that understanding into a formal spec.md artifact at docs/specs/NNN-short-name/spec.md.
---

# Writing Specs

## Overview

Render the agreed understanding from the discovery stage into a structured spec document. No user interaction in this stage — discovery already happened. The coordinator already holds the agreed content; this skill is about how to lay it out on disk.

**Core principle:** The spec is a contract. It should be specific enough that a competent engineer (or a fresh subagent) can implement it without re-deriving intent from a chat log.

**Announce at start:** "I'm using the writing-specs skill to render the spec document."

## Hard Gates

- Do NOT introduce new design decisions in this stage. If you find a gap, stop and return to discovery — don't paper over with assumptions.
- Do NOT include implementation steps, code snippets, file paths to be created, or task lists. Those live in the plan.
- Do NOT use Mermaid, C4, PlantUML, ASCII art, or any other diagram syntax. The spec is prose. If you find yourself wanting a diagram, describe the structure in words or split the description into smaller pieces. The validator catches labeled diagram syntaxes (Mermaid/PlantUML/C4); ASCII art is on honor system — don't sneak it in.

## Checklist

1. Resolve the feature directory and short name
2. Load project context (skip in writers if the coordinator already loaded it — coordinate)
3. Write `spec.md` using the required structure (Spec Structure section below)
4. Initialize/update the SDD state file
5. Run the inline self-review (Self-Review section below); fix issues inline
6. Report the spec path

## Step 1: Resolve Feature Directory

Default storage layout (overridable via `.sublime-skills/config.yml` → `paths.spec_dir`):

```
docs/specs/NNN-<short-name>/
  spec.md           # this stage writes
  state.json        # SDD state file (this stage initializes)
```

**Numbering:**
- `NNN` is sequential, three digits, zero-padded
- Scan existing directories under `docs/specs/` for the highest used number; new feature is highest+1
- If no specs exist yet, start at `001`

**Short name:**
- 2-4 kebab-case words from the feature description
- Examples: `user-auth`, `add-export-csv`, `fix-payment-timeout`

**If config overrides paths**: use those. Resolve sequential numbering against the configured `spec_dir`.

## Step 2: Load Project Context

If discovery (Stage 1) already Read these files in this session, you can skip re-Reading — but you MUST still have constitution + ADRs + glossary contents in your working context before writing the spec.

Otherwise, run the discovery script and **Read every file it returns a non-null path for** before composing the spec:

```bash
./spec-driven-development/scripts/discover-context.sh
```

Required reads when present (skip files the JSON returns as `null`):

- `constitution` — non-negotiable principles the spec MUST comply with; violations get flagged CRITICAL by reviewing-specs (Stage 3)
- All `adrs` — prior decisions you must respect, not re-litigate; silently contradicting a settled ADR is CRITICAL
- `glossary` / `domain` — canonical domain vocabulary; synonym proliferation is HIGH/MEDIUM (vocabulary drift)
- `architecture` — situates the feature within existing structure
- `readme` — fallback for high-level project understanding

These reads are load-bearing, not padding — the next stage's auto-review checks the spec against them. A spec written without reading them will fail review.

**Empty-context case:** if every context field in the JSON comes back `null` (greenfield project, no bootstrap yet), that's a valid state — proceed without context. Do not halt; do not ask the user to produce files. Note the empty-context state in your final report and move on.

## Step 3: Write spec.md

Use the structure in **Spec Structure** below. Omit any section that doesn't apply — don't leave "N/A" placeholders.

Required sections (in order): Goal, User Stories, Functional Requirements, Success Criteria, Edge Cases, Assumptions, Out-of-Scope.

Optional sections: Key Entities (only if data is involved), Open Questions (only if any remain), References (only if external docs/specs/ADRs are worth linking).

The Clarifications section is auto-managed by the grilling-specs skill if invoked later — do not create it preemptively here.

**Write atomically.** Compose the full spec content, write to `<spec_path>.tmp`, then `mv <spec_path>.tmp <spec_path>`. The atomic move prevents a half-written spec.md if the session dies mid-write. Apply the same pattern when editing the spec during grill/approval — never edit-in-place.

## Step 4: Initialize State File

Write `docs/specs/NNN-<short-name>/state.json` using the atomic pattern (write to `state.json.tmp`, then `mv state.json.tmp state.json`). See `sdd-coordinator` for the full state schema. Use the preflight outcomes the coordinator passed in (current branch).

**Do NOT commit.** The spec.md and state.json stay uncommitted in the working tree. The `choosing-feature-branch` skill at Stage 12 batch-commits them on the user's chosen branch alongside the plan and ADRs.

Initial state when this skill writes the file:

```json
{
  "feature_id": "NNN-<short-name>",
  "short_name": "<short-name>",
  "work_type": "<feature|fix from coordinator's in-memory dict>",
  "started_at": "<ISO-8601 timestamp>",
  "updated_at": "<ISO-8601 timestamp>",
  "spec_path": "docs/specs/NNN-<short-name>/spec.md",
  "plan_path": null,
  "branch": "<current-branch from coordinator>",
  "current_stage": "spec_writing",
  "stages_completed": ["preflight", "discovering"],
  "stages_skipped": [],
  "tasks": {},
  "adr_results": [],
  "test_status": null,
  "fix_iterations": 0,
  "final_review_completed": false
}
```

**Important:** leave `current_stage` as `"spec_writing"` and DO NOT add `"spec_written"` to `stages_completed` here. The coordinator will advance the stage and mark spec_written complete after this skill returns. (Avoids racing with the coordinator's stage-advancement logic.)

## Step 5: Inline Self-Review

Before reporting back:

### 5a. Schema validation (automated)

Run the validator script:

```bash
./spec-driven-development/scripts/validate-spec.sh docs/specs/NNN-<short-name>/spec.md
```

If it fails (exit code 1): fix every CRITICAL issue it reports, then re-run. Don't proceed until the script returns PASS. Warnings can be left if they're acceptable for the spec's nature, but address them when easy.

### 5b. Read with fresh eyes (manual)

The validator catches gross format issues; you check for semantic ones:

1. **Internal consistency** — sections don't contradict each other; FR-### items align with the user stories they support
2. **Testability** — every FR and SC could be evaluated objectively without re-reading the chat
3. **Scope** — focused enough for a single plan; no creeping subsystem sprawl
4. **Ambiguity** — terms that could be interpreted two ways are pinned down or moved to Open Questions
5. **Vocabulary** — uses domain terms from the glossary (if present); doesn't invent synonyms

Fix issues inline. No need to re-review; just fix and move on. (A dedicated reviewing-specs subagent will pass over this next.)

## Step 6: Report

Return to the coordinator. The report **must include the validator's PASS line verbatim** — the coordinator uses this as proof that validation actually ran and succeeded.

```
Spec written: docs/specs/NNN-<short-name>/spec.md
Sections present: [list]
Open questions: [count]
State file initialized.

Validator output (last line):
PASS — N warning(s), 0 critical issues
```

If you cannot produce a PASS line from the validator (the script returned non-zero and you couldn't fix the issues), do NOT claim the spec is written. Report the failure instead with the validator's full output and which CRITICAL issues you couldn't resolve.

The coordinator will re-run the validator before committing — if your reported PASS doesn't match a fresh run, the coordinator aborts the stage. So there's no benefit to faking it.

---

## Spec Structure

```markdown
# Spec: <Title>

**Feature ID:** NNN-<short-name>
**Created:** YYYY-MM-DD
**Status:** Draft
**Branch:** <branch-name>

## Goal

<One paragraph: what problem this solves and for whom. Use domain vocabulary.>

## User Stories

### Story 1 — <Brief title> (P1)

<Plain-language journey: who, what, why.>

**Why this priority:** <Reason — usually impact or dependency.>

**Independent test:** <How can this story alone be tested as an MVP increment?>

**Acceptance scenarios:**

1. **Given** <state>, **When** <action>, **Then** <outcome>
2. **Given** <state>, **When** <action>, **Then** <outcome>

---

### Story 2 — <Brief title> (P2)

<…same shape as Story 1…>

---

### Story 3 — <Brief title> (P3)

<…same shape as Story 1…>

## Functional Requirements

- **FR-001:** System MUST <capability>. _Stories: US1, US2_
- **FR-002:** Users MUST be able to <action>. _Stories: US1_
- **FR-003:** System MUST <data/behavior>. _Stories: US3_

(Each FR is testable. Each references the stories it supports.)

## Success Criteria

- **SC-001:** <Measurable outcome — time/percent/count/rate.>
- **SC-002:** <Measurable outcome.>
- **SC-003:** <User-experience or business metric.>

(All technology-agnostic, all measurable.)

## Key Entities

(Include only if data is involved. Otherwise omit.)

- **<Entity 1>:** <What it represents, key attributes (conceptual, no DB columns), key relationships.>
- **<Entity 2>:** <…>

## Edge Cases

- <What happens when [boundary condition]?>
- <How does the system handle [error scenario]?>
- <What's the behavior under [unusual load / network / data condition]?>

## Assumptions

- <Things we're treating as given that we should be explicit about.>
- <Defaults adopted from industry standards or project conventions.>

## Out-of-Scope

- <Adjacent feature explicitly deferred.>
- <Capability someone might reasonably expect but isn't included.>

## Open Questions

(Include only if some remain after discovery. Each should be answerable later — they're not blockers.)

- <Question 1>
- <Question 2>

## References

(Include only if external docs/specs/ADRs are worth linking.)

- ADR-NNNN — <title>
- <External doc URL or repo path>
```

---

## Acceptance Criteria Format Options

Default for "Acceptance scenarios": **Given/When/Then**. It's compact and readable.

**EARS format is allowed** when more precision is needed. Use only for FRs or for individual scenarios where ambiguity in the natural-language form is a real risk. Don't mix freely — pick a style per story and stick with it.

EARS templates:
- `WHEN <event> THEN <system> SHALL <response>` (event-driven)
- `IF <precondition> THEN <system> SHALL <response>` (conditional)
- `WHILE <state>, <system> SHALL <response>` (state-driven)
- `WHERE <feature>, <system> SHALL <response>` (ubiquitous)
- `<system> SHALL <response>` (unconditional)

If using EARS, mark the story with `**Acceptance criteria (EARS):**` instead of `**Acceptance scenarios:**`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Leaving "TBD" or bracketed placeholders | Either fill it in from discovery context or move it to Open Questions |
| Implementation creeping in (file paths, code) | That belongs in the plan. Move it. |
| Multiple stories conflated as one | If two stories have different priorities or different tests, split them |
| Vague success criteria ("fast", "scalable") | Quantify: "p95 < 200ms", "10k concurrent users" |
| Acceptance scenarios that aren't testable | Restate so a tester (or a tester subagent) could verify with a clear pass/fail |
| Domain-noun drift (using "user" then "customer" then "account holder" for the same thing) | Canonical term from glossary; one term across the doc |

## Red Flags

- About to start writing the spec without having Read constitution + ADRs (when present) → STOP; that's the failure mode the auto-review (Stage 3) flags as CRITICAL and you'd ship a spec that fails review
- About to use a synonym for a glossary term ("customer" instead of the project's canonical "User") → STOP; vocabulary drift is a review finding
- About to add a Mermaid block → delete
- About to write "the developer should..." → wrong document; that's the plan
- Found a real gap mid-write → stop, return to discovery, don't paper over
- Spec is longer than 600 lines → likely too big; consider decomposition
