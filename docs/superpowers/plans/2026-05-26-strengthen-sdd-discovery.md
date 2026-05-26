# Strengthening SDD Discovery (Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `ss-sdd-discovering-requirements/SKILL.md` from 8 linear steps into 4 named phases with a mandatory framing probe (F1–F4), a coverage-checklist dimension walk, four cross-cutting rules (CC-1 playback / CC-2 contradiction / CC-3 adjacent-scenario / CC-4 scope re-check), a Phase 4 stop-and-summarize gate, and a structured end-of-stage summary to the coordinator. Sync `docs/sdd/pipeline.md` (Stage 1), `docs/sdd/skills.md` (skill entry), and `README.md` (Skills section) to match.

**Architecture:** Pure documentation/prose change. The SKILL.md is the operational artifact; the docs/ files and README are downstream narrative. No code, no tests, no scripts, no config, no state-file schema touched. The skill's existing contract is preserved: no Stage 1 artifacts on disk, coordinator carries in-memory understanding, existing dispatch parameters (e.g., `DECISIONS_CAPTURED` for Stage 6) are unchanged.

**Tech Stack:** Markdown only.

**Design reference:** `docs/superpowers/specs/2026-05-26-strengthen-sdd-discovery-design.md`. The design doc is the source of truth for *why*; this plan is the source of truth for *what to do and in what order*. Where this plan and the design doc disagree on content, **this plan wins** (it embeds the final approved wording).

---

## File Structure

Files modified:

| Path | Edit scope | Tasks |
|---|---|---|
| `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` | Heavy rewrite — frontmatter, overview, hard gates, checklist, replace 8 Steps with 4 Phases + cross-cutting subsection, update Common Mistakes and Red Flags | 1–7 |
| `docs/sdd/pipeline.md` | Stage 1 section narrative update (lines ~86–119) | 8 |
| `docs/sdd/skills.md` | One skill entry (lines ~127–155) | 9 |
| `README.md` | One skill entry (lines ~220–229) | 10 |

No files created. No files deleted. No file moves.

**Commit strategy:** one commit per task, ten commits total. The design doc's recommendation of "two logical commits" is relaxed in implementation in favor of granular history (recovery is cheaper if a task needs to be rolled back individually). The two-commit grouping can be reconstructed post-merge if desired via interactive rebase, but is not required.

---

## Task 1 — SKILL.md: frontmatter, Overview, Hard Gates, Checklist

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (top of file through and including `## Checklist`)

- [ ] **Step 1: Read the current file to confirm starting state.**

  Run: `wc -l skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: `183 skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`

- [ ] **Step 2: Replace the frontmatter (lines 1–4).**

  Use Edit with `old_string` matching exactly:

  ```
  ---
  name: ss-sdd-discovering-requirements
  description: Use during the discovery stage of an SDD pipeline run, after ss-sdd-preflight and before ss-sdd-writing-specs. Drives an interactive conversation with the user to reach a shared understanding of what's being built — purpose, scope, users, success criteria, key decisions — without writing any artifacts yet.
  ---
  ```

  and `new_string`:

  ```
  ---
  name: ss-sdd-discovering-requirements
  description: Use during the discovery stage of an SDD pipeline run, after ss-sdd-preflight and before ss-sdd-writing-specs. Drives a four-phase interactive conversation (context → framing probe → targeted coverage walk → synthesis) and produces a structured end-of-stage summary for the coordinator. No artifacts are written to disk in this stage.
  ---
  ```

- [ ] **Step 3: Replace the Overview section.**

  Use Edit with `old_string` matching the existing Overview block (from `# Discovering Requirements` through the line before `## Hard Gates`) and `new_string`:

  ```markdown
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
  ```

