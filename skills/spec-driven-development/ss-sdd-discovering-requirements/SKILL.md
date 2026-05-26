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

## Phase 4 — Synthesis

Four sub-steps, in order: stop-gate self-check, section-by-section approval, final confirmation, structured end-of-stage summary.

### 4.1 — Stop-and-summarize gate

Before summarizing back to the user, run this self-check:

> Can I, right now, write a single paragraph that names: (a) who the primary user is, (b) what triggers them to use this, (c) what success looks like for them, and (d) the top 3 ways this could go wrong?
>
> If yes — proceed to Step 4.2.
> If no — return to Phase 3 and drill the missing dimension(s). Do not summarize.

A second sub-check runs alongside: every dimension from Phase 3 must have its stated answer (or signal-cited N/A) in your in-memory understanding. If any dimension is still in a "we'll figure it out" state, that's a return-to-Phase-3 signal regardless of the paragraph check.

This gate replaces the prior version's softer "Stop when you have enough" guidance.

### 4.2 — Section-by-section approval

Summarize back to the user in sections. Get explicit approval after each section before moving to the next. Cover (in order):

1. **Goal & problem** — one paragraph
2. **Users & their flows** — list of user stories with priorities (P1/P2/P3)
3. **Scope** — in-scope bullets, out-of-scope bullets
4. **Success criteria** — measurable outcomes
5. **Key entities** — only if data is involved
6. **Edge cases & constraints** — explicit list
7. **Major decisions** — what was chosen and why (these become ADR candidates at Stage 6)

**Section format scales to complexity.** A few sentences if straightforward, up to ~200–300 words if nuanced.

**Frame the goal section with its driver inline.** When presenting "Goal & problem," include the F1 driver (and the F3 substitute behavior, when load-bearing) as a brief parenthetical at the top of the section. Example:

> **Goal & problem.** *(Driver from Phase 2 F1: customer success spends ~5 hrs/week on manual exports; substitute today is copy-paste into a spreadsheet.)* This feature gives CS reps a self-serve export panel so they can…
>
> Does this match your intent?

This makes it cheap for the user to spot if your framing-probe interpretation drifted.

After each section ask: "Does this match your intent?" If the user pushes back on any section, revise and re-confirm. Don't move on.

### 4.3 — Final confirmation

When all sections are approved, say:

> "Alright, here's the shared understanding we're going to spec out:
>
> [the one-paragraph summary from the stop-gate self-check]
>
> Ready to write this up?"

Wait for explicit confirmation.

### 4.4 — Structured end-of-stage summary

Return control to the coordinator with the following **fixed-shape structured summary** in your final message. The structure is for *your own self-discipline* (forces every dimension to be actually stated) and for *coordinator state cleanliness*; it is NOT a parse contract with `ss-sdd-writing-specs`. No new file is written — the summary lives in the conversation, exactly where the prior version's free-form bullet list lived.

Use this exact template, filling in every field. Use `N/A — <signal>` for fields that genuinely don't apply, citing a Phase 1 or Phase 2 signal:

```
=== DISCOVERY SUMMARY ===
short_name: <kebab-case>
work_type: feature | fix

framing:
  driver:               <one sentence — answer to F1 (timing/trigger), or "N/A — F1 skipped because <reason>">
  alternatives:         <list of alternatives considered + why rejected, OR
                        "user did not consider; agent proposed X/Y/Z; user chose <pick>">
  substitute_behavior:  <one sentence — answer to F3 (what user does without it), or "N/A — F3 skipped because <reason>">
  walkthrough:          <one short paragraph — answer to F4>

dimensions:
  purpose:     <stated answer | N/A: <signal>>
  users:       <stated answer | N/A: <signal>>
  scope_in:    <bullet list>
  scope_out:   <bullet list>
  success:     <stated answer with measurable outcome | N/A: <signal>>
  entities:    <stated answer | N/A: <signal>>
  edge_cases:  <bullet list of top failure modes>
  constraints: <stated answer | N/A: <signal>>
  integration: <stated answer | N/A: <signal>>

major_decisions:    # ADR candidates — including any decisions resolved at F2
  - title:    <short title>
    chosen:   <chosen option>
    rejected: [<option 1>, <option 2>]
    reasoning: <one to two sentences>

open_questions:     # from Phase 3 §3.4 graceful-unknown protocol
  - question: <what's open>
    default:  <reasonable default agent proposed>
    disposition: accepted_default | deferred_to_assumptions | deferred_to_followup_spec

approved_sections: [goal, users, scope, success, entities, edge_cases, decisions]
=== END SUMMARY ===
```

