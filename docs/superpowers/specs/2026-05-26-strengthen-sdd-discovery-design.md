# Strengthening SDD Discovery (Stage 1) — Design

**Date:** 2026-05-26
**Skill affected:** `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
**Pipeline stage:** Stage 1 (Discovering Requirements)
**Status:** Design approved, pending implementation plan

---

## Background

The SDD pipeline (`ss-sdd-coordinator`) drives an 18-stage flow from preflight through finishing. Stage 1 — Discovering Requirements — is the only conversational stage that aligns the agent and the user before any artifact is written. Every later stage (spec writing, reviews, ADR maintenance, planning, implementation) depends on the shared understanding Stage 1 produces. A weak Stage 1 propagates weakness through the entire pipeline.

An audit of the existing skill surfaced 9 findings. The 4 highest-impact gaps are:

1. **No mid-conversation playback loop.** The only restatement happens at the end (section-by-section approval). By then, dimensions interlock and corrections force re-doing other sections.
2. **No probe for the implicit / unsaid.** The dimensions surface what the user *says*, not what the user assumes, why now, what alternatives they rejected, or what happens if the feature isn't built.
3. **The 9 dimensions are flat and generic.** Same depth for trivial dimensions as for load-bearing ones; no signal-driven prioritization.
4. **Handoff to Stage 2 is unstructured.** The spec writer re-interprets a bulleted summary from conversation context, allowing drift.

Five additional findings (concrete-example prompt, contradiction handling, completeness signal, mid-conversation scope re-check, graceful-unknown protocol) round out the picture. All nine are addressed by this design.

## Goals

- Make discovery's clarification work **enforceable** rather than aspirational — every new rigor has a named, numbered home.
- Catch framing mistakes at the **cheapest possible moment** (before the spec is written).
- Reduce spec drift caused by **unstructured handoff** from Stage 1 to Stage 2.
- Keep the skill **minimal** — no new files, no new config keys, no new pipeline stages, no breaking changes to other skills.

## Non-goals

- Restructuring the SDD pipeline at the stage level (still 18 stages, Stage 1 still mandatory and artifact-free).
- Editing `ss-sdd-grilling-specs` or `ss-sdd-writing-specs`. If stronger discovery makes the grill find less, that's a happy outcome — not a reason to rewrite the grill. The Stage 2 writer may benefit from an explicit "Consuming the discovery digest" subsection later; that's a follow-up if proven needed in practice.
- Adding tunable config keys (no question caps, no toggles for the framing probe).
- Touching the coordinator skill — its Stage 1 description is a single sentence pointing at this skill; no edit needed.

---

## Design overview

The current `ss-sdd-discovering-requirements/SKILL.md` has 8 numbered checklist items. The new structure regroups them under **four named phases**, with new content inserted only where it has a clear home:

```
Phase 1 — Context        (current Steps 1-3, unchanged)
Phase 2 — Framing        (NEW — framing probe: F1-F4)
Phase 3 — Targeted walk  (dimensions reframed as coverage checklist)
Phase 4 — Synthesis      (stop-gate + structured handoff)