- [ ] **Step 4: Replace the Hard Gates section.**

  Use Edit with `old_string` matching the existing Hard Gates block and `new_string`:

  ```markdown
  ## Hard Gates

  - Do NOT write any spec, plan, or implementation artifact to disk in this stage. The terminal state of this skill is "user has approved a shared understanding"; the agent's final message to the coordinator is the structured end-of-stage summary (Step 4.4), which lives in conversation, not on disk.
  - Do NOT propose more than one question per message. Even when topics relate, split them.
  - Do NOT proceed past a section the user hasn't approved.
  - Do NOT skip a framing probe (F1–F4) for any reason other than the narrow, explicit skip conditions listed in Phase 2.
  - Do NOT advance to Phase 4 synthesis without every Phase 3 dimension having a stated answer — a sentence or two, or an explicit `N/A — <Phase 1 or Phase 2 signal>`. Free-form `N/A — doesn't apply` is rejected.
  - Do NOT pass the Phase 4 stop-and-summarize self-check if you cannot, right now, write a single paragraph naming (a) the primary user, (b) their trigger, (c) what success looks like, and (d) the top 3 ways the feature can fail. If you can't, return to Phase 3 and drill the missing dimension(s).
  ```

- [ ] **Step 5: Replace the Checklist section.**

  Use Edit with `old_string` matching the existing Checklist block and `new_string`:

  ```markdown
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
  ```

- [ ] **Step 6: Read back the top of the file to verify coherence.**

  Run: `sed -n '1,80p' skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected output: frontmatter with new description; `# Discovering Requirements` heading; `## Overview` with four-phase narrative; `## Hard Gates` with six bullets; `## Checklist` with phased structure (items 1–13 plus the cross-cutting reminder). The next heading after the checklist should be `## Step 1: Load Project Context` (unchanged in this task — replaced in Task 2).

- [ ] **Step 7: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: four-phase shape (frontmatter, overview, gates, checklist)"
  ```

---

## Task 2 — SKILL.md: Phase 1 (replaces Steps 1–3)

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (replace `## Step 1: Load Project Context`, `## Step 2: Scope Check`, `## Step 3: Determine Work Type` with a single `## Phase 1 — Context` section)

- [ ] **Step 1: Read the current Step 1–3 sections to confirm boundaries.**

  Run: `sed -n '/^## Step 1:/,/^## Step 4:/p' skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md | head -90`
  Expected: full Step 1, Step 2, Step 3 content followed by the start of the `## Step 4: Conversational Discovery` heading.

- [ ] **Step 2: Replace the Step 1–3 block with the Phase 1 section.**

  Use Edit with `old_string` covering everything from `## Step 1: Load Project Context` through the line immediately before `## Step 4: Conversational Discovery`, and `new_string`:

  ```markdown
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

  ```

- [ ] **Step 3: Read back to verify the new Phase 1 section lands correctly and the file flows into the next existing section.**

  Run: `grep -n "^## " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md | head -10`
  Expected: headings should include `## Overview`, `## Hard Gates`, `## Checklist`, `## Phase 1 — Context`, then the still-present `## Step 4: Conversational Discovery` (will be replaced in Task 4).

- [ ] **Step 4: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: regroup Steps 1-3 under Phase 1 — Context"
  ```

---

## Task 3 — SKILL.md: Phase 2 — Framing probe (new section)

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (insert a new `## Phase 2 — Framing probe` section immediately after the end of Phase 1, before `## Step 4: Conversational Discovery`)

- [ ] **Step 1: Confirm the insertion point.**

  Run: `grep -n "^## Phase 1\|^## Step 4:" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: two lines — `## Phase 1 — Context` somewhere mid-file and `## Step 4: Conversational Discovery` later. The new Phase 2 section goes between them.

