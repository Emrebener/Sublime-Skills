---
name: ss-sdd-discovering-requirements
description: Use during the discovery stage of an SDD pipeline run, after ss-sdd-preflight and before ss-sdd-writing-specs. Drives a four-phase interactive conversation (context → framing probe → targeted coverage walk → synthesis) and produces a structured end-of-stage summary for the coordinator. No artifacts are written to disk in this stage.
---

# Discovering Requirements

## Overview

Turn a rough idea into a shared, complete understanding through conversation. This stage produces no files on disk — only alignment. The agent's final message to the coordinator is a fixed-shape structured summary (Step 4.4); the `ss-sdd-writing-specs` skill turns that alignment into the spec document at the next stage.

Discovery runs in **four phases**:
- **Phase 1 — Context:** load project conventions, scope-check, classify work type.
- **Phase 2 — Framing probe:** four fixed probes (F1–F4) that surface the implicit before requirements gathering.
- **Phase 3 — Targeted dimension walk:** ensure every dimension of the 9-dimension coverage checklist ends with a stated answer.
- **Phase 4 — Synthesis:** stop-and-summarize gate, section-by-section approval, structured end-of-stage summary.

Four **cross-cutting rules** apply throughout Phases 2–4: CC-1 playback gate, CC-2 contradiction watch, CC-3 adjacent-scenario invitation, CC-4 mid-conversation scope re-check.

**Core principle:** One question at a time. Multiple choice with a recommended answer where applicable. Surface decisions before the user has to ask. Paraphrase non-obvious implications back; let the user confirm or correct before moving on.

**Announce at start:** "I'm using the ss-sdd-discovering-requirements skill to align on what we're building."

## Hard Gates

- Do NOT write any spec, plan, or implementation artifact to disk in this stage. The terminal state of this skill is "user has approved a shared understanding"; the agent's final message to the coordinator is the structured end-of-stage summary (Step 4.4), which lives in conversation, not on disk.
- Do NOT propose more than one question per message. Even when topics relate, split them.
- Do NOT proceed past a section the user hasn't approved.
- Do NOT skip a framing probe (F1–F4) for any reason other than the narrow, explicit skip conditions listed in Phase 2.
- Do NOT advance to Phase 4 synthesis without every Phase 3 dimension having a stated answer — a sentence or two, or an explicit `N/A — <Phase 1 or Phase 2 signal>`. Free-form `N/A — doesn't apply` is rejected.
- Do NOT pass the Phase 4 stop-and-summarize self-check if you cannot, right now, write a single paragraph naming (a) the primary user, (b) their trigger, (c) what success looks like, and (d) the top 3 ways the feature can fail. If you can't, return to Phase 3 and drill the missing dimension(s).

## Checklist

The coordinator MUST track each of these as a todo item and complete them in order:

**Phase 1 — Context**
1. Load project context (script + read found files)
2. Scope check — is this one feature or several? Decompose if needed.
3. Determine work type (`feature` or `fix`)

**Phase 2 — Framing probe**
4. Ask F1 (Driver / timing)
5. Ask F2 (Alternatives considered) — invoke forcing function if user considered none
6. Ask F3 (Substitute behavior)
7. Ask F4 (Concrete walkthrough)

**Phase 3 — Targeted dimension walk**
8. Cover every dimension in the 9-dimension table with a stated answer (or signal-cited N/A)
9. Propose 2–3 approaches for any non-obvious major decision; tag the chosen decision as an ADR candidate

**Phase 4 — Synthesis**
10. Pass the stop-and-summarize self-check
11. Present the shared understanding in sections; get section-by-section approval
12. Confirm the final understanding with the user
13. Return the structured end-of-stage summary to the coordinator

Apply cross-cutting rules (CC-1, CC-2, CC-3, CC-4) throughout Phases 2–4 as their triggers fire.

Individual probes in Phase 2 may be skipped only under the narrow conditions listed in that section; no other shortcut is permitted.

## Phase 1 — Context

Three sub-steps. Behavior is unchanged from the prior Steps 1–3; only the grouping name changes.

### 1.1 — Load project context

