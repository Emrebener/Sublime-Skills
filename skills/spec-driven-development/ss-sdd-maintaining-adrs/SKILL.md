---
name: ss-sdd-maintaining-adrs
description: Use when dispatched as a subagent during the ADR maintenance stage of an SDD pipeline run. Reads the current spec and prior ADRs, identifies any architecturally significant decisions that warrant new ADR records, and writes them in the locked format.
---

# Maintaining ADRs

## Overview

Identify and capture architecturally significant decisions from a spec as Architecture Decision Records. Avoid duplicates with existing ADRs. Skip if the spec contains no decisions worth recording.

**Core principle:** Not every choice is an ADR. ADR-worthy = a decision a future engineer or reviewer would re-litigate without context — choices where the *reason* matters more than the *outcome*.

**Returning "0 ADRs created" is a normal and common outcome.** Execution-level specs often have nothing ADR-worthy. Don't manufacture ADRs to look productive.

**Leaf skill — do not dispatch sub-subagents.** If you find yourself wanting to delegate, you're either overthinking the task or it doesn't belong here.

**Announce at start:** "I'm using the ss-sdd-maintaining-adrs skill to capture architectural decisions."

## Hard Gates

- Do NOT use todo/task tools. The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools. Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents. You are a leaf skill.

## What You Get From the Coordinator

The dispatch prompt includes:

