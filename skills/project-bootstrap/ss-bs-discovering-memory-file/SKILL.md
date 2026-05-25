---
name: ss-bs-discovering-memory-file
description: Use during project bootstrap (or audit) to discover, propose, and write the project's agent memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md). Runs last in the bootstrap sequence so it can synthesize pointers to the other six artifacts (constitution, architecture, testing, glossary, domain, design) rather than duplicate them. One of seven discovery skills loaded inline by ss-bs-bootstrapping-project; never dispatched as a subagent. Distinct from ss-sdd-maintaining-memory-file, which updates the same file incrementally during SDD feature runs.
---

# Discovering the Agent Memory File

## Overview

You discover, draft, and write the project's agent memory file — `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, or `.agents.md` (the user picks if multiple are possible, or chooses one to create if none exist). Output: a single file at the path determined by Step 0; the chosen path is written back to `.sublime-skills/config.yml`'s `memory_file.path`. You are loaded **inline** by `ss-bs-bootstrapping-project` (last stage, after all other discovery stages) or `ss-bs-auditing-project`.

You synthesize pointers to the other six artifacts (constitution, architecture, testing, glossary, domain, design) plus a small set of canonical project conventions, vocabulary highlights, NEVER/MUST rules seeded from the constitution, and run commands extracted from the project's task runner.

**Core principle:** A memory file earns every line. Agent memory is loaded into every session — token waste compounds. Link to the other artifacts rather than restating them. Your job is the navigation layer, not the explanation layer.

**Announce at start:** "I'm using the ss-bs-discovering-memory-file skill to draft your project's agent memory file."

## When This Skill Runs

- Bootstrap stage 7 (last) when the coordinator's per-file loop reaches the memory-file artifact. Runs after constitution, architecture, testing, glossary, domain, and design have been settled (created / extended / replaced / skipped).
- Audit, when the user picks the memory-file stage from the scope question.

## Hard Gates

- Do NOT run before the other 6 discovery stages have completed in this bootstrap run. The skill synthesizes pointers; running early means pointers reference files that may not exist yet.
- Do NOT maintain multiple memory files. Bootstrap maintains exactly one. If the project has `CLAUDE.md` + `AGENTS.md` side-by-side, ask which is canonical (Step 0c) and leave the others alone.
- Do NOT exceed the `memory_file.character_limit` from config (default 40 000). If the synthesized draft is at or above 90% of the limit, surface a warning and ask the user which sections to trim before writing.
- Do NOT write past 100% of `character_limit` under any circumstances. If trimming fails to bring the draft within budget, report what was dropped and return `skipped (character budget exceeded)`.
- Do NOT duplicate content from the other artifacts — link instead. The Pointers section is the linkdump; the Domain vocabulary section holds 3–5 sample terms and a pointer to GLOSSARY.md.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. Zero strong candidates → Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT run Step 1.5 when `SUGGEST=off`; skip it entirely — do not run-but-suppress.
- Do NOT use severity MUST for a diagnose candidate unless there is observable harm. Weaker evidence defaults to SHOULD or INFO.
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). This is documented in the Inputs section.
- ALWAYS use the harness's interactive question tool for every multi-choice or multi-select question. Do not fall back to plain-text prompts.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask.
- ALWAYS write atomically: `<path>.tmp` then `mv`.
- ALWAYS run `validate-config.sh` after the config writeback in Step 6. Halt and surface the error if validation fails.

## Inputs (from coordinator)