Cross-cutting rules      (NEW — apply throughout Phases 2-4)
```

The 9-dimension coverage table is preserved verbatim as the spine of Phase 3. Its role shifts from *script* to *coverage checklist*: every dimension must end Phase 3 with a stated answer (or explicit "N/A — reason"). The agent's depth per dimension is driven by signals from Phase 1 (constitution / ADRs) and Phase 2 (framing answers), not by a fixed quota.

---

## Phase 1 — Context

Unchanged from the current skill. Three sub-steps:

1. **Load project context** — runs `framework/discover-context.sh` and Reads any returned files (constitution, ADRs, architecture, glossary, domain, README fallback).
2. **Scope check** — assesses whether the request is one feature or multiple. Recommends decomposition into separate SDD runs if multiple.
3. **Determine work type** — classifies as `feature` or `fix`. Inferred from initial input; asked only if genuinely ambiguous.

No behavioral changes here. Phase 1 is the foundation that Phase 2's framing probe and Phase 3's depth rule both build on.

---

## Phase 2 — Framing probe (NEW)

Runs after Phase 1 (context/scope/work-type), before Phase 3 (dimension walk). The purpose is to surface the implicit before the agent commits to gathering requirements for the literal ask.

### The probe set

Four fixed probes, asked in this order. Each can be **skipped only when the user's initial input already answered it unambiguously** — no other shortcut.

| # | Probe | What it surfaces |
|---|---|---|
| F1 | **Why now?** "What's prompting this now — what changed, or what's the cost of not building it?" | Underlying driver. Distinguishes "nice-to-have we keep deferring" from "load-bearing for Q3 launch." Reshapes priority and scope. |
| F2 | **Alternatives considered.** "What other approaches did you consider, and what made you land here?" | Surfaces whether the user has already filtered options or is treating the first idea as the only idea. If they say "I didn't consider any," the agent flags this and proposes 2-3 alternatives before continuing. |
| F3 | **Cost of inaction.** "If we don't build this, what does the affected user do instead — workaround, suffer, leave?" | Reveals real stakes and the true substitute. If the answer is "nothing, they just live with it," that's a strong signal to deprioritize or rescope. |
| F4 | **Concrete walkthrough.** "Walk me through one real scenario, start to finish — a specific user, a specific moment, what they do and what they expect to happen." | Forces commitment to specifics. Catches abstract framings that hide unanswered questions. |

### Protocol

- **One probe per message** (same rule as the rest of discovery).
- **No recommendations on framing probes.** Framing answers come from the user; the agent has no basis to recommend "why now."
- **Each answer is logged in the agent's in-memory understanding**, not written to disk (consistent with the "no artifacts in Phase 1" hard gate — Stage 1 produces no files at all).
- **The playback gate (CC-1) applies most aggressively here** — framing answers are where misunderstanding is cheapest to catch and most expensive to leave.
- **F2 has a forcing function.** If the user says they didn't consider alternatives, the agent **must** propose 2-3 before continuing to F3. This is the framing-rescue moment.
- **F4 is the bridge to Phase 3.** The concrete walkthrough naturally exposes which dimensions matter most.

### Skip conditions (explicit, narrow)

| Probe | Skip only when |
|---|---|
| F1 | The user's initial input contained an explicit "we need this because X" or a deadline/incident framing |
| F2 | The user's initial input named alternatives they rejected |
| F3 | The user's initial input explicitly framed the cost of inaction |
| F4 | The user's initial input *already was* a concrete scenario with specific users and specific actions |

"I think I can guess" is not a valid skip condition.

### Non-overlap with Phase 3

The framing probe does **not** replace the Purpose dimension in Phase 3. The probe surfaces *why* and *what's behind the ask*; the Purpose dimension still pins down the problem statement for the spec. They feed each other.

---

## Phase 3 — Targeted dimension walk

This phase is the heart of discovery — where the spec's content is actually shaped. The structural change is small but load-bearing: the 9-dimension table goes from *script* to *coverage checklist*.

### The coverage rule

Every dimension below must end Phase 3 with a **stated answer** — a sentence or two the agent can recite. A dimension that genuinely doesn't apply ends with an explicit *"N/A — <one-line reason>"* statement. There is no third option (no "skipped," no "we'll get to it"). This is the rule the Phase 4 stop gate verifies.

| Dimension | What "stated answer" looks like |
|---|---|
| Purpose | One sentence naming the problem and who feels it |
| Users | Named roles (or "single role: X") + the trigger that brings each to the feature |
| Scope (in) | Bullet list of the smallest valuable slice |
| Scope (out) | Explicit deferred items |
| Success | At least one measurable outcome (number, threshold, observable behavior) |
| Key entities | Named entities with attributes, or explicit "N/A — no domain data" |
| Edge cases | At least the top 3 failure modes |
| Constraints | Named constraints (tech/perf/security/compliance) or explicit "N/A — none beyond defaults" |
| Integration | External dependencies named with failure modes, or explicit "N/A — self-contained" |

The "Sample question" column from the current skill becomes **guidance, not script** — the agent picks wording that fits the conversation, drawing on framing-probe answers.

### Depth rule

Depth per dimension is **driven by signals from Phase 1 and Phase 2**, not by a fixed quota. The agent drills **deeper** when:

- **Phase 2 framing (F4 walkthrough)** exposed a specific ambiguity in that dimension (e.g., the walkthrough revealed two user roles where only one was implied → drill Users)
- **Phase 1 context** (constitution / ADRs) implies non-trivial constraints on that dimension (e.g., ADR-0007 mandates auth pattern → drill Constraints to confirm alignment)
- **Risk-weight** is high: data-handling dimensions for features touching user data, integration dimensions when the feature crosses a service boundary, edge cases when the framing implied real-time or financial behavior

The agent drills **shallower** (one question, often answered from context alone) when:

- The dimension is trivially settled by Phase 1 + Phase 2 answers
- The user's initial input already specified it concretely
- A prior ADR settles it — agent cites the ADR and records the stated answer with the ADR reference

There is **no fixed cap on questions per dimension**. The cap is implicit: the stop gate refuses to advance until every dimension has a stated answer, and the cross-cutting rules (no repeating, no asking-twice-worded-differently) prevent over-drilling.

### Major decisions sub-step

The current Step 5 ("Propose 2-3 approaches for any non-obvious major design decision") survives unchanged inside Phase 3. It triggers when the dimension walk surfaces a fork (auth strategy, sync vs async, storage model, etc.). Format stays the same: 2-3 alternatives, trade-offs, recommendation lead, user picks.

**One refinement:** a decision proposed here is **tagged as an ADR candidate** in the agent's in-memory understanding, with the chosen option plus rejected ones and the reasoning. Phase 4's handoff digest serializes these tags so Stage 6 (`ss-sdd-maintaining-adrs`) gets clean input.

### Graceful-unknown protocol

If the agent **cannot** state an answer for a dimension after a reasonable amount of drilling: surface explicitly as an **Open Question**, propose a reasonable default, and let the user choose to (a) accept the default, (b) defer to the spec's "Assumptions" section, or (c) defer to a follow-up spec. This is the recovery mechanism the current skill lacks.

---

## Phase 4 — Synthesis

Three steps, in order.

### Step 4.1 — Stop-and-summarize gate (NEW)

Before summarizing back to the user, the agent must pass a small **self-check**:

> Can I, right now, write a single paragraph that names: (a) who the primary user is, (b) what triggers them to use this, (c) what success looks like for them, and (d) the top 3 ways this could go wrong?
>
> If yes — proceed to Step 4.2.
> If no — return to Phase 3 and drill the missing dimension(s). Do not summarize.

A **second sub-check** runs alongside: every dimension from Phase 3 must have its stated answer (or explicit N/A) in the agent's in-memory understanding. If any dimension is still in a "we'll figure it out" state, that's a return-to-Phase-3 signal regardless of the paragraph check.

This replaces the current skill's softer "Stop when you have enough" guidance.

### Step 4.2 — Section-by-section approval

Identical to the current Step 6, with one tightening: each section is presented with **the underlying framing-probe answer that shaped it** inline as a one-liner, when relevant. Example:

> **Goal & problem.** *(Driver from Phase 2: customer success spends ~5 hrs/week on manual exports.)* This feature gives CS reps a self-serve export panel so they can …
>
> Does this match your intent?

This makes it cheap for the user to spot if the agent's framing-probe interpretation drifted.

Sections (unchanged from current skill): Goal & problem → Users & flows → Scope → Success → Key entities → Edge cases & constraints → Major decisions. Section-by-section approval is required; the agent does not move to the next section without explicit confirmation.

### Step 4.3 — Final confirmation

Identical to the current Step 7. The agent states the one-paragraph summary from the stop-gate self-check and asks "Ready to write this up?" Wait for explicit confirmation.

### Step 4.4 — Structured handoff digest

The current Step 8 returns a bulleted list. The sharpened version returns a **fixed-shape block** so Stage 2 consumes it without re-interpreting:

```
=== DISCOVERY HANDOFF ===
short_name: <kebab-case>
work_type: feature | fix

