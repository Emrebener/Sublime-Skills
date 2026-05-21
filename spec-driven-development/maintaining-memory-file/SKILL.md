---
name: maintaining-memory-file
description: Use when dispatched as a subagent during the memory-file maintenance stage of an SDD pipeline run, after handoff generation and before finishing. Reads the spec, plan, and any ADRs from this run to decide whether the project's agent memory file (CLAUDE.md, AGENTS.md, etc.) needs updating. Updates ONLY for significant architectural changes or non-obvious project conventions. Respects a configurable character cap. Never bloats the file with transient or narrative content.
---

# Maintaining Memory File

## Overview

Agent memory files like `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, etc. are loaded into every AI session for the project. They tell future agents what's true about the codebase that they can't easily learn from reading: project-wide conventions, non-obvious constraints, NEVER-do and MUST-do rules, canonical vocabulary, pointers to where deeper info lives.

A stale memory file is worse than no memory file. Agents trust what's in there; if it lies, they propagate the lie. Updating it after each shipped feature is genuinely tedious for humans, which is why it falls behind.

Your job: read what this run produced (spec, plan, ADRs), decide whether **anything in it changes what's true at the project level**, and update the memory file if so. Most runs do not warrant an update — that's normal and correct.

**Core principle:** A memory file update earns its place. If you can't write a one-line answer to "what would a future agent get wrong without this?", don't add the line.

**Operating mode:** Read SDD artifacts + existing memory file. Write at most ONE file (the memory file itself). Never modify spec, plan, ADRs, or state.

**Leaf skill — do not dispatch sub-subagents.**

**Announce at start:** "I'm using the maintaining-memory-file skill to check whether the project memory file needs updating."

## Hard Gates

- Do NOT update the memory file just because a feature shipped. Most features don't change project-level truth.
- Do NOT duplicate content from the spec, plan, ADRs, or handoff doc. Reference them by path when relevant.
- Do NOT write narrative ("we built X for Y reason") — agents don't need the story, they need the rules.
- Do NOT exceed the character cap. If your additions would push the file past the cap, you must either tighten existing content or omit your additions.
- Do NOT modify any file other than the memory file.
- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.

## What You Get From the Coordinator

The dispatch prompt includes:

- `SPEC_PATH` — path to spec.md
- `PLAN_PATH` — path to plan.md
- `ADR_PATHS` — list of ADRs created or modified in this run (may be empty)
- `MEMORY_FILE_PATH` — resolved path to the memory file (from config or auto-detect). May be `null` if no memory file exists and the user didn't configure one — in which case you SKIP (return "no memory file configured; no update").
- `CHARACTER_LIMIT` — soft cap on total memory file size (default 40000 from config). Warning at 90%, refuse to push past it.
- `EXISTING_CONTENT` — full text of the current memory file (or empty if it doesn't exist yet)

## Checklist

1. Read spec, plan, every ADR — identify candidates for memory-file relevance
2. Read existing memory file content
3. For each candidate, decide: is this a project-level change agents need to know? (Most aren't — that's the default answer)
4. If no candidates pass the bar: return "no update" and stop. **This is the most common outcome.**
5. If candidates pass: compose the update (additions and/or edits)
6. Check character budget: would your update + existing content exceed the cap?
7. If yes: tighten existing content (reduce verbosity, drop now-obsolete lines) before adding
8. Write the updated memory file atomically (`.tmp` + `mv`)
9. Report

## Step 1: Identify Candidates

A candidate is something in this run that **changes what's true at the project level**. Walk through the sources:

### From ADRs (highest signal)

Each ADR in `ADR_PATHS` is a candidate. Read its Decision and Consequences sections. Ask:
- Does this introduce a project-wide convention agents should follow? (e.g., "all auth uses JWT")
- Does it forbid an approach? (e.g., "we never use raw SQL — always the query builder")
- Does it set a constraint future code must satisfy? (e.g., "all writes go through the audit log")

An ADR is a strong candidate when its Decision is something a future engineer touching unrelated code might re-litigate without knowing it was already decided.

### From the spec (medium signal)

Look at:
- **New domain vocabulary** introduced in Key Entities or Glossary clarifications — promote to memory if it's a term the codebase now uses widely
- **Constraints in Assumptions** — if there's a project-wide constraint here (not feature-specific), it might belong in memory
- **Out-of-Scope items** that imply a NEVER rule for the project ("we don't support social login" → "do not add social login providers without spec approval")

### From the plan (low signal, mostly skip)

Plans are usually about HOW for one feature, not WHAT IS for the project. But occasionally:
- A **new tech-stack addition** (added `bcrypt`, added `pino` for logging) might warrant a memory line if it becomes the canonical choice
- A **pattern established** (first time the project uses X pattern, future features should match) — if this is genuinely the first instance, memory line; otherwise the pattern is already established and doesn't need re-statement

### From the handoff (skip)

The handoff doc covers this specific feature's context. It doesn't reflect project-level truth. Don't pull from it.

## Step 2: The "Earns Its Place" Bar

For each candidate, run it through these filters:

| Filter | If yes → keep | If no → drop |
|---|---|---|
| Would a future agent reading unrelated code get this wrong without the line? | ✓ Keep | ✗ Drop |
| Is this stable (won't change next month)? | ✓ Keep | ✗ Drop (memory shouldn't track transient things) |
| Is this NOT already obvious from reading the codebase? | ✓ Keep | ✗ Drop (don't duplicate what's already self-evident) |
| Is this NOT already documented in CLAUDE.md / existing memory? | ✓ Keep | ✗ Drop (don't duplicate within the memory file) |
| Is the line shorter than the paragraph it would take to explain the implications? | ✓ Keep | ✗ Drop (if your line needs a paragraph of context, it doesn't belong) |

**Default to drop.** Memory files atrophy from accretion. Adding three lines that are 60% useful is worse than adding one line that's 100% useful.

## Step 3: Format the Update

Memory files are read by every agent every session. Token economy matters.

### Structure

If the file doesn't exist, create it with a sensible default structure:

```markdown
# <Project Name> — Agent Memory