- `REPO_ROOT` — absolute path to repo root
- `MODE` — `create`, `extend`, `replace`, or `audit`. Audit invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3.
- `EXISTING_CONTENT` — verbatim current memory-file content (only for `extend` / `replace` / `audit`; empty for `create`)
- `FILE_PATH` — target path if `memory_file.path` is already set in config; `null` otherwise (Step 0 detects)
- **`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both. Defaulted by the coordinator from `suggest.default` in config. Always `on` in audit mode.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 0: detect target file (which memory file) │
│   → Step 1: silent scan (6 artifacts + run cmds +  │
│             README first paragraph)                 │
│   → Step 1.5: silent diagnose (if SUGGEST=on)      │
│   → Step 2: announce findings (+ diagnoses if any) │
│   → Step 3: Q1 (sections), Q1.5 (suggestions),    │
│             Q2 (pointers), Q3 (conventions),       │
│             Q4 (NEVER/MUST)                        │
│   → Step 4: synthesize draft → show to user        │
│   → Step 5: refine via tweak loop (cap 3)          │
│   → Step 6: atomic write + config writeback        │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 0 (same — confirm/detect target file)     │
│   → Step 1 + read EXISTING_CONTENT                 │
│   → Step 1.5: diagnose (if SUGGEST=on)             │
│   → Step 2: announce findings + gaps + diagnoses   │
│   → Step 3: questions on gaps + Q1.5               │
│   → Step 4: synthesize additions → show diff       │
│   → Step 5: refine via tweak loop (cap 3)          │
│   → Step 6: atomic write of merged content         │
│             + config writeback                     │
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 0: detect target file (same as always)    │
│   → Step 1: silent scan (6 artifacts + run cmds +  │
│             README first paragraph)                 │
│   → Step 1.5: silent diagnose (always on for audit) │
│   → Step 1.6: drift check vs EXISTING_CONTENT       │
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3: Q0 (drift resolution) → Q1 → Q1.5 → ...│
│   → Step 4-6: as usual                              │
└─────────────────────────────────────────────────────┘
```

## Step 0: Detect Target File

Determine which memory file to maintain. This runs before Step 1 so every subsequent step knows the target path.

### 0a. Check the config

If `memory_file.path` in `.sublime-skills/config.yml` is set to a non-null path, set `FILE_PATH` to that value. Skip 0b–0d. Proceed to Step 1.

### 0b. Auto-detect existing files

If `memory_file.path` is null, look in the repo root for these four names, in this priority order:

1. `CLAUDE.md`
2. `AGENTS.md`
3. `GEMINI.md`
4. `.agents.md`

### 0c. Multiple exist — ask which is canonical

If 2 or more of the four names are present, ask:

```
Question: "I see multiple agent memory files: <list of found files>.
Which is canonical for bootstrap to maintain?
(The others will be left alone — bootstrap only maintains one.)"

Multi-choice: one option per file found, plus
  - "I'll maintain them manually — skip the memory file" (bailout)
```

Record the chosen path as `FILE_PATH`. The non-chosen files are untouched.

### 0d. None exist — ask which to create

If none of the four names are present in repo root, ask:

```
Question: "Which agent memory file should I create?"

Multi-choice:
  - "CLAUDE.md (Claude Code's preferred name)" (Recommended)
  - "AGENTS.md (vendor-neutral community convention)"
  - "GEMINI.md (Gemini CLI's preferred name)"
  - ".agents.md (alternative neutral name)"
```

Set `FILE_PATH` to the chosen filename.

### 0e. Set FILE_PATH and prepare config writeback

`FILE_PATH` is now set from one of the above branches. Mark whether this was a new path (i.e., `memory_file.path` was null at the start of Step 0). The config writeback happens in Step 6 after the file is written.

If the user chose "I'll maintain them manually — skip the memory file", report `skipped (user declined)` to the coordinator and exit immediately.

## Step 1: Code Scan (Silent — No User Narration Yet)

Read what exists. Don't narrate progress to the user — announce findings once in Step 2.

### 1a. Read the other 6 artifacts

For each of these config keys: `constitution_path`, `architecture_path`, `testing_path`, `glossary_path`, `domain_path`, `design_path` — if the key is non-null AND the file exists on disk, read it. Hold its content in memory.

These become the Pointers section (every existing artifact → one pointer entry) and seed the vocabulary, NEVER/MUST, and conventions extraction.

### 1b. Run commands

Read whichever task-runner files exist:

- `package.json` — extract `scripts.test`, `scripts.lint`, `scripts.build`, `scripts.dev`, `scripts.start`
- `Makefile` — read target lines (lines of the form `<target>: ...` plus any comment above it explaining the target)
- `justfile`, `Taskfile.yml` — extract named recipes / tasks
- `pyproject.toml` — read `[tool.poetry.scripts]` or `[project.scripts]`
- `Cargo.toml` — read `[[bin]]` declarations