Run the shared discovery script and read the relevant files via the harness's read mechanism. The output tells you which files exist; only read what's present.

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/discover-context.sh
```

Read these if present:
- `constitution` — non-negotiable project principles; the spec must comply.
- `architecture` — overall structure; helps situate where the feature fits.
- `glossary` / `domain` — domain vocabulary you should use.
- All `adrs` — prior decisions you should respect, not re-litigate.
- `readme` — fallback for high-level project understanding.

The discovery script already resolves `context.<name>_path` values from `.sublime-skills/config.yml` and verifies the files exist before returning them, so the output JSON's `constitution` / `architecture` / `glossary` / etc. fields can be consumed directly. A `null` field means the project didn't configure (or doesn't have) that artifact.

**Skip files that don't exist.** Context is optional — features can be specced without any of these.

### 1.2 — Scope check

Before any clarifying questions, assess whether the request is one feature or multiple. Signals it's too big:

- Mentions multiple distinct subsystems (chat + billing + analytics + admin)
- Describes a "platform" rather than a feature
- The user's description spans more than ~3 sentences of independent functionality

If too big, surface immediately:

> "This describes [N] independent subsystems: [list]. I recommend splitting these into separate SDD runs — each spec → plan → implementation cycle stays clean that way. Want to start with [subsystem 1] now? We can capture the rest as follow-up specs."

If the user pushes back, accept their judgment but note the risk: "I'll proceed, but if the spec gets unwieldy I'll suggest the split again."

Note: this is the initial scope check. CC-4 (mid-conversation scope re-check) re-runs this same check during Phases 2–3 if the user adds independent functionality.

### 1.3 — Determine work type

Classify the work as either `feature` (something new being built) or `fix` (a defect in existing behavior being corrected). This is recorded in the state file at Stage 2 and used by `ss-sdd-choosing-feature-branch` (Stage 12) to suggest a branch prefix (`feat/` vs `fix/`).

**Inference rule:** if the user's initial input contains clear bug-fix signals — verbs like "fix", "broken", "regression", "bug", or framings like "X used to work but now…" — classify as `fix`. Otherwise default to `feature`.

If genuinely ambiguous (e.g., "improve the login flow" could be either a UX feature or a UX bug fix), ask once via the harness's interactive question tool:

> Is this a new feature, or a fix to existing behavior?

Record the classification in your in-memory output. Do not labor on this — it's a single bit that only affects the suggested branch name.

## Phase 2 — Framing probe

Runs after Phase 1, before Phase 3 (the dimension walk). Purpose: surface what the user isn't saying — implicit drivers, assumptions, alternatives — before requirements gathering locks the framing in.

Four fixed probes, asked in order. Each can be **skipped only when the user's initial input already answered it unambiguously** — no other shortcut.

### The probes

| # | Probe | What it surfaces |
|---|---|---|
| F1 | **Driver / timing.** "What's prompting this now — what changed, what deadline or incident is in play, or is something blocking other work?" | Underlying driver. Distinguishes "nice-to-have we keep deferring" from "load-bearing for Q3 launch." Strictly about *why now*, not stakes. |
| F2 | **Alternatives considered.** "What other approaches did you consider, and what made you land here?" | Whether the user has filtered options or is treating the first idea as the only idea. If they say "I didn't consider any," the **forcing function** fires (see below). |
| F3 | **Substitute behavior.** "If we don't build this, what does the affected user do instead — workaround, suffer, leave?" | What the user does in absence of the feature. Distinct from F1 (timing); this is purely about the substitute. If the answer is "nothing, they just live with it," that's a strong signal to deprioritize or rescope. |
| F4 | **Concrete walkthrough.** "Walk me through one real scenario, start to finish — a specific user, a specific moment, what they do and what they expect to happen." | Forces commitment to specifics. Catches abstract framings that hide unanswered questions. Establishes the baseline scenario that Phase 3 and CC-3 build on. |

### Protocol

- **One probe per message.** No combining.
- **No recommendations on framing probes.** Framing answers come from the user; you have no basis to recommend "why now."
- **Each answer is logged in your in-memory understanding** — not written to disk (the no-artifacts hard gate applies).
- **Apply CC-1 (playback gate) aggressively here.** Framing answers are where misunderstanding is cheapest to catch and most expensive to leave.
- **F2 forcing function.** If the user says they didn't consider alternatives, you MUST propose 2–3 before continuing to F3. Any decision the user resolves at F2 is **immediately tagged as an ADR candidate** in your in-memory understanding (same treatment as a major decision surfaced in Phase 3 §3.3). Phase 3 will not re-propose the same fork.
- **F4 is the bridge to Phase 3.** The concrete walkthrough naturally exposes which dimensions matter most for this feature.

### Skip conditions (explicit, narrow)

A probe is skipped only when:

| Probe | Skip only when |
|---|---|
| F1 | The user's initial input contained an explicit driver/timing framing (deadline, incident, blocker for other work) |
| F2 | The user's initial input named alternatives they rejected |
| F3 | The user's initial input explicitly stated what users currently do without the feature (workaround/suffer/leave) |
| F4 | The user's initial input *already was* a concrete scenario with specific users and specific actions |

"I think I can guess" is not a valid skip condition. When skipping, record the skip reason in your in-memory understanding so the Phase 4 summary can cite it.

### Non-overlap with Phase 3

The framing probe does NOT replace the Purpose dimension in Phase 3. The probe surfaces *why* and *what's behind the ask*; the Purpose dimension pins down the problem statement for the spec. They feed each other.

## Phase 3 — Targeted dimension walk

The heart of discovery — where the spec's content is shaped. The 9-dimension table from the prior version of this skill is preserved verbatim, but its role shifts from *script* to *coverage checklist*.

### 3.1 — The coverage rule

Every dimension below must end Phase 3 with a **stated answer** — a sentence or two you can recite. A dimension that genuinely doesn't apply ends with an explicit `N/A — <one-line reason citing a Phase 1 or Phase 2 signal>` statement. **The cited signal is mandatory.** Free-form `N/A — doesn't apply here` is rejected.