### How the coordinator uses each field

No new dispatch parameters are introduced; the summary populates existing in-memory carry and existing dispatch parameters.

| Summary field | Coordinator action (unchanged contracts) |
|---|---|
| `short_name`, `work_type` | Passed to `ss-sdd-writing-specs` (Stage 2), which persists them into the state file. |
| `framing.*` | Carried in coordinator's in-memory context. Stage 2 receives the same in-memory understanding it does today (now slightly richer); Stage 2's prerogative how it uses framing material in the spec's Goal/Problem section. |
| `dimensions.*` | Same as today — coordinator's in-memory understanding of the agreed content, passed to Stage 2. |
| `major_decisions` | Populates the existing `DECISIONS_CAPTURED` dispatch parameter the coordinator already passes to `ss-sdd-maintaining-adrs` (Stage 6). Today free-form; now shape (title/chosen/rejected/reasoning). Stage 6's contract is unchanged. |
| `open_questions` | Coordinator's choice: either include in the in-memory understanding passed to Stage 2 (so the writer can route them into the spec's Open Questions / Assumptions sections per the existing spec format), or surface to the user for resolution before Stage 2. No new dispatch parameter. |
| `approved_sections` | Confirmation marker. Used only as evidence that Phase 4 ran to completion. |

## Cross-cutting rules

Four rules apply throughout Phases 2–4. Each has a name, a trigger, and a short rule body. Apply them as their triggers fire — they aren't sequential steps.

### CC-1 — Playback gate

**Trigger:** after any user answer that carries a non-obvious implication.

**Rule:** before asking the next question, paraphrase the *implication* (not just the answer). Form: "So — <implication>, meaning <consequence>. Right?" Wait for confirmation before moving on.

**Non-obvious implications include:**
- The answer narrows scope in a way the user may not have noticed (e.g., "exports only" → implies no import path)
- The answer commits to a tradeoff (latency, infra cost, etc.)
- The answer assumes something about another part of the system
- The answer interacts with a constitution/ADR principle

**Does NOT trigger playback:**
- Direct factual answers to direct questions ("Are there multiple roles?" / "Just admins.") — nothing to paraphrase
- Confirming a recommendation ("yes, A") — the recommendation already stated the implication

**Application:** especially aggressive during Phase 2. Framing answers reshape the entire feature; a misread framing answer is the most expensive miss in discovery.

### CC-2 — Contradiction watch

**Trigger:** any time the user's most recent answer implies a different system than a prior answer.

**Rule:** surface the contradiction explicitly and resolve before continuing. Format:

> "Earlier you said <X, which implies system A>; just now you said <Y, which implies system B>. These point at different designs — which is load-bearing?"

You do NOT guess which the user meant. You do NOT silently update one earlier answer to match the latest. Resolving a contradiction is part of the answer-processing loop, not a new question against any budget.

**Common contradiction shapes:** real-time vs batch, single-user vs multi-tenant, stateless vs stateful, internal vs external users.

### CC-3 — Adjacent-scenario invitation

**Trigger:** when two or more clarifying exchanges on the same Phase 3 dimension have not yielded a stated answer.

