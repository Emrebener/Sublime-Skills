---
name: discovering-requirements
description: Use during the discovery stage of an SDD pipeline run, after preflight-checks and before writing-specs. Drives an interactive conversation with the user to reach a shared understanding of what's being built — purpose, scope, users, success criteria, key decisions — without writing any artifacts yet.
---

# Discovering Requirements

## Overview

Turn a rough idea into a shared, complete understanding through conversation. This stage produces no files — only alignment. The `writing-specs` skill turns that alignment into the spec document afterward.

**Core principle:** One question at a time. Multiple choice with a recommended answer where possible. Surface decisions before the user has to ask.

**Announce at start:** "I'm using the discovering-requirements skill to align on what we're building."

## Hard Gates

- Do NOT write any spec, plan, or implementation artifact in this stage. The terminal state of this skill is "user has approved a shared understanding" — handing off to `writing-specs` is the next stage.
- Do NOT propose more than one question per message. Even when topics relate, split them.
- Do NOT proceed past a section the user hasn't approved.

## Checklist

The coordinator MUST track each of these as a todo item and complete them in order:

1. Load project context (script + Read found files)
2. Scope check — is this one feature or several? Decompose if needed.
3. Conversational discovery, one question at a time
4. Propose 2-3 approaches for any non-obvious major decision
5. Present the shared understanding in sections; get section-by-section approval
6. Confirm final understanding with the user
7. Hand off to `writing-specs`

## Step 1: Load Project Context

Run the shared discovery script and Read the relevant files. The output tells you which files exist; only Read what's present.

```bash
./spec-driven-development/scripts/discover-context.sh
```

Read these if present:
- `constitution` — non-negotiable project principles; spec must comply
- `architecture` — overall structure; helps situate where the feature fits
- `glossary` / `domain` — domain vocabulary you should use
- All `adrs` — prior decisions you should respect, not re-litigate
- `readme` — fallback for high-level project understanding

The discovery script already resolves `context.<name>_path` values from `.sublime-skills/config.yml` and verifies the files exist before returning them, so the output JSON's `constitution` / `architecture` / `glossary` / etc. fields can be consumed directly. A `null` field means the project didn't configure (or doesn't have) that artifact.

**Skip files that don't exist.** Context is optional — features can be specced without any of these.

## Step 2: Scope Check

Before any clarifying questions, assess whether the request is one feature or multiple. Signals it's too big:

- Mentions multiple distinct subsystems (chat + billing + analytics + admin)
- Describes a "platform" rather than a feature
- The user's description spans more than ~3 sentences of independent functionality

If too big, surface immediately:

> "This describes [N] independent subsystems: [list]. I recommend splitting these into separate SDD runs — each spec → plan → implementation cycle stays clean that way. Want to start with [subsystem 1] now? We can capture the rest as follow-up specs."

If the user pushes back, accept their judgment but note the risk: "I'll proceed, but if the spec gets unwieldy I'll suggest the split again."

## Step 3: Conversational Discovery

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
- Honor the project context — if `constitution.md` says "all APIs must use OAuth2", don't ask "which auth method?"
- Skip dimensions that are obviously not applicable (e.g., "key entities" for a config-only feature)
- Stop when you have enough to write a spec — overly thorough discovery is friction

## Step 4: Propose Approaches for Major Decisions

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

## Step 5: Present Shared Understanding in Sections

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

## Step 6: Final Confirmation

When all sections are approved, say:

> "Alright, here's the shared understanding we're going to spec out:
>
> [one-paragraph summary]
>
> Ready to write this up?"

Wait for explicit confirmation.

## Step 7: Hand Off

After confirmation, return control to the coordinator with:

```
Discovery complete.
- Short name: <kebab-case>
- Approved sections: goal, users, scope, success, entities, edge_cases, decisions
- Major decisions captured: [list, to become ADR candidates later]
- Out-of-scope explicit: [list]
```

The coordinator will invoke `writing-specs` next.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping the scope check | Always do it; saves work on misaligned features |
| Asking open-ended when MCQ would work | Format as A/B/C with a recommendation; users decide faster |
| Combining questions ("what's the scope AND who uses it?") | Split, always |
| Writing partial spec content during this stage | This is discovery-only; `writing-specs` handles the artifact |
| Re-asking what an existing ADR already decided | Cite the ADR; move on |
| Driving the conversation past the point where you have enough | When you can summarize confidently, summarize and stop |

## Red Flags

- About to start asking the user clarifying questions without having Read the project's constitution + ADRs (when present) → STOP; you'll either re-ask settled questions or steer the user toward decisions that violate stated principles
- Felt the urge to write `spec.md` already → stop; that's the next stage
- About to propose a design decision that contradicts an existing ADR without flagging it → flag it explicitly, get user buy-in to override
- About to ask a 10th question on the same dimension → step back; either you don't have enough context to know what to ask, or you're overthinking it