- `SPEC_PATH` — absolute path to the spec
- `ADR_DIR` — directory where ADRs live (hardcoded `docs/adr`; the coordinator passes the value into the dispatch)
- `EXISTING_ADRS` — list of paths to existing ADR files (may be empty if this is the project's first feature)
- `DECISIONS_CAPTURED` — list of decisions the coordinator flagged during discovery + grill as ADR candidates (may be empty)

## Checklist

1. Read the spec
2. Read all existing ADRs (to know what's already captured and the next sequential number)
3. Identify ADR-worthy decisions from the spec
4. Cross-check against existing ADRs to skip duplicates
5. Write new ADR file(s) using the locked format
6. Report back

## Step 1 & 2: Read

Read `SPEC_PATH`. Pay attention to:
- The "Decisions" section (often where the major choices land)
- The Constraints and Out of Scope sections (sometimes record the rejected alternatives)
- The `## Clarifications` section (if present — written by the `ss-sdd-grilling-specs` skill). Each clarification is a `- Q: ... → A: ...` bullet inside a `### Session YYYY-MM-DD` subheading; grill-driven decisions are valid ADR sources when they meet the ADR-worthy criteria below

Then read every file in `EXISTING_ADRS` — you need to know:

- The highest existing ADR number — the next ADR is `highest + 1` (do not fill gaps from deleted ADRs)
- What decisions are already documented (to avoid duplicates)
- What's been superseded (don't reopen those without good reason)
- The project's existing tone/depth so new ADRs match

If `EXISTING_ADRS` is empty, this is the project's first ADR. Start at `0001`.

## Step 3: Identify ADR-Worthy Decisions

A decision is ADR-worthy when **all** of these are true:

- **Architectural:** touches structure, technology, communication, data flow, security model, deployment topology, persistence, or boundary placement — not just business-level
- **Real alternative existed:** a reasonable alternative was considered and rejected (or could reasonably have been chosen)
- **Reasoning is not self-evident from the code or spec:** a future engineer reading the code without context would ask "why did they do this?" — and the answer is non-obvious enough to warrant capturing
- **Not already captured:** no existing ADR documents this decision

**Examples of ADR-worthy:**
- Choice of auth scheme (JWT vs sessions vs OAuth2)
- Persistence layer choice (SQL vs document DB vs event store)
- Sync vs async processing for a workflow
- API style (REST vs gRPC vs GraphQL)
- Module boundary or context boundary decisions
- Caching strategy
- Deployment topology change (monolith → service split)
- Custom serialization format vs off-the-shelf
- Hard cap on retry counts, timeouts, or queue depths (when the *value* is policy, not a hyperparameter)

**NOT ADR-worthy:**
- Routine implementation details (variable naming, function organization)
- Spec-level requirements (those live in the spec)
- Choices forced by external constraints with no real alternative (e.g., "use the company's mandated SSO")
- Stylistic preferences
- Library choice when the project already uses that library elsewhere
- Choices fully determined by an existing ADR

## Step 4: Avoid Duplicates

For each candidate, check if an existing ADR already covers it:

- **Exact match:** skip — note in the report which existing ADR covers it
- **Partial overlap:** the new decision is a refinement or context-specific extension of an existing ADR. Write a new ADR that references the existing one rather than restating it.
- **Direct supersession:** the new decision overrides an existing ADR. Write the new ADR with `Supersedes: ADR-NNNN`, AND edit the existing ADR's status line: change `Status: Accepted` (or whatever it was) to `Status: Superseded by ADR-NNNN`. You write both file changes; the coordinator commits them together.

## Step 5: Write ADRs

Use this **locked format** (do not deviate):

```markdown
# ADR-NNNN: <Title>

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN | Deprecated
- **Date:** YYYY-MM-DD
- **Spec:** [NNN-short-name](../specs/NNN-short-name/spec.md)
- **Supersedes:** ADR-NNNN (optional, only when applicable)

## Context

<2-4 paragraphs: the situation we're in, the forces at play, what's driving the decision now. Use project domain vocabulary. Don't restate the spec — link to it.>

## Decision

<1-2 paragraphs: what we chose, stated clearly enough that someone could implement it from this alone.>

## Consequences

**Positive:**
- <Outcome we gain.>
- <Outcome we gain.>

**Negative:**
- <Cost we accept.>
- <Risk we take on.>

**Trade-offs accepted:**
- <Things we're explicitly giving up vs. alternatives.>

## Alternatives Considered

- **<Alt A>:** <What it was, why rejected (concretely).>
- **<Alt B>:** <What it was, why rejected.>
- <Add more only if there were genuine candidates. Two-three is typical.>
```

**Filename:** `<ADR_DIR>/<NNNN>-<kebab-title>.md`
- `NNNN` is zero-padded to 4 digits
- `kebab-title` is 2-5 kebab-case words from the ADR title (e.g., `0003-use-jwt-for-sessions.md`)

**Status:** Default to `Proposed`. The coordinator's user-approval stage will flip it to `Accepted` (or the user can during review).

**Do NOT commit.** Write the ADR files but do NOT run `git commit`. Stage 12 (`ss-sdd-choosing-feature-branch`) batch-commits all SDD planning artifacts — including these ADRs — on the user's chosen branch.

**Date:** Today in UTC: `date -u +%Y-%m-%d`. Don't use local time.

**Numbering:** Sequential across all ADRs in the project. If the highest existing is `0012`, the next is `0013`, even if `0007` was deleted (do not fill gaps). Multiple new ADRs from one spec are numbered sequentially in the order they were identified.

**Alternatives Considered — minimum count:** At least 1 alternative is required. If you cannot name a single genuine alternative, the decision isn't really architectural — reconsider whether it's ADR-worthy at all. Two or three is typical; padding with weak alternatives makes the ADR worse, not better.

**Consequences — be concrete:** "Adds ~50ms login latency" beats "may be slower." If you don't know a number, say what you do know ("Single-DB read replaced by token verify + DB read") rather than vaguely speculating ("might affect performance").

## Step 6: Report

Return to the coordinator:

```markdown
## ADR Maintenance Result

**ADRs created:** N
- ADR-NNNN — <title> (file: docs/adr/NNNN-kebab.md)
- ADR-NNNN — <title> (file: docs/adr/NNNN-kebab.md)

**ADRs updated (superseded markers):** N
- ADR-NNNN — marked superseded by ADR-NNNN

**Decisions skipped (already covered):**
- <decision>: covered by ADR-NNNN

**Decisions skipped (not ADR-worthy):**
- <decision>: <reason — e.g., "no alternative was considered", "stylistic only">

**Notes for coordinator:**
- <Anything the coordinator should bring to the user's attention before approval, e.g., a status-supersession conflict.>
```

If no ADRs are warranted, return:

```markdown
## ADR Maintenance Result

**ADRs created:** 0

No architecturally significant decisions warrant new ADRs. <One sentence explaining why — usually: the spec is execution-level, decisions are constrained by existing ADRs, or no real alternatives were in play.>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Writing an ADR for every spec, even when nothing is ADR-worthy | Returning "0 ADRs" is normal and common |
| Restating the spec in the Context section | Link to the spec; Context is about *what's forcing the decision now*, not what the feature is |
| Vague Consequences ("might be slower", "could cause issues") | Quantify or remove. "Adds ~50ms login latency" beats "may be slower" |
| Padding Alternatives Considered with weak options | If A vs B wasn't a real choice, don't pad the section. Real alternatives only. |
| Marking ADR as Accepted prematurely | Default to Proposed; user approval flips it |
| Not updating the superseded ADR's status when writing a successor | Both files must be edited — they're a pair |
| Inconsistent kebab title vs ADR title | Title in the file should match the filename slug |
| Filling gaps in numbering (e.g., re-using 0007 after it was deleted) | Always use highest + 1; gaps are intentional history |
| Using local date instead of UTC | `date -u +%Y-%m-%d` everywhere |

## Red Flags

- About to write an ADR titled "Use TypeScript" or "Use Git" → not ADR-worthy
- About to write an ADR contradicting an existing one without marking supersession → STOP; either supersede explicitly or step back
- About to create three ADRs for the same decision split across three angles → consolidate; one ADR per decision
- About to write Consequences that are all "may", "could", "might" → STOP; either be concrete or drop the bullet
- About to write an ADR with zero genuine alternatives → STOP; reconsider whether this is architectural