**Rule:** switch from abstract to concrete by asking for a scenario **adjacent to, but distinct from**, the F4 walkthrough already on the table. The new scenario must vary at least one axis: a different user role, a different trigger, an edge case the F4 scenario didn't cover, or a failure path. You MUST reference F4 explicitly so the user doesn't experience it as your forgetting:

> "You already walked me through <F4 scenario summary>. Let me try one that's adjacent — what if the user were <different role>, or it happened <different trigger>, or <something failed>? Walk me through that one."

**Distinct from Phase 2's F4:** F4 is preventative, runs once upfront, and establishes the baseline scenario. CC-3 is a reactive recovery tool *only* when a Phase 3 dimension is stuck on abstractions, and it must produce a *different* scenario than F4. Re-asking F4 verbatim is forbidden.

**Skip condition:** if you cannot identify an adjacent scenario meaningfully distinct from F4 (rare; usually means the feature is genuinely narrow), fall back to other CC rules and the §3.4 graceful-unknown protocol; do not fire CC-3 just because the trigger condition was met.

### CC-4 — Mid-conversation scope re-check

**Trigger:** the user adds independent functionality mid-discovery — language like "oh, and it should also…" or "while we're at it, can it also…" or a new capability that doesn't extend an existing requirement.

**Rule:** pause the current line of questioning and re-run Phase 1's scope check (§1.2) on the expanded request. Two outcomes:

- **Still one feature:** added functionality genuinely extends the same user journey or domain object. Continue discovery with the added scope folded in.
- **Now multiple features:** apply Phase 1's decomposition recommendation:
  > "What you're now describing is two independent features — [original] and [added]. I recommend specifying these separately. Want to capture [added] as a follow-up spec and stay focused on [original]?"

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the scope check at Phase 1 §1.2 | Always do it; saves work on misaligned features |
| Skipping a framing probe (F1–F4) without an explicit narrow skip condition | Ask the probe; "I think I can guess" is not a skip condition |
| Asking open-ended when MCQ would work (Phase 3 dimensions) | Format as A/B/C with a recommendation; users decide faster |
| Combining questions ("what's the scope AND who uses it?") | Split, always |
| Forgetting CC-1 playback after a non-obvious answer | Paraphrase the implication before the next question |
| Re-asking what an existing ADR already decided | Cite the ADR; move on |
| Writing free-form `N/A — doesn't apply` for a dimension | Cite a Phase 1 or Phase 2 signal (e.g., `N/A — F4 walkthrough involved no persistent data`) |
| Re-proposing a fork already resolved at F2 | F2-resolved decisions are tagged as ADR candidates; cite the F2 outcome |
| Firing CC-3 with the F4 scenario verbatim | CC-3 requires an *adjacent* scenario — different user / trigger / edge case |
| Advancing past the §4.1 stop-gate without being able to write the user/trigger/success/failure paragraph | Return to Phase 3 and drill the missing dimension(s) |
| Returning a free-form bullet list instead of the §4.4 structured summary | Use the exact template; every field must be filled |

## Red Flags

- About to start asking the user clarifying questions without having read the project's constitution + ADRs (when present) → STOP; you'll either re-ask settled questions or steer the user toward decisions that violate stated principles
- About to skip a framing probe (F1–F4) for any reason other than the explicit narrow skip conditions in Phase 2 → STOP
- About to advance to Phase 4 with any dimension still in a "we'll figure it out" state → STOP; return to Phase 3
- About to summarize but cannot write the §4.1 paragraph (user / trigger / success / top-3 failures) → STOP; return to Phase 3
- Two user answers point at different systems and you're about to silently pick one → CC-2 fires; surface and ask
- User just added "oh and also…" — independent functionality → CC-4 fires; re-run the scope check before continuing
- About to write `spec.md` already → STOP; that's Stage 2
- About to propose a design decision that contradicts an existing ADR without flagging it → flag explicitly, get user buy-in to override
- About to ask a 10th question on the same dimension → step back; either you don't have enough context to know what to ask, or you're overthinking it (consider CC-3 or the §3.4 graceful-unknown protocol)
