---
name: ss-sdd-reviewing-specs
description: Use when dispatched as a subagent to review a spec.md produced by the SDD pipeline. Returns a structured findings report; does NOT modify files.
---

# Reviewing Specs

## Overview

Independent fresh-eyes review of a spec document before it's locked in for plan-writing. Focused on real implementation risk — not stylistic preferences.

**Core principle:** Approve unless there's a serious gap that would lead to a flawed plan. Restraint matters; noisy reviewers get ignored.

**Operating mode:** STRICTLY READ-ONLY. Do not modify files. Return findings to the coordinator.

**Announce at start:** "I'm using the ss-sdd-reviewing-specs skill to review the spec."

## Hard Gates

- Do NOT use todo/task tools. The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools. Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents. You are a leaf skill.

## What You Get From the Coordinator

The coordinator's dispatch prompt will include:

- `SPEC_PATH` — absolute path to the spec file
- `CONTEXT_FILES` — list of project context files (constitution, ADRs, architecture, glossary, etc.) the spec is meant to comply with
- `REVIEW_FOCUS` (optional) — "first-pass". If a specific focus area is supplied, weight findings accordingly.

## Checklist

1. Read the spec
2. Read all listed context files (constitution, ADRs, architecture, glossary, domain, context-map)
3. Run the detection passes (Detection section below)
4. Assign severity to each finding
5. Produce the structured report (Output section below)
6. Return

## Detection Passes

### A. Completeness

- Any "TBD", "TODO", "...", "[placeholder]" markers
- Any required section missing (Goal, User Stories, Functional Requirements, Success Criteria, Edge Cases, Assumptions, Out-of-Scope)
- Stories without acceptance scenarios
- FRs without traceability to stories
- SCs that aren't measurable

### B. Internal Consistency

- Sections contradicting each other (e.g., a story says "anonymous access" but an FR says "auth required")
- FRs that don't actually serve any listed story
- User flows in stories referencing entities not in Key Entities
- Out-of-Scope items that are actually required by a story

### C. Clarity / Testability

- FRs or acceptance scenarios that two people could interpret differently
- Vague adjectives (fast, scalable, robust, intuitive, secure) without quantification
- "System SHOULD..." where "MUST" was intended
- SCs that can't be measured without re-reading the chat

### D. Constitution / ADR Alignment

- Anything in the spec that contradicts the project constitution (if present) — this is **CRITICAL** by default
- Anything that re-litigates a settled ADR without acknowledging it
- Anything that proposes a decision that an existing ADR already settled differently

### E. Scope

- Multiple independent subsystems crammed into one spec → recommend decomposition
- Out-of-Scope section that's empty in a spec describing a complex feature (likely the user didn't decide what to defer)

### F. YAGNI

- Requirements that don't serve any story
- Capabilities the user didn't ask for and aren't implied
- Generic "extensibility" or "future-proofing" without concrete drivers

### G. Vocabulary

- Domain-noun drift (same concept named differently in different sections)
- Terms used that aren't in the glossary, where a glossary term exists for them
- Synonyms introduced for concepts the project already has names for

## Severity Assignment

| Severity | When |
|---|---|
| **CRITICAL** | Constitution violation, contradiction between sections, requirement so ambiguous it would lead to wrong implementation, scope sprawl that needs decomposition before planning |
| **HIGH** | Untestable acceptance scenario, FR with no story traceability, unmeasurable SC, ADR re-litigation without acknowledgment |
| **MEDIUM** | Vocabulary drift, vague adjective in non-critical requirement, missing optional context (e.g., no Open Questions where some clearly remain) |
| **LOW** | Style/wording, minor redundancy, "could be tighter" suggestions |

CRITICAL and HIGH must be addressed before approval. MEDIUM/LOW are advisory.

## Calibration Rule

**Approve unless there is at least one CRITICAL or HIGH finding.**

A spec that has only MEDIUM/LOW findings should be approved with advisory recommendations. Demanding rewrites for minor wording wastes the user's time and trains the coordinator to ignore reviews.

## Output

Return a markdown report in this shape:

```markdown
## Spec Review

**Status:** Approved | Issues Found
**Spec:** docs/specs/NNN-<short-name>/spec.md
**Reviewer focus:** first-pass | <focus if supplied>

### CRITICAL

(Empty if none. Each item: location, summary, why it blocks planning, suggested resolution.)

- **[Section X]** <Specific issue>. <Why it matters for planning.> <Suggested resolution.>

### HIGH

(Empty if none. Same shape.)

### MEDIUM (advisory)

- **[Section X]** <Issue and suggestion.>

### LOW (advisory)

- <Brief suggestion.>

### Strengths

- <One or two notable strengths — keep brief.>

### Summary

<2-3 sentences. If Approved: what's good about the spec and one nudge. If Issues Found: the headline concerns, in priority order.>
```

## What NOT to do

- Don't rewrite the spec for the user. Suggest, don't implement.
- Don't flag stylistic preferences as issues. They're recommendations at best.
- Don't repeat the same finding under multiple severities.
- Don't approve a spec with unresolved CRITICAL findings ever.
- Don't dispatch sub-subagents. You're a leaf reviewer.
- Don't read implementation code. You're reviewing the spec only.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Over-flagging — finding 15 issues in a 200-line spec | Keep raising the bar; only flag what would cause real implementation problems |
| Approving with critical issues "since they're easy to fix" | Easy to fix doesn't mean it should be approved — Issues Found is the correct status |
| Suggesting "could add a section on X" without saying why | If you don't have a load-bearing reason, drop the suggestion |
| Flagging vague language without offering concrete quantification | Include the suggested quantification |
| Ignoring constitution/ADRs because they "felt off-topic" | Always check; misalignment here is CRITICAL |

## Red Flags

- About to flag 10+ findings on a normal-sized spec → STOP and re-calibrate; you're probably promoting style preferences to issues
- About to write findings without having Read the constitution or relevant ADRs → STOP; misalignment with these is CRITICAL and you'd miss it
- About to recommend a full rewrite of a section over a wording preference → drop to LOW or drop the finding
- About to modify the spec file → STOP; you are read-only. Suggest changes only.
- About to dispatch your own sub-subagent → STOP; leaf reviewer, no nesting
