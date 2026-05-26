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

## Step 4: Conversational Discovery

Walk through these dimensions (in roughly this order, skipping any that are already clear from the user's description):

| Dimension | Sample question |
|---|---|
| Purpose | "What problem is this solving? Who's currently feeling that pain?" |
| Users | "Who interacts with this? Are there multiple roles?" |
| Scope (in) | "What's the smallest version that delivers value?" |
| Scope (out) | "Anything you want to explicitly leave out for later?" |
| Success | "How will we know it's working? What's measurable?" |
| Key entities | "What are the main objects/records involved?" |
| Edge cases | "What happens when [boundary condition]?" |
| Constraints | "Any tech-stack, performance, security, or compliance constraints?" |
| Integration | "Does this need to talk to other systems or APIs?" |

**Rules:**
- One question at a time
- Prefer multiple choice with a recommended answer (e.g., "A) ... [recommended because ...] B) ... C) ...") over open-ended when the choice has clear alternatives
- Honor the project context — if `CONSTITUTION.md` says "all APIs must use OAuth2", don't ask "which auth method?"
- Skip dimensions that are obviously not applicable (e.g., "key entities" for a config-only feature)
- Stop when you have enough to write a spec — overly thorough discovery is friction

## Step 5: Propose Approaches for Major Decisions

For any non-obvious major design decision (e.g., "JWT vs session cookies", "REST vs WebSocket", "synchronous vs queued processing"), propose **2-3 alternatives** with:
- Description (1-2 sentences each)
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