Examples of well-formed N/A:
- `N/A — F4 walkthrough involved no persistent data`
- `N/A — constitution forbids external integrations for this layer`
- `N/A — F3 substitute behavior is purely manual; no integration surface`

There is no third option — no "skipped," no "we'll get to it." The Phase 4 stop gate (§4.1) verifies this rule.

| Dimension | What "stated answer" looks like |
|---|---|
| Purpose | One sentence naming the problem and who feels it |
| Users | Named roles (or "single role: X") + the trigger that brings each to the feature |
| Scope (in) | Bullet list of the smallest valuable slice |
| Scope (out) | Explicit deferred items |
| Success | At least one measurable outcome (number, threshold, observable behavior) |
| Key entities | Named entities with attributes, or explicit `N/A — <signal>` |
| Edge cases | At least the top 3 failure modes |
| Constraints | Named constraints (tech/perf/security/compliance) or explicit `N/A — <signal>` |
| Integration | External dependencies named with failure modes, or explicit `N/A — <signal>` |

The "Sample question" column from the prior version of this skill is gone. Question wording is **guidance, not script** — pick what fits the conversation, drawing on framing-probe answers and project context.

### 3.2 — Depth rule

Depth per dimension is driven by signals from Phase 1 and Phase 2, not by a fixed quota. Drill **deeper** when:

- **Phase 2's F4 walkthrough** exposed a specific ambiguity in that dimension (e.g., the walkthrough revealed two user roles where only one was implied → drill Users)
- **Phase 1 context** (constitution / ADRs) implies non-trivial constraints on that dimension
- **Risk-weight** is high: data-handling dimensions for features touching user data, integration dimensions when the feature crosses a service boundary, edge cases when the framing implied real-time or financial behavior

Drill **shallower** (one question, often answered from context alone) when:

- The dimension is trivially settled by Phase 1 + Phase 2 answers
- The user's initial input already specified it concretely
- A prior ADR settles it — cite the ADR and record the stated answer with the ADR reference

There is **no fixed cap on questions per dimension.** The cap is implicit: the Phase 4 stop gate refuses to advance until every dimension has a stated answer, and the cross-cutting rules (no repeating, no asking-twice-worded-differently) prevent over-drilling.

### 3.3 — Major decisions sub-step

For any non-obvious major design decision (e.g., "JWT vs session cookies", "REST vs WebSocket", "synchronous vs queued processing"), propose **2–3 alternatives** with:

- Description (1–2 sentences each)
- Trade-offs (what you gain, what you give up)
- **Your recommended choice with reasoning**