- [ ] **Step 2: Insert the Phase 2 section.**

  Use Edit with `old_string` set to the unique anchor `## Step 4: Conversational Discovery` (the next heading after Phase 1 ends) and `new_string` set to the full Phase 2 section followed by the same `## Step 4:` line (so the heading is restored after the insertion):

  ```markdown
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
  - **F2 forcing function.** If the user says they didn't consider alternatives, you MUST propose 2–3 before continuing to F3. Any decision the user resolves at F2 is **immediately tagged as an ADR candidate** in your in-memory understanding (same treatment as a major decision surfaced in Phase 3 §6). Phase 3 will not re-propose the same fork.
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

  ## Step 4: Conversational Discovery
  ```

  **Why the `new_string` ends with `## Step 4: Conversational Discovery`:** the anchor in `old_string` is just that heading line, so the new content + restored heading replaces it cleanly in one Edit call. The Step 4 content below the heading is unchanged in this task — it will be replaced in Task 4.

- [ ] **Step 3: Read back to verify Phase 2 is inserted between Phase 1 and Step 4.**

  Run: `grep -n "^## " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md | head -12`
  Expected order: `## Overview`, `## Hard Gates`, `## Checklist`, `## Phase 1 — Context`, `## Phase 2 — Framing probe`, `## Step 4: Conversational Discovery`, then the rest.

- [ ] **Step 4: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: add Phase 2 framing probe (F1-F4)"
  ```

---

## Task 4 — SKILL.md: Phase 3 — Targeted dimension walk (replaces Steps 4–5)

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (replace `## Step 4: Conversational Discovery` and `## Step 5: Propose Approaches for Major Decisions` with a single `## Phase 3 — Targeted dimension walk` section)

- [ ] **Step 1: Confirm boundaries.**

  Run: `grep -n "^## Step 4:\|^## Step 5:\|^## Step 6:" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: three line numbers — Step 4, Step 5, Step 6. The block to replace runs from Step 4's heading through the line before Step 6's heading.

- [ ] **Step 2: Replace the Steps 4–5 block with the Phase 3 section.**

  Use Edit with `old_string` covering everything from `## Step 4: Conversational Discovery` through the line immediately before `## Step 6: Present Shared Understanding in Sections`, and `new_string`:

  ```markdown
  ## Phase 3 — Targeted dimension walk

  The heart of discovery — where the spec's content is shaped. The 9-dimension table from the prior version of this skill is preserved verbatim, but its role shifts from *script* to *coverage checklist*.

  ### 3.1 — The coverage rule

  Every dimension below must end Phase 3 with a **stated answer** — a sentence or two you can recite. A dimension that genuinely doesn't apply ends with an explicit `N/A — <one-line reason citing a Phase 1 or Phase 2 signal>` statement. **The cited signal is mandatory.** Free-form `N/A — doesn't apply here` is rejected.

  Examples of well-formed N/A:
  - `N/A — F4 walkthrough involved no persistent data`
  - `N/A — constitution forbids external integrations for this layer`
  - `N/A — F3 substitute behavior is purely manual; no integration surface`

  There is no third option — no "skipped," no "we'll get to it." The Phase 4 stop gate (Step 4.1) verifies this rule.

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

  ```

- [ ] **Step 3: Read back to verify Phase 3 is in place and the file flows into Step 6 (still present, replaced in Task 5).**

  Run: `grep -n "^## " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md | head -12`
  Expected: `## Overview`, `## Hard Gates`, `## Checklist`, `## Phase 1`, `## Phase 2`, `## Phase 3`, `## Step 6:`, `## Step 7:`, `## Step 8:`, `## Common Mistakes`, `## Red Flags`.

- [ ] **Step 4: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: replace Steps 4-5 with Phase 3 (coverage rule + depth rule + graceful unknown)"
  ```

---

## Task 5 — SKILL.md: Phase 4 — Synthesis (replaces Steps 6–8)

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (replace `## Step 6: Present Shared Understanding in Sections`, `## Step 7: Final Confirmation`, `## Step 8: Hand Off` with a single `## Phase 4 — Synthesis` section)

- [ ] **Step 1: Confirm boundaries.**

  Run: `grep -n "^## Step 6:\|^## Step 7:\|^## Step 8:\|^## Common Mistakes" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: four line numbers. The block to replace runs from Step 6's heading through the line before `## Common Mistakes`.