For each role (test / lint / build / run or dev), pick the single most-canonical command. If both a local and a CI variant exist (e.g., `pnpm test` vs `pnpm test:ci`), prefer the CI variant for the memory file — it's the one that must pass.

### 1c. Existing memory file (extend mode only)

Read `EXISTING_CONTENT`. Note:
- Which canonical sections are present: Project conventions / Domain vocabulary / NEVER-MUST / Pointers / Commands
- Which sections are missing or empty
- Any content that appears stale relative to the artifacts just read (e.g., a "Framework: Jest" entry when testing artifact now says Vitest)

### 1d. Repo root README

Read `README.md`'s first heading and first paragraph. Extract:
- **Project name** — from the first heading (strip the `#`)
- **One-liner** — the first paragraph (may be 1–2 sentences; do not copy more than 2 sentences)

If `README.md` doesn't exist or is empty, note that; the memory file header will use the repo directory name as a fallback.

### 1e. Compile candidate content in memory

Hold:

- Project name + one-liner (from 1d)
- **Pointers candidate list**: for each artifact that exists, one entry: `[Title](path) — one-line summary`
- **Conventions seed**: 3–7 stable patterns derivable from constitution + architecture (test framework, error-handling approach, logging library, API style, etc.). Only include patterns that are both stable and non-obvious from reading the code.
- **Vocabulary seed**: 3–5 terms from GLOSSARY.md (the most-frequent in code, or the most-dangerous to misunderstand). If no GLOSSARY.md exists, leave this empty.
- **NEVER/MUST seed**: each principle from the constitution that carries a MUST, SHALL, or NEVER directive. Copy the directive verbatim, not the rationale.
- **Commands**: test / lint / build / run or dev commands from 1b

## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for memory-file-specific problems. Every diagnose finding must be **evidence-cited** with specific file paths or concrete quotes. Abstract "best practice" suggestions are not allowed.

### 1.5a. Memory-file diagnose categories

For each category below, scan within what Step 1 already read (no extra file reads unless needed within the budget). One strong candidate per category is the target; the aggregate cap of 5 is enforced in 1.5b after dropping unsupported candidates.

