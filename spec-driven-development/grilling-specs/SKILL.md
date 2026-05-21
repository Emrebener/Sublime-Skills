---
name: grilling-specs
description: Use during the optional grill stage of an SDD pipeline run, after spec-review and ADR maintenance, when the user wants the spec stress-tested for weak/unclear/underspecified areas. Drives a bounded interview that applies each accepted answer to the spec inline.
---

# Grilling Specs

## Overview

Relentlessly interview the user about the spec to surface and resolve weaknesses — but bounded, scoped, and applied. Every accepted answer updates the spec file immediately. The point isn't to interrogate for its own sake; it's to tighten the spec before plan-writing.

**Core principle:** Every answer that lands updates the spec. A grill that doesn't change the document is a grill that wasted the user's time.

**Announce at start:** "I'm using the grilling-specs skill to stress-test the spec."

## Hard Gates

- Do NOT ask more questions than the configured cap (default 10).
- Do NOT ask about areas already adequately covered.
- Do NOT proceed to the next question until the current answer is applied to the spec and saved.
- Do NOT introduce new design decisions on your own — propose options and let the user pick.

## Checklist

1. Load project context (script + Read files)
2. Read the current spec
3. Build a prioritized internal queue of candidate questions
4. Ask one at a time, with a recommended answer where applicable
5. After each accepted answer, update the spec inline and save
6. Stop when: user signals done, all high-impact areas resolved, or hit cap (default 10)
7. Report what was changed

## Step 1: Load Context

Run the discovery script if the coordinator hasn't already passed you the context. Read what's present:

```bash
./spec-driven-development/scripts/discover-context.sh
```

The grill needs:
- The current spec
- Constitution (if any)
- Glossary (if any)
- Relevant ADRs (especially any cited or contradicted by the spec)

## Step 2: Read the Spec and Identify Weak Spots

Scan for these signal categories. Mark each with a status: **Clear** / **Partial** / **Missing**. The internal coverage map is a working tool — don't dump it to the user.

| Category | What to look for |
|---|---|
| Goal sharpness | Is the problem statement specific enough? Does it distinguish symptoms from root cause? |
| Story priority rationale | Are P1/P2/P3 priorities justified? Could any P1 be reasonably deferred? |
| Acceptance testability | For each acceptance scenario, would a tester know unambiguously whether it passes? |
| FR coverage | Are there stories not fully covered by FRs? FRs that don't serve any story? |
| SC measurability | Are success criteria quantified or are there hand-wavy ones ("fast", "scalable")? |
| Entity completeness | Are key entities' attributes and relationships specific enough to inform a data model? |
| Edge case depth | Are negative paths, concurrency, partial failures, empty/zero states addressed? |
| Constraint rigor | Are tech/perf/security/compliance constraints concrete? Or just "must be secure"? |
| Integration risk | Are external dependencies named, with their failure modes considered? |
| Constitution / ADR fit | Anything subtly drifting from project principles or past decisions? |
| Out-of-scope explicitness | Are common-but-deferred things actually listed as out-of-scope? Or are they ambiguous? |

## Step 3: Prioritized Question Queue

Build an internal queue of candidate questions, bounded by the cap. Prioritize by **(impact × uncertainty)**:

- **Impact** — how much does this answer change the plan, the tests, or the architecture?
- **Uncertainty** — how unclear is the spec on this dimension currently?

Drop questions where:
- The answer wouldn't change implementation or testing
- A reasonable default would be obvious to any implementer
- It's a plan-level detail (file paths, function names) — those belong in the plan stage

**Cap:** default 10. Override via `.sublime-skills/config.yml` → `grill.question_cap`. Read it via the scalar helper:

```bash
CAP=$(./spec-driven-development/scripts/get-config-value.sh grill question_cap)
CAP="${CAP:-10}"
[ "$CAP" -gt 20 ] && CAP=20   # hard ceiling
```

Hard ceiling of 20 even with config override — beyond that, the spec needs a rewrite, not a grill.

## Step 4: Ask, One at a Time