- [ ] **Step 2: Replace the Steps 6–8 block with the Phase 4 section.**

  Use Edit with `old_string` covering everything from `## Step 6: Present Shared Understanding in Sections` through the line immediately before `## Common Mistakes`, and `new_string`:

  ```markdown
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

  ```

- [ ] **Step 3: Read back to verify Phase 4 lands and the file flows into Common Mistakes.**

  Run: `grep -n "^## " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected order: `## Overview`, `## Hard Gates`, `## Checklist`, `## Phase 1 — Context`, `## Phase 2 — Framing probe`, `## Phase 3 — Targeted dimension walk`, `## Phase 4 — Synthesis`, `## Common Mistakes`, `## Red Flags`. No `## Step N` headings remaining.

- [ ] **Step 4: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: replace Steps 6-8 with Phase 4 (stop-gate + section approval + structured summary + coordinator handling)"
  ```

---

## Task 6 — SKILL.md: Cross-cutting rules subsection (new)

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (insert a `## Cross-cutting rules` section between `## Phase 4 — Synthesis` and `## Common Mistakes`)

- [ ] **Step 1: Confirm insertion point.**

  Run: `grep -n "^## Phase 4\|^## Common Mistakes" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: two line numbers — Phase 4 (just added in Task 5) and Common Mistakes. The new subsection goes between them.

- [ ] **Step 2: Insert the Cross-cutting rules section.**

  Use Edit with `old_string` set to the anchor `## Common Mistakes` (the heading after Phase 4 ends) and `new_string` set to the full Cross-cutting rules section followed by the same `## Common Mistakes` line:

  ```markdown
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
  ```

  **Why the `new_string` ends with `## Common Mistakes`:** the anchor in `old_string` is just that heading line, so the new content + restored heading replaces it in one Edit call.

- [ ] **Step 3: Read back to verify.**

  Run: `grep -n "^## \|^### CC-" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: top-level headings include `## Cross-cutting rules` between `## Phase 4` and `## Common Mistakes`; sub-headings `### CC-1 — Playback gate`, `### CC-2 — Contradiction watch`, `### CC-3 — Adjacent-scenario invitation`, `### CC-4 — Mid-conversation scope re-check` appear in order.

- [ ] **Step 4: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: add cross-cutting rules (CC-1..CC-4)"
  ```

---

## Task 7 — SKILL.md: update Common Mistakes and Red Flags

**Files:**
- Modify: `skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md` (replace `## Common Mistakes` table and `## Red Flags` list to reflect the new four-phase shape)

- [ ] **Step 1: Confirm boundaries.**

  Run: `grep -n "^## Common Mistakes\|^## Red Flags" skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: two line numbers. The block to replace runs from Common Mistakes through end-of-file.

- [ ] **Step 2: Replace the Common Mistakes + Red Flags block.**

  Use Edit with `old_string` covering everything from `## Common Mistakes` to end-of-file, and `new_string`:

  ```markdown
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
  ```

- [ ] **Step 3: Read back end-of-file to verify.**

  Run: `tail -40 skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: updated Common Mistakes table with new entries (free-form N/A rejection, F2 forcing function, CC-3 distinct-scenario rule, §4.1 stop-gate, §4.4 structured summary) and updated Red Flags list referencing F1–F4, CC-2, CC-4, §4.1, §3.4.

- [ ] **Step 4: Full file sanity check — total length and heading order.**

  Run: `grep -n "^## \|^### " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected headings, in order: `## Overview`, `## Hard Gates`, `## Checklist`, `## Phase 1 — Context` with `### 1.1`, `### 1.2`, `### 1.3`, `## Phase 2 — Framing probe` with `### The probes`, `### Protocol`, `### Skip conditions...`, `### Non-overlap with Phase 3`, `## Phase 3 — Targeted dimension walk` with `### 3.1`, `### 3.2`, `### 3.3`, `### 3.4`, `## Phase 4 — Synthesis` with `### 4.1`, `### 4.2`, `### 4.3`, `### 4.4`, `### How the coordinator uses each field`, `## Cross-cutting rules` with `### CC-1`, `### CC-2`, `### CC-3`, `### CC-4`, `## Common Mistakes`, `## Red Flags`.

  Run: `wc -l skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md`
  Expected: ~280–320 lines (design estimate). If under 250 or over 350, re-read the file end-to-end and confirm no section was lost or duplicated.