- **Missing pointers to artifacts that exist.** `EXISTING_CONTENT` has no pointer to an artifact that is present on disk. Evidence: artifact path + the absence of any mention in `EXISTING_CONTENT`.
- **Stale entries contradicting current code.** A convention line in `EXISTING_CONTENT` says one thing (e.g., "uses Jest") but an artifact says the opposite (e.g., TESTING.md says "Vitest"). Evidence: the memory-file quote + the artifact path + the contradicting line.
- **Items better enforced as hooks than held in memory.** A rule like "always run tests before commit" is unreliable as a memory line that agents might miss; a pre-commit hook would enforce it deterministically. Evidence: the memory-file line verbatim.
- **Rules that belong in the constitution rather than in memory.** A MUST/NEVER line in memory doesn't appear in `docs/constitution.md` and is strong enough to be a constitution principle. Evidence: the memory-file line + the fact that constitution either lacks it or covers it more weakly.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline
- `evidence`: specific file paths or verbatim quotes
- `proposed_addition` OR `proposed_removal`: for additions, the exact line to add; for removals, the exact line to delete (memory-file diagnose may suggest *removals* of stale content, not only additions)

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence.

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence strength (direct quote or path > inferred)
3. Impact (prevents future agent confusion > improves consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3 is skipped silently.

## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each entry in `EXISTING_CONTENT` against the current artifacts and code state. The goal is to detect entries that have gone stale.

### 1.6a. Drift categories for memory-file

- **Pointer to deleted file.** A pointer like `[Architecture](docs/ARCHITECTURE.md)` resolves to a missing file. (Overlaps with coherence-check Tier 1; surface here too so the user can fix in audit context.) Evidence: file-system check of the linked path.
- **Convention line contradicted by code.** A convention says "use Pytest" but the code uses Vitest. Evidence: code path.
- **Stale command.** A `## Commands` entry uses a command name no longer present in package.json / Makefile. Evidence: task-runner file path.
- **Glossary section terms out of sync.** The 3–5 highlighted terms in the memory file no longer match the most-frequent glossary terms. Evidence: glossary current state.
- **NEVER/MUST drift.** A NEVER/MUST line that no longer maps to any constitution principle (constitution may have dropped or weakened it). Evidence: constitution diff.
- **Provenance re-evaluation.** Suggestion-added lines carry HTML-comment provenance markers (`<!-- provenance: bootstrap suggestion <date>; evidence: <summary> -->`). For each such marker, re-evaluate whether the suggestion is still warranted:
  - If the original evidence pattern is STILL present (the code has not changed), the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (code now matches the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (pointer-broken / convention-contradicted / stale-command / glossary-out-of-sync / never-must-drift / aspiration-met / aspiration-still-pending), `entry` (the memory-file text being challenged), `evidence` (artifact or file paths showing the current state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.

## Step 2: Announce Findings

One short message (3–6 sentences; 3–7 when `SUGGEST=on` extends with the diagnose-mention sentence). State what you read and the headline finding.

**Normal mode example:**

> "Here's what I picked up: project is 'Acme API — a multi-tenant billing service' (from README). Other artifacts on disk: constitution, architecture, testing, glossary, domain — design was skipped this run. CI uses `pnpm test` and `pnpm lint`. I'll synthesize the memory file with pointers to those, the constitution's MUSTs as NEVER/MUST rules, 3 glossary highlights, and the canonical run commands. A few questions, then a draft."

**With `SUGGEST=on` AND Step 1.5 produced ≥1 candidate:**

> "…and I found a few things in the existing memory file worth flagging — I'll show those after we confirm what to include."

**Extend mode:**

> "Your existing memory file covers [sections]. I scanned the current artifacts and found [gaps / stale entries]. I'll ask about those, then propose additions."

**Audit mode:**

> "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X pointer/convention/command issues, Y provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan already answered it definitively.

### Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)

Ask one question per drift finding (do NOT bundle — drift items often have nuanced individual resolutions):

```
Question: "Drift detected: <entry summary>. Current state: <evidence>. What's the right resolution?"

Options:
  - "Update the memory file to match current state"
  - "Keep the entry — current state is wrong / will be fixed"
  - "Remove the entry — no longer applies"
```

For **provenance re-evaluation** findings, the question is different:

```
Question: "Aspirational entry '<entry>' was added on <date>. Evidence at that time: <original evidence>. Current code state: <current evidence>. Has this aspiration been realized?"

Options:
  - "Yes — code has caught up. Remove the provenance marker (promote to normal)."
  - "No — code still has the original problem. Keep as aspirational; refresh the marker date."
  - "Drop the entry — we've decided not to pursue this aspiration."
```

Record each resolution. Apply during Step 4 (Draft Synthesis).

### Q1 — Which canonical sections to include (multi-select)

```
Question: "Which sections should the memory file have?"

Multi-select (all recommended for non-trivial projects):
  - "Project conventions" (stable patterns: framework, error handling, logging)
  - "Domain vocabulary" (3-5 terms + pointer to GLOSSARY.md if it exists)
  - "NEVER / MUST" (hard rules; seeded from constitution)
  - "Pointers" (linkdump to docs/{constitution, ARCHITECTURE, …})
  - "Commands" (test, lint, build, run/dev)
  - "All of the above (Recommended)"
```

### Q1.5 — Confirm suggested additions and removals (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some things I'd suggest changing in the memory file.
These are opinionated — pick any you want to apply:"

Multi-select. For each Step 1.5 candidate, list as:
  - [suggestion · <severity> · <evidence-summary>] <title>   (for additions)
  - [suggestion · removal · <evidence-summary>] <title>       (for removals)
    Evidence: <evidence>
    Proposed change: <one-line summary>

Always include "None of these — keep the memory file descriptive only" as
the last option.

Use the harness's multi-select question tool. Do not present as plain text.
```

If the user picks none, treat as "no suggestions accepted" and proceed to Q2. Accepted additions carry into Step 4 with provenance markers. Accepted removals: the stale line is simply omitted from the synthesized draft — no marker needed.

### Q2 — Confirm auto-extracted pointers (multi-select)

```
Question: "Which artifacts should be pointed to from the memory file?"

Multi-select, pre-checked for all that exist on disk:
  - "docs/constitution.md" (if exists)
  - "docs/ARCHITECTURE.md" (if exists)
  - "docs/TESTING.md" (if exists)
  - "docs/GLOSSARY.md" (if exists)
  - "docs/DOMAIN.md" (if exists)
  - "docs/DESIGN.md" (if exists)
  - "README.md"
  - "docs/adr/" (if the directory exists)
  - "docs/specs/" (if the directory exists)
  - "Add another pointer (free-form)"
```

### Q3 — Free-form additions for "project conventions"

```
Question: "Anything the agent should know about working in this project
that isn't visible from the other artifacts? For example:
- Which tests are flaky and should be retried
- How to handle DB migrations locally
- Gotchas in the local dev setup
- Which decisions are pending and agents should not re-litigate

Free-form text. Skip if nothing to add."
```

### Q4 — Confirm NEVER/MUST list (multi-select)

```
Question: "Here are the NEVER/MUST rules I'd seed from the constitution.
Confirm or prune:"

Multi-select pre-checked. List each MUST, SHALL, or NEVER principle from the
constitution as one line each. Allow free-form additions at the end.
```

## Step 4: Draft & Show to User

Synthesize the draft using:

- Project name + one-liner (from Step 1d)
- Q1 sections chosen
- Accepted Q1.5 additions (rendered with provenance markers — see Step 6)
- Accepted Q1.5 removals (stale lines simply omitted — no marker)
- Q2 confirmed pointers
- Q3 free-form additions
- Q4 confirmed NEVER/MUST list
- Commands (auto-included if "Commands" section was chosen in Q1; from Step 1b)
- Q0 drift resolutions (per drift item: update / keep / remove)
- Q0 provenance re-evaluations (per aspirational entry: promote / refresh / drop)

Use the Output Template (below). Show the full draft.

**Character budget check:** before presenting, compute the draft's character count. If it is ≥ 90% of `memory_file.character_limit`:

> "This draft is at <N>% of the character limit (<X>/<limit> chars). I'd recommend trimming one or more sections before writing. Which would you like to shorten or remove?"

Surface the question with a multi-select of sections. Only proceed to the approval question once the draft is under 90% (or the user overrides).

Then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip the memory file"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture the user's free-form notes; apply; re-show; re-ask Step 4. Run the character budget check again on each iteration. Cap at **3 iterations**:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip the memory file for now, or
> (c) supply the file yourself — you write the markdown, I'll save it?"

**On Start over:** restart Step 3 from Q1 (scan findings carry over; user answers reset).

**On Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 6: Atomic Write & Config Writeback

```bash
cat > "$FILE_PATH.tmp" <<'EOF'
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **extend** mode: merge `EXISTING_CONTENT` + new sections / refinements into a single document, then write atomically. Preserve existing accurate sections; replace or add only what changed. Accepted Q1.5 removals: omit the stale lines from the merged content.

Report to the coordinator one of:

- `created` (mode = create, full draft written)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)
- `skipped (user declined)` (user chose "I'll maintain manually" at Step 0c)
- `skipped (character budget exceeded)` (draft could not be brought within `character_limit`)

Also report the resolved `FILE_PATH` so the coordinator's run summary can mention it.

### Provenance markers for accepted Q1.5 additions

Each accepted Q1.5 addition becomes a regular line in the relevant memory-file section. Append an HTML comment immediately after the line (memory files prefer minimal visual noise — blockquote markers or bold callouts would pollute every agent's reading experience):

```markdown
- <new line content>
<!-- provenance: bootstrap suggestion 2026-05-25; evidence: <summary> -->
```

Replace the date with today's date. The audit skill reads this marker on re-runs to ask whether the aspiration has been realized.

For *removals* accepted in Q1.5, simply omit the line from the synthesized draft — no marker needed.

### Config writeback (Step 0e follow-through)

If Step 0e marked this as a new path (i.e., `memory_file.path` was null at the start of Step 0), edit `.sublime-skills/config.yml` to set `memory_file.path: <FILE_PATH>`. Use a targeted Edit: find the existing `path: null` line under the `memory_file:` block and replace it — do not regenerate the whole file.

After the edit, run:

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/validate-config.sh .sublime-skills/config.yml
```

If validation fails, surface the error verbatim to the user and do NOT proceed. The config must pass validation before the skill can report success.

## Output Template

```markdown
# <Project Name>

<One-sentence description from README first paragraph.>

## Project conventions

- <Convention 1>
- <Convention 2>
- (3–7 total; only stable, non-obvious rules)

## Domain vocabulary

(See [GLOSSARY.md](docs/GLOSSARY.md) for the full vocabulary.)

Key terms:
- **<Term>** — <brief gloss>
- (3–5 entries)

## NEVER / MUST

- NEVER <hard rule>
- MUST <hard rule>
- (each rule traceable to a constitution principle or Q4 addition)

## Pointers

- [Constitution](docs/constitution.md) — principles
- [Architecture](docs/ARCHITECTURE.md) — system shape
- [Testing](docs/TESTING.md) — test strategy
- [Glossary](docs/GLOSSARY.md) — vocabulary
- [Domain Model](docs/DOMAIN.md) — entities
- [Design System](docs/DESIGN.md) — visual tokens
- [ADRs](docs/adr/) — architectural decisions
- [Specs](docs/specs/) — per-feature SDD artifacts

## Commands

```bash
<test command>
<lint command>
<build command>
<run / dev command>
```
```

**Omit** a section entirely if the user deselected it in Q1. Omit individual pointers not confirmed in Q2. For the Domain vocabulary section: if no GLOSSARY.md exists, omit the `(See GLOSSARY.md ...)` pointer line; list the 3–5 seeds directly.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Running before the other 6 artifacts are settled | Memory file is the LAST stage; coordinator orders this. If invoked early, ask the coordinator to reorder. |
| Maintaining multiple memory files | Bootstrap maintains one. Ask which is canonical (Step 0c); leave the others alone. |
| Duplicating content from the other artifacts | Link, don't duplicate. Domain vocabulary is 3–5 terms + pointer, not the full glossary. |
| Forgetting the config writeback in Step 6 | If FILE_PATH was determined in Step 0d (none existed), `memory_file.path` MUST be written back to config. Subsequent SDD runs (ss-sdd-maintaining-memory-file) depend on this. |
| Skipping validate-config.sh after the config writeback | The targeted edit might break adjacent YAML; always validate. |
| Exceeding character_limit | Warn at 90%; refuse to write past 100%. Trim with the user first. |
| Surfacing diagnose candidates without file-path or quote evidence | Drop them; only evidence-cited candidates pass the gate. |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest. |
| Forgetting the HTML-comment provenance marker on an accepted Q1.5 addition | The audit skill reads this marker for drift detection; without it, drift detection breaks. |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off; do not run-but-suppress. |
| Bundling multiple questions in one ask | One question per turn. |
| Looping past 3 tweak iterations | Surface to user with bail options. |
| Overwriting in extend mode | Extend merges; only replace overwrites. |
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |

## Red Flags

- About to write the file before the other 6 stages are done → STOP; check coordinator ordering
- About to skip the config writeback → STOP; subsequent SDD runs (`ss-sdd-maintaining-memory-file`) will mis-detect or skip the file
- About to maintain a second memory file in this run → STOP; bootstrap is one-per-project
- About to copy the full glossary into the memory file → STOP; link to GLOSSARY.md, then list 3–5 sample terms only
- About to run Step 1.5 when `SUGGEST=off` → STOP; skip it entirely
- About to ask the user a question without the harness's interactive tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to write the file before user approval → STOP; Step 4 approval is mandatory
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing memory file in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

Like all discovery skills, the per-file conversation is interactive: scan → announce → ask → draft → refine. Routing through a coordinator (subagent returns findings → coordinator paraphrases → user replies → re-dispatch) wastes turns and risks every paraphrase drifting from intent.

Additionally, this skill must read the content of the other six artifacts that were just written in the same bootstrap run. Running inline means those writes are visible with no coordination lag. The five sibling discovery skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-testing`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`) follow the same pattern for the same reason.

The incremental-update counterpart (`ss-sdd-maintaining-memory-file`) operates differently: it runs as a dispatched subagent after each SDD feature run, reads the spec/plan/ADRs for that run, and updates the memory file minimally. That skill does not do the full discover-draft-refine loop that this skill does.