## Project conventions

- <Stable rule or convention>

## Domain vocabulary

- **<Term>:** <definition>

## NEVER / MUST

- NEVER: <rule>
- MUST: <rule>

## Pointers

- Architecture: see [ARCHITECTURE.md](ARCHITECTURE.md)
- ADRs: docs/adr/
- Specs: docs/specs/
```

If the file exists, **respect its existing structure.** Don't reorganize. Find the section your additions belong in and add there.

### Line shape

- **One line per rule.** Prefer bullet lists over prose.
- **Lead with the verb / rule.** "MUST validate inputs via the schema layer" not "It is expected that inputs are validated using the schema layer..."
- **Cite the ADR/spec when relevant** so the reader can dig deeper: `- All auth uses JWT (ADR-0003).`
- **No timestamps, no "as of <date>"** — memory should read as eternal truth at all times.
- **No "we recently added X"** — agents don't care about history, they care about current state.

### What belongs in each section (suggested defaults)

- **Project conventions** — stable patterns the project follows (architecture style, error handling approach, logging conventions, testing approach)
- **Domain vocabulary** — terms with specific meanings in this codebase (3-15 entries is typical; if you have 50, the glossary doc should be the source of truth and memory should point to it)
- **NEVER / MUST** — hard rules. Use sparingly. Each rule should have a real cost if broken.
- **Pointers** — paths/URLs to deeper docs. The memory file should never re-explain what an ADR or architecture doc already explains; link instead.

## Step 4: Check the Character Budget

Compute: `(existing_content_length - removed_lines_length) + new_additions_length`.

- **Under 90% of `CHARACTER_LIMIT`:** safe to write.
- **90%–100%:** include a one-line warning in your report: "Memory file is at <N>% of cap; consider pruning."
- **Over 100%:** do NOT write. Either tighten existing content first (look for verbose paragraphs, redundant rules, narrative cruft) or omit your additions. If you must omit, report what you dropped and why.

The cap is a soft budget for token economy. CLAUDE.md is widely recommended to stay under 40k chars because larger files cost more on every session and start losing the "always loaded" guarantee on some platforms.

## Step 5: Apply Edits

Compose the new full content. Then:

1. Write to `<MEMORY_FILE_PATH>.tmp`
2. Sanity-check: the file is still valid markdown, the structure isn't broken, the total char count is within budget
3. `mv <MEMORY_FILE_PATH>.tmp <MEMORY_FILE_PATH>`

If the existing file had subtle formatting (specific heading levels, blank-line spacing, table alignment), preserve it. Don't reformat for its own sake.

## Step 6: Report

Return to the coordinator:

```
## Memory File Update

**Status:** updated | no update needed | skipped (no path configured)
**File:** <path>
**Character count:** <N> / <limit> (<percent>%)
**Lines added:** <N>
**Lines removed:** <N> (and one-line reason for each removal if any)
**Lines edited:** <N>

### Update summary