- [ ] **Step 5: Commit.**

  ```bash
  git add skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md
  git commit -m "ss-sdd-discovering-requirements: refresh Common Mistakes and Red Flags for four-phase shape"
  ```

---

## Task 8 — `docs/sdd/pipeline.md`: update Stage 1 narrative

**Files:**
- Modify: `docs/sdd/pipeline.md` (Stage 1 section, lines ~86–119)

- [ ] **Step 1: Confirm current Stage 1 boundaries.**

  Run: `grep -n "^## Stage 1\|^## Stage 2" docs/sdd/pipeline.md`
  Expected: two line numbers — Stage 1's heading and Stage 2's heading. The block to replace runs from Stage 1's heading through the line before Stage 2's heading.

- [ ] **Step 2: Replace the Stage 1 section.**

  Use Edit with `old_string` covering everything from `## Stage 1 — Discovering requirements` through the line immediately before `## Stage 2 — Writing the spec`, and `new_string`:

  ```markdown
  ## Stage 1 — Discovering requirements

  **Skill:** `ss-sdd-discovering-requirements` (inline)
  **Output:** shared understanding of the feature held in the coordinator's conversation context, plus a structured end-of-stage summary in the agent's final message.

  This is the conversational stage. The skill drives a Q&A with the user — one question per message, multiple choice preferred where applicable, with a recommended answer when there's a clear best choice. It runs in **four phases** with four **cross-cutting rules** applied throughout.

  ### Phase 1 — Context

  Loads project conventions (constitution / ADRs / architecture / glossary / domain / README) via `framework/discover-context.sh`. Runs the initial scope check — if the request describes multiple independent subsystems, recommends decomposition into separate SDD runs. Classifies work type (`feature` or `fix`); inferred from initial input, asked only if ambiguous.

  ### Phase 2 — Framing probe

  Four fixed probes, in order, each skippable only under narrow explicit conditions:

  | # | Probe | Purpose |
  |---|---|---|
  | F1 | Driver / timing — "What's prompting this now?" | Distinguishes urgency from background priority |
  | F2 | Alternatives considered — "What did you consider, why this?" | Catches single-option framings; forcing function: if user considered none, agent proposes 2–3 before continuing, and the resolved decision is tagged as an ADR candidate immediately |
  | F3 | Substitute behavior — "What do users do today without this?" | Reveals real stakes and the true substitute |
  | F4 | Concrete walkthrough — "Walk me through one real scenario" | Forces commitment to specifics; establishes the baseline scenario |

  Framing answers reshape the entire feature; CC-1 (playback gate) is applied aggressively here. Decisions resolved at F2 are tagged as ADR candidates and Phase 3 will not re-propose them.

  ### Phase 3 — Targeted dimension walk

  The skill walks the 9-dimension coverage checklist:

  | Dimension | What gets covered |
  |---|---|
  | Purpose | Problem and who feels it |
  | Users | Roles + triggers |
  | Scope (in) | Smallest valuable slice |
  | Scope (out) | Explicit deferrals |
  | Success | At least one measurable outcome |
  | Key entities | Domain objects (if any) |
  | Edge cases | Top 3 failure modes |
  | Constraints | Tech/perf/security/compliance |
  | Integration | External dependencies + failure modes |

  Every dimension must end Phase 3 with a stated answer or `N/A — <Phase 1 or Phase 2 signal>`. Free-form N/A is rejected. Depth per dimension is driven by signals from Phase 1 (constitution / ADRs) and Phase 2 (especially F4's walkthrough), not by a fixed quota.

  **Major design decisions** with non-obvious tradeoffs are presented as 2–3 options with the skill's recommendation and reasoning. The user picks. The chosen decision (with rejected options and reasoning) is tagged as an ADR candidate for Stage 6.

  **Graceful-unknown protocol:** if a dimension can't be resolved after reasonable drilling, the skill surfaces it as an Open Question with a proposed default and lets the user pick (accept the default / defer to Assumptions / defer to a follow-up spec). This is the recovery mechanism that prevents the Phase 4 stop gate from looping.

  ### Phase 4 — Synthesis

  Four sub-steps:

  - **Stop-and-summarize gate (NEW):** the agent runs a self-check before summarizing — "can I write a single paragraph naming the primary user, their trigger, what success looks like, and the top 3 ways this could go wrong?" If no, return to Phase 3.
  - **Section-by-section approval:** sections are presented in order (Goal & problem → Users & flows → Scope → Success → Key entities → Edge cases & constraints → Major decisions), each with explicit user approval required before moving on. The Goal section is framed with its F1 driver (and F3 substitute, when load-bearing) inline as a parenthetical, so framing drift is cheap to spot.
  - **Final confirmation:** the agent restates the one-paragraph summary and asks "ready to write this up?"
  - **Structured end-of-stage summary:** the agent's final message to the coordinator is a fixed-shape block (`=== DISCOVERY SUMMARY === / === END SUMMARY ===`) covering `short_name`, `work_type`, `framing` (driver/alternatives/substitute_behavior/walkthrough), `dimensions` (all 9), `major_decisions` (ADR candidates with chosen / rejected / reasoning), `open_questions` (with disposition), and `approved_sections`. The structured shape exists for the agent's own self-discipline (forces every dimension to be actually stated) and for cleaner coordinator state; it is **not** a parse contract with Stage 2. The coordinator's existing in-memory handoff to Stage 2 and existing `DECISIONS_CAPTURED` dispatch to Stage 6 absorb the structured material via the same channels as today; no new dispatch parameters are introduced.

  ### Cross-cutting rules

  Apply throughout Phases 2–4 as their triggers fire (not sequential steps). Full definitions in the skill's SKILL.md.

  | Rule | Trigger |
  |---|---|
  | CC-1 — Playback gate | After any non-obvious user answer; paraphrase the implication before the next question |
  | CC-2 — Contradiction watch | When two user answers imply different systems; surface and resolve |
  | CC-3 — Adjacent-scenario invitation | When a Phase 3 dimension is stuck on abstractions after ≥2 exchanges; ask for a scenario *distinct* from F4 |
  | CC-4 — Mid-conversation scope re-check | When the user adds independent functionality mid-discovery; re-run Phase 1's scope check |

  ### Hard gate

  The skill writes nothing to disk. The output is shared understanding in the coordinator's context plus the structured end-of-stage summary in the agent's final message. Stage 2 turns that understanding into the formal spec artifact.

  ```