For each question:

**Multiple choice with recommendation (preferred when there are clear options):**

> **Q3 — [Topic]: <Question>**
>
> Spec section: <quote relevant snippet>
>
> **Recommended:** Option B — <reasoning, 1-2 sentences>
>
> | Option | Description | Implication |
> |---|---|---|
> | A | <Description> | <What it means for the feature> |
> | B | <Description> | <What it means> |
> | C | <Description> | <What it means> |
> | Other | Your own short answer (≤10 words) | — |
>
> Reply with the letter, "yes" / "recommended", or a short custom answer.

**Short-answer with suggestion (when options don't fit):**

> **Q3 — [Topic]: <Question>**
>
> **Suggested:** <Proposed answer> — <reasoning>
>
> Reply with "yes" to accept, or your own short answer.

**Rules:**
- One question per message. No combining.
- Always show a recommendation. Don't ask the user to do your thinking.
- After their answer: if "yes" / "recommended" / "suggested", use your stated recommendation. Otherwise validate the answer (and disambiguate inline if needed — that doesn't count as a new question).

## Step 5: Apply the Answer Inline

After every accepted answer, update the spec file:

1. Add (or extend) a `## Clarifications` section just below the Goal section if it doesn't exist
2. Add (or extend) a `### Session YYYY-MM-DD` subheading for today's grill
3. Append a bullet: `- Q: <question> → A: <final answer>`
4. **Apply the substance** to the appropriate section(s) of the spec:

| Question category | Where to apply |
|---|---|
| Goal sharpness | Edit the Goal paragraph |
| Story priority | Edit the relevant story's "Why this priority" line |
| Acceptance testability | Edit the acceptance scenarios for that story |
| FR coverage | Add/edit/remove FR items |
| SC measurability | Quantify the SC item |
| Entity attributes | Edit the Key Entities entry |
| Edge cases | Add to Edge Cases |
| Constraints | Add to Assumptions or Out-of-Scope, as appropriate |
| Integration | Add to Edge Cases or Assumptions |
| Constitution fit | Edit the offending FR/story to comply |
| Out-of-scope | Edit the Out-of-Scope list |

5. **Save the spec immediately** using the atomic write pattern: write the full new spec content to `<spec_path>.tmp`, then `mv <spec_path>.tmp <spec_path>`. Don't batch multiple answers before saving — interruption loses them, and the atomic move prevents half-written files.

6. If the new clarification contradicts earlier wording, **replace the contradicted text**. Don't leave both.

7. Then ask the next question (or stop, per Step 6).

## Step 6: Stop Conditions

Stop asking when any of these is true:

- User says "done", "good", "enough", "stop", "no more"
- All categories with status Partial/Missing have been addressed (or explicitly deferred by the user)
- You hit the cap (default 10)

When stopping early because all high-impact areas were resolved, briefly explain: "All high-impact areas resolved — stopping at Q5."

## Step 7: Report

Return to the coordinator:

```
Grill complete.
- Questions asked: <N>
- Spec sections touched: [Goal, Story 2, FR-003, SC-002, Edge Cases]
- Clarifications session: YYYY-MM-DD (N bullets)
- Stopped because: user_signal | resolved_all | cap_hit
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Asking without applying the answer to the spec | Apply immediately, save, then move on |
| Batching multiple answers before saving | Interruption loses everything — save per answer |
| Asking about plan-level details (function names, file paths) | Out of scope; move on |
| Going past the cap | Hard ceiling at 20. If the spec still feels weak, it needs a rewrite |
| Leaving the contradicted earlier wording in place | Edit it out; the clarification replaces it |
| No recommendation, just open-ended question | Always lead with a recommendation |
| Skipping the Clarifications section entry | The audit trail matters — record every accepted Q&A |

## Red Flags

- Asked the same question worded two ways → you're stretching the cap; stop instead
- About to introduce a design decision without offering options → step back; surface alternatives
- Spec file getting longer than 800 lines from grill edits → the spec is over-stuffed; recommend decomposition to the coordinator