framing:
  driver:           <one sentence — answer to F1 "why now">
  alternatives:     <list of alternatives considered + why rejected, OR
                    "user did not consider; agent proposed X/Y/Z; user chose <pick>">
  cost_of_inaction: <one sentence — answer to F3>
  walkthrough:      <one short paragraph — answer to F4>

dimensions:
  purpose:     <stated answer | N/A: reason>
  users:       <stated answer | N/A: reason>
  scope_in:    <bullet list>
  scope_out:   <bullet list>
  success:     <stated answer with measurable outcome | N/A: reason>
  entities:    <stated answer | N/A: reason>
  edge_cases:  <bullet list of top failure modes>
  constraints: <stated answer | N/A: reason>
  integration: <stated answer | N/A: reason>

major_decisions:    # each becomes an ADR candidate at Stage 6
  - title:    <short title>
    chosen:   <chosen option>
    rejected: [<option 1>, <option 2>]
    reasoning: <one to two sentences>

open_questions:     # from Phase 3's graceful-unknown protocol
  - question: <what's open>
    default:  <reasonable default agent proposed>
    disposition: accepted_default | deferred_to_assumptions | deferred_to_followup_spec

approved_sections: [goal, users, scope, success, entities, edge_cases, decisions]
=== END HANDOFF ===
```

**Why this shape:**
- Still in-conversation context (no new file written — preserves the Phase 1 "no artifacts" hard gate).
- Stage 2's `ss-sdd-writing-specs` already has structure to consume; a structured digest reduces drift versus re-interpreting bullets.
- The `major_decisions` block feeds Stage 6 directly — each entry is one ADR candidate with everything the maintainer needs.
- The `framing` block gives Stage 2 the "why" it can use in the spec's Goal section — a signal currently lost between discovery and spec-writing.

---

## Cross-cutting rules

A dedicated subsection in SKILL.md (between the phase definitions and the Common Mistakes table). Each rule has a name, a trigger, and a short rule body.

### CC-1 — Playback gate

**Trigger:** After any user answer that carries a non-obvious implication.

**Rule:** Before asking the next question, paraphrase the *implication* (not the answer). Form: "So — <implication>, meaning <consequence>. Right?" Wait for confirmation before moving on.

**Non-obvious implications include:**
- The answer narrows scope in a way the user may not have noticed
- The answer commits to a tradeoff (latency, infra cost, etc.)
- The answer assumes something about another part of the system
- The answer interacts with a constitution/ADR principle

**Does NOT trigger playback:**
- Direct factual answers to direct questions
- Confirming a recommendation

**Application:** especially aggressive during Phase 2.

### CC-2 — Contradiction watch

**Trigger:** Any time the user's most recent answer implies a different system than a prior answer.

**Rule:** Surface the contradiction explicitly and resolve before continuing. Format:

> "Earlier you said <X, which implies system A>; just now you said <Y, which implies system B>. These point at different designs — which is load-bearing?"

The agent does **not** guess which the user meant. Does **not** silently update one earlier answer. Resolving a contradiction is part of the answer-processing loop, not a new question.

**Common contradiction shapes:** real-time vs batch, single-user vs multi-tenant, stateless vs stateful, internal vs external users.

### CC-3 — Concrete-example invitation

**Trigger:** When two or more clarifying exchanges on the same dimension have not yielded a stated answer.

**Rule:** Switch from abstract to concrete. Ask the user to walk through one specific scenario, end to end. Example:

> "Let me try this differently — walk me through one concrete moment: a specific user, what they're doing right before they hit this, what they expect to happen, what they see."

**Distinct from Phase 2's F4:** F4 is preventative and runs once upfront; CC-3 is a reactive recovery tool when a Phase 3 dimension gets stuck on abstractions.

### CC-4 — Mid-conversation scope re-check

**Trigger:** The user adds independent functionality mid-discovery — language like "oh, and it should also…" or a new capability that doesn't extend an existing requirement.

**Rule:** Pause the current line of questioning and re-run Phase 1's scope check on the expanded request. Two outcomes:

- **Still one feature:** added functionality genuinely extends the same user journey or domain object. Continue with the added scope folded in.
- **Now multiple features:** apply Phase 1's decomposition recommendation: "What you're now describing is two independent features — [original] and [added]. I recommend specifying these separately. Want to capture [added] as a follow-up spec and stay focused on [original]?"

---

## Findings traceability

| Finding | Where addressed |
|---|---|
| F1 — No mid-conversation playback | CC-1 (Playback gate) |
| F2 — No probe for implicit/unsaid | Phase 2 framing probe (F1, F3) |
| F3 — Flat, generic dimensions | Phase 3 coverage rule + depth rule |
| F4 — No concrete-example prompt | Phase 2 F4 (preventative) + CC-3 (reactive) |
| F5 — No contradiction protocol | CC-2 (Contradiction watch) |
| F6 — No "what did you consider and reject?" | Phase 2 F2 (merged with F2 above) |
| F7 — No completeness signal | Phase 4 stop-and-summarize gate |
| F8 — Scope re-check is one-shot | CC-4 (Mid-conversation scope re-check) |
| F9 — Unstructured handoff to Stage 2 | Phase 4 structured handoff digest |

---

## Changes outside SKILL.md

Scope is deliberately narrow.

### `docs/sdd/pipeline.md` — Stage 1 section

Replace the "walks through (and skips dimensions already covered)" framing with the four-phase structure. Add one paragraph each on: the framing probe, the cross-cutting rules (by name, pointing at SKILL.md for full definitions), the stop-and-summarize gate, the structured handoff digest. Reposition the dimensions table from "walked through" to "coverage checklist verified before synthesis."

Expected size delta: ~30 lines → ~45-50 lines.

### `docs/sdd/skills.md` — skill entry

Update the one-line summary for `ss-sdd-discovering-requirements` to reflect the new shape:

> Drives the four-phase discovery conversation (context → framing probe → targeted coverage walk → synthesis), produces a structured handoff digest for spec-writing.

### `README.md` — Skills section entry

Same treatment: update the existing one-liner to match. Per CLAUDE.md, the README entry must be kept current when the skill changes.

### Explicitly NOT touched

- `ss-sdd-coordinator/SKILL.md` — Stage 1 description is a single sentence; no edit needed.
- `ss-sdd-grilling-specs/SKILL.md` — separate optional stage with different mission. Leave alone.
- `ss-sdd-writing-specs/SKILL.md` — consumes the new handoff digest, but the digest is designed to map onto the existing spec format. An explicit "Consuming the discovery digest" subsection is a follow-up if proven needed in practice; not in scope here.
- `ss-sdd-receiving-review-findings`, `framework/` scripts, state schema — discovery doesn't interact with these.
- `.sublime-skills/config.yml` schema — no new keys. Framing probe is mandatory, coverage rule is mandatory.

---

## Commit grouping

When implementation lands, suggest two commits:

1. `feat(ss-sdd-discovering-requirements): four-phase structure + framing probe + cross-cutting rules` — the SKILL.md rewrite, single commit.
2. `docs(sdd): align pipeline.md, skills.md, README.md with new discovery shape` — the narrative updates.

Keeps the operational change and the documentation sync clearly separated in history.

---

## Risks and tradeoffs

- **Discovery length.** Adding the framing probe in absolute terms lengthens discovery for simple features. Mitigation: skip conditions are explicit and narrow; trivial features get one-line answers per dimension; the stop gate refuses extra drilling once coverage is met. Net length should be similar to today for simple features (framing probe replaces shallow dimension questions that would have been asked anyway) and longer only for genuinely under-specified features (which is the case we want it to be longer for).
- **Skill size.** SKILL.md grows from ~184 lines to an estimated ~280-320 lines. Acceptable given the skill is the operational spec for the most context-sensitive stage in the pipeline.
- **Agent compliance with new rules.** Cross-cutting rules are named, triggered, and short — that's what makes them enforceable rather than aspirational. If an agent skips them anyway, the section-by-section approval gate in Phase 4 surfaces the gap (since framing-driver one-liners would be missing or hollow).
- **Drift between SKILL.md and pipeline.md narrative.** Mitigated by committing both updates in the same PR (two commits, one PR) and including the cross-cutting rules section in the narrative summary.