- [ ] **Step 3: Read back to verify.**

  Run: `sed -n '/^## Stage 1/,/^## Stage 2/p' docs/sdd/pipeline.md | head -120`
  Expected: full new Stage 1 narrative with the four-phase structure, cross-cutting rules table, and hard gate paragraph; Stage 2 heading appears at the end of the output.

- [ ] **Step 4: Commit.**

  ```bash
  git add docs/sdd/pipeline.md
  git commit -m "docs/sdd/pipeline.md: rewrite Stage 1 narrative for four-phase discovery"
  ```

---

## Task 9 — `docs/sdd/skills.md`: update skill entry

**Files:**
- Modify: `docs/sdd/skills.md` (the `## ss-sdd-discovering-requirements` section, around lines 127–155)

- [ ] **Step 1: Confirm boundaries.**

  Run: `grep -n "^## ss-sdd-discovering-requirements\|^## ss-sdd-writing-specs" docs/sdd/skills.md`
  Expected: two line numbers. The block to replace runs from the discovering-requirements heading through the line before the writing-specs heading.

- [ ] **Step 2: Replace the skill entry.**

  Use Edit with `old_string` covering the discovering-requirements entry (from its `## ss-sdd-discovering-requirements` heading through the line immediately before `## ss-sdd-writing-specs`), and `new_string`:

  ```markdown
  ## ss-sdd-discovering-requirements

  **Type:** Phase skill (inline; conversational)
  **Loaded:** by the coordinator at Stage 1
  **Stage:** 1

  **Purpose:** Build shared understanding of what's being built through a four-phase conversation. Output is in-memory plus a structured end-of-stage summary in the agent's final message; nothing is written to disk in this stage. `ss-sdd-writing-specs` renders the spec next.

  **Four phases:**
  - **Phase 1 — Context:** load conventions, scope-check, classify work type (`feature` / `fix`)
  - **Phase 2 — Framing probe:** F1 driver, F2 alternatives, F3 substitute behavior, F4 concrete walkthrough — surfaces the implicit before requirements gathering
  - **Phase 3 — Targeted dimension walk:** every dimension in the 9-dimension coverage checklist ends with a stated answer (or signal-cited N/A); major decisions tagged as ADR candidates
  - **Phase 4 — Synthesis:** stop-and-summarize gate, section-by-section approval (with F1/F3 framing inline), final confirmation, structured end-of-stage summary

  **Cross-cutting rules (apply throughout Phases 2–4):**
  - CC-1 — Playback gate (paraphrase non-obvious implications)
  - CC-2 — Contradiction watch (surface and resolve conflicting answers)
  - CC-3 — Adjacent-scenario invitation (ask for a scenario *distinct* from F4 when a dimension is stuck)
  - CC-4 — Mid-conversation scope re-check (re-run Phase 1's scope check on added functionality)

  **Conversation rules:**
  - One question per message (no compound questions)
  - Multiple choice with a recommended answer preferred over open-ended when there are clear alternatives
  - Framing probes (F1–F4) skippable only under narrow explicit conditions
  - F2 forcing function: if user considered no alternatives, agent proposes 2–3 and tags the resolved decision as an ADR candidate immediately

  **Hard gate:** the skill writes NOTHING to disk. Output is the coordinator's understanding plus the structured end-of-stage summary in the agent's final message.

  **Reads:** project context (via `discover-context.sh`)
  **Writes:** nothing

  **Section-by-section approval:** at the end, the skill summarizes back in sections (goal, users, scope, success, entities, edge cases, decisions). User approves each before moving on. The Goal section is framed with its F1 driver (and F3 substitute, when load-bearing) inline as a parenthetical.

  **Structured end-of-stage summary** (the agent's final message to the coordinator):

  ```
  === DISCOVERY SUMMARY ===
  short_name, work_type
  framing: driver, alternatives, substitute_behavior, walkthrough
  dimensions: purpose, users, scope_in, scope_out, success, entities, edge_cases, constraints, integration
  major_decisions: [{title, chosen, rejected, reasoning}]
  open_questions: [{question, default, disposition}]
  approved_sections
  === END SUMMARY ===
  ```

  The structure is for agent self-discipline and cleaner coordinator state; it is NOT a parse contract with Stage 2. No new dispatch parameters introduced — the summary populates existing in-memory carry and the existing `DECISIONS_CAPTURED` dispatch to Stage 6.

  **Common mistakes:**
  - Skipping framing probes without an explicit narrow skip condition
  - Free-form `N/A — doesn't apply` for a dimension (must cite a Phase 1 or Phase 2 signal)
  - Re-proposing decisions already resolved at F2
  - Advancing past the §4.1 stop-gate without being able to write the user/trigger/success/failure paragraph
  - Returning a free-form bullet list instead of the §4.4 structured summary

  ---

  ```

- [ ] **Step 3: Read back to verify.**

  Run: `sed -n '/^## ss-sdd-discovering-requirements/,/^## ss-sdd-writing-specs/p' docs/sdd/skills.md`
  Expected: full updated entry with four-phase structure, cross-cutting rules, structured summary block; ends just before the writing-specs heading.

- [ ] **Step 4: Commit.**

  ```bash
  git add docs/sdd/skills.md
  git commit -m "docs/sdd/skills.md: update ss-sdd-discovering-requirements entry for four-phase shape"
  ```

---

## Task 10 — `README.md`: update Skills section entry

**Files:**
- Modify: `README.md` (the `#### [ss-sdd-discovering-requirements]` entry, around lines 220–229)