(One paragraph: what changed in the project's stable truth as a result of this run, and which ADR/spec drives it. Empty if "no update needed".)

### Reasons candidates were dropped (if any)

- <Candidate>: <reason — "already documented", "feature-specific", "would need too much context", etc.>
```

If status is "no update needed", that's a complete and valid outcome — the file isn't expected to change every run.

## Best Practices: Managing Memory Files

These are general principles for any agent memory file. Apply when creating new files; don't enforce on existing files unless asked.

### What memory is for

- **Project-wide rules** that agents need to honor on every interaction
- **Canonical vocabulary** that resolves ambiguity in everyday code
- **Pointers** to deeper documentation
- **Reminders of constraints** that aren't obvious from code (legal, performance, security policies)

### What memory is NOT for

- **Recent changes** — that's git log
- **Active TODOs** — that's an issue tracker
- **Architecture explanation** — that's ARCHITECTURE.md (link instead)
- **API surface area** — that's auto-generated docs or the code
- **In-flight work** — that's the handoff doc for THAT work
- **History of how the project evolved** — agents don't need this
- **Tone/style preferences** that the code already demonstrates

### Sizing

| File size | Behavior |
|---|---|
| Under 4k chars | Healthy — fits in any context budget |
| 4k–20k chars | Good — readable in one scan |
| 20k–40k chars | Watch — starts adding up across sessions |
| Over 40k chars | Prune — likely accumulated cruft; some platforms drop the "always loaded" guarantee here |

### Update cadence

Most features ship without warranting a memory update. Healthy frequencies look like:
- A clean, established project: roughly **1 memory update per 5-15 features**
- A young project: more frequent updates (1 per 2-3 features) as conventions solidify
- An old, stable project: rare updates (1 per 20+ features); structural shifts only

If you find yourself updating memory every feature, you're probably treating memory as a changelog. Stop.

### Pruning

Once a quarter (or when the file hits 75% of cap), prune:
- Remove rules that have become obvious from code patterns (the code teaches it now)
- Consolidate redundant entries
- Update or remove entries pointing to renamed files / deprecated tooling
- Move detail to other docs (ARCHITECTURE.md, GLOSSARY.md) and replace with a pointer

### Multiple memory files

Some projects have both `CLAUDE.md` AND `AGENTS.md` (or similar). Conventions vary by tool:
- **CLAUDE.md** — Claude Code's preferred name
- **AGENTS.md** — emerging community convention for tool-agnostic agent memory
- **GEMINI.md** — Gemini CLI
- **.agents.md** — sometimes used as a "hidden" variant

The skill updates only the configured path. If the project has multiple memory files, point the config at one and document in that file (with a pointer) that the others should follow it, OR run the skill separately for each (e.g., `memory_file.paths: [...]` as a future enhancement; current implementation handles one path).

### Anti-patterns to watch for

| Anti-pattern | Why it's bad | Fix |
|---|---|---|
| "As of Q3 2026, we now use..." | Timestamps rot; memory should always read as current truth | Drop the timestamp |
| "We recently switched from X to Y" | Story rather than rule | "Use Y, not X" or "All <thing> uses Y (ADR-NNNN)" |
| Multi-paragraph explanation of a single rule | Should be in a doc; memory should link | One-line rule + pointer |
| Conflicting rules (e.g., two entries that say opposite things) | Agents will pick one and confuse you | Resolve conflict; have only one true rule |
| Style/aesthetic preferences ("prefer concise over verbose comments") | Already obvious from existing code | Drop unless there's a real policy reason |
| Listing every file in the project | Auto-derivable from `ls` | Drop |
| "Always run tests before committing" | Should be enforced by a pre-commit hook, not a memory rule agents might miss | Implement the hook; consider whether the memory line is still needed |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Updating memory on every feature ship | Most features don't warrant updates; "no update needed" is the most common outcome |
| Copying ADR text into memory | Link to the ADR; one-line summary at most |
| Adding history/narrative ("we used to do X, now we do Y") | Memory is for current truth, not evolution |
| Adding obvious things ("we use TypeScript") | If it's obvious from `package.json` / `pyproject.toml`, skip |
| Exceeding the character cap to add a "small" line | The cap is the cap; tighten existing content or omit |
| Reorganizing the existing structure when adding | Respect what's there; add to the appropriate section |
| Including tone/style guidance the code already shows | Code teaches by example; memory teaches non-obvious rules |
| Putting in-progress / TODO items in memory | Memory is stable truth; use issue trackers for TODOs |

## Red Flags

- About to add a memory entry that's a one-time fact ("the Q3 launch used JWT") → STOP; not stable truth
- About to write a paragraph rather than a one-line rule → STOP; either tighten or move to a real doc + link
- About to exceed the character cap to fit an addition → STOP; prune first or omit the addition
- About to update memory because "the feature shipped" without identifying a project-level truth change → STOP; return "no update needed"
- About to dispatch a sub-subagent → STOP; leaf skill
- About to modify any file other than the memory file → STOP; only the memory file is in scope