Lead with the recommendation. If prior ADRs already settled this kind of decision, cite the ADR and proceed without re-asking.

Example:

> "For auth, three reasonable approaches:
>
> **A) JWT (recommended)** — stateless, scales horizontally, no session store needed. Trade-off: revocation is awkward; we'd need a blocklist.
>
> **B) Server-side sessions** — easy revocation, simple model. Trade-off: needs a session store (Redis-ish) and breaks horizontal scaling without sticky sessions.
>
> **C) OAuth2 with an external provider** — offloads identity entirely. Trade-off: external dependency, extra latency on login.
>
> Recommended A because [project-specific reasoning]. Sound right?"

**Any decision resolved here is tagged as an ADR candidate** in your in-memory understanding (title / chosen / rejected options / reasoning). Phase 4's structured summary serializes these for the coordinator to feed into Stage 6's `DECISIONS_CAPTURED` dispatch parameter.

**Do not re-propose decisions already resolved at Phase 2 F2** — they were already tagged as ADR candidates and the user already chose. Cite the F2 outcome and move on.

### 3.4 — Graceful-unknown protocol

If you cannot state an answer for a dimension after a reasonable amount of drilling, surface explicitly as an **Open Question**. Propose a reasonable default. Let the user choose:

- **(a) Accept the default** — the stated answer for that dimension is the default; record `disposition: accepted_default` for the Phase 4 summary.
- **(b) Defer to spec Assumptions** — `disposition: deferred_to_assumptions`; the stated answer is "open; default <X> proposed, user opted to defer to the spec's Assumptions section."
- **(c) Defer to a follow-up spec** — `disposition: deferred_to_followup_spec`; the dimension's stated answer references the deferral.

In all three cases the dimension exits Phase 3 with a stated answer (the open question itself counts, since it includes the disposition and the default). This is the only recovery mechanism for a genuinely-unresolved dimension; without it, the Phase 4 stop gate would loop indefinitely.

## Step 6: Present Shared Understanding in Sections

Once the conversation has covered enough ground, summarize back to the user in sections. Get explicit approval after each section before moving to the next. Cover (in order):

1. **Goal & problem** — one paragraph
2. **Users & their flows** — list of user stories with priorities (P1/P2/P3)
3. **Scope** — in-scope bullets, out-of-scope bullets
4. **Success criteria** — measurable outcomes
5. **Key entities** — only if data is involved
6. **Edge cases & constraints** — explicit list
7. **Major decisions** — what was chosen and why (these become ADR candidates later)

**Section format:** scaled to complexity. A few sentences if straightforward, up to ~200-300 words if nuanced. After each section ask: "Does this match your intent?"

If the user pushes back on any section, revise and re-confirm. Don't move on.

## Step 7: Final Confirmation

When all sections are approved, say:

> "Alright, here's the shared understanding we're going to spec out:
>
> [one-paragraph summary]
>
> Ready to write this up?"

Wait for explicit confirmation.

## Step 8: Hand Off

After confirmation, return control to the coordinator with:

```
Discovery complete.
- Short name: <kebab-case>
- Work type: feature | fix
- Approved sections: goal, users, scope, success, entities, edge_cases, decisions
- Major decisions captured: [list, to become ADR candidates later]
- Out-of-scope explicit: [list]
```

The coordinator will invoke `ss-sdd-writing-specs` next.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the scope check | Always do it; saves work on misaligned features |
| Asking open-ended when MCQ would work | Format as A/B/C with a recommendation; users decide faster |
| Combining questions ("what's the scope AND who uses it?") | Split, always |
| Writing partial spec content during this stage | This is discovery-only; `ss-sdd-writing-specs` handles the artifact |
| Re-asking what an existing ADR already decided | Cite the ADR; move on |
| Driving the conversation past the point where you have enough | When you can summarize confidently, summarize and stop |

## Red Flags

- About to start asking the user clarifying questions without having Read the project's constitution + ADRs (when present) → STOP; you'll either re-ask settled questions or steer the user toward decisions that violate stated principles
- Felt the urge to write `spec.md` already → stop; that's the next stage
- About to propose a design decision that contradicts an existing ADR without flagging it → flag it explicitly, get user buy-in to override
- About to ask a 10th question on the same dimension → step back; either you don't have enough context to know what to ask, or you're overthinking it