- [ ] **Step 1: Confirm boundaries.**

  Run: `grep -n "^#### \[ss-sdd-discovering-requirements\]\|^#### \[ss-sdd-writing-specs\]" README.md`
  Expected: two line numbers. The entry to replace runs from the discovering-requirements line through the line before the writing-specs line.

- [ ] **Step 2: Replace the entry.**

  Use Edit with `old_string` covering the existing 10-ish line entry (from `#### [ss-sdd-discovering-requirements]...` through the blank line immediately before `#### [ss-sdd-writing-specs]...`), and `new_string`:

  ```markdown
  #### [ss-sdd-discovering-requirements](skills/spec-driven-development/ss-sdd-discovering-requirements/)

  Four-phase discovery conversation: Context (load conventions, scope
  check, classify work type) → Framing probe (F1 driver / F2 alternatives
  / F3 substitute behavior / F4 concrete walkthrough) → Targeted dimension
  walk (9-dimension coverage checklist; every dimension ends with a
  stated answer or signal-cited N/A) → Synthesis (stop-and-summarize
  gate, section-by-section approval, structured end-of-stage summary).
  Four cross-cutting rules (CC-1 playback gate, CC-2 contradiction watch,
  CC-3 adjacent-scenario invitation, CC-4 mid-conversation scope
  re-check) apply throughout Phases 2–4. Output is shared understanding
  in the coordinator's context plus a fixed-shape structured summary in
  the agent's final message; no files written to disk —
  `ss-sdd-writing-specs` renders the spec next.

  ```

- [ ] **Step 3: Read back to verify.**

  Run: `sed -n '/^#### \[ss-sdd-discovering-requirements\]/,/^#### \[ss-sdd-writing-specs\]/p' README.md`
  Expected: the new entry, ending with a blank line before the writing-specs heading.

- [ ] **Step 4: Commit.**

  ```bash
  git add README.md
  git commit -m "README.md: update ss-sdd-discovering-requirements entry for four-phase shape"
  ```

---

## Post-implementation sanity check

After all ten tasks are complete, run this final verification:

```bash
# Confirm SKILL.md heading structure
grep -n "^## \|^### " skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md

# Confirm pipeline.md Stage 1 section uses four-phase language
grep -c "Phase [1-4]" docs/sdd/pipeline.md

# Confirm skills.md entry mentions all four phases and cross-cutting rules
grep -A1 "^## ss-sdd-discovering-requirements" docs/sdd/skills.md | head -5

# Confirm README entry references the four-phase structure
grep -A2 "ss-sdd-discovering-requirements\](skills" README.md | head -5

# Confirm no stale references to old step structure remain in updated files
grep -n "Step 1: Load Project Context\|Step 4: Conversational Discovery\|Step 8: Hand Off" \
  skills/spec-driven-development/ss-sdd-discovering-requirements/SKILL.md \
  docs/sdd/pipeline.md \
  docs/sdd/skills.md \
  README.md
```

Expected: heading structure matches the Task 7 final list; `Phase` mentions in pipeline.md are non-zero (≥4); skills.md and README.md entries are recognizably the new content; the stale-reference grep returns no matches.

If any check fails, identify which task's edit was incomplete and apply a fix-up commit; do NOT silently amend prior commits.
