---
name: bootstrapping-project
description: Use to set up a project for spec-driven development - walks the user through each convention file (constitution, architecture, glossary, domain) with deep per-file project analysis via dedicated subagents, then scaffolds .sdd/config.yml and the supporting directories. User-invoked, not part of the SDD pipeline.
---

# Bootstrapping Project

## Overview

You are the coordinator for project bootstrap. You hold the workflow's shape; the deep per-artifact analysis happens in fresh subagent contexts (one subagent per convention file). After all convention files are settled, you copy the config scaffold, edit it to reflect what was actually created, validate it, and commit.

**Core principle:** Per-artifact analysis is read-heavy; dispatch it to a fresh subagent (clean context, focused skill). User discussion and file writing happens in this coordinator.

**Announce at start:** "I'm using the bootstrapping-project skill to set up SDD for this project."

## What This Skill Doesn't Do

- It does NOT run the SDD pipeline. That's `sdd-coordinator`.
- It does NOT write specs or plans. That's pipeline work.
- It does NOT enforce anything globally. Convention files are referenced by pipeline skills only if their `context.<name>_path` resolves to an existing file.
- It does NOT dispatch sub-subagents. Each subagent it dispatches is a leaf — they cannot dispatch further.

## Hard Gates

- Do NOT skip the per-file detect+ask loop — every convention file gets its own decision point
- Do NOT regenerate the config YAML from scratch — copy the scaffold verbatim, then Edit specific keys
- Do NOT commit until `validate-config.sh` passes
- Do NOT dispatch multiple proposer subagents in parallel — sequential, one file at a time, so the user can reason about each
- Do NOT overwrite an existing convention file without explicit user direction (Replace mode requires affirmative user choice)
- ALWAYS use the harness's interactive question tool (`AskUserQuestion` in Claude Code, or any harness equivalent) when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool (`TodoWrite` in Claude Code's older harness, `TaskCreate` / `TaskUpdate` in newer harnesses, `todo` in Codex, or any harness equivalent) to track progress through the bootstrap. Build the initial list right after Step 1 (Detect): one todo per convention file (constitution, architecture, glossary, domain) plus one each for supporting directories, config copy, config edit-to-reflect-reality, validate-config, gitignore, and the final commit. Mark `in_progress` when you start an item and `completed` immediately after — don't batch updates. Bootstrap is short but multi-step, and the user is watching this list to know which file you're working on.

## Checklist

Proceed through these in order:

1. Detect existing setup via discovery script
2. For each convention file (constitution → architecture → glossary → domain): detect → ask → dispatch proposer subagent → discuss → write
3. Create supporting directories (`docs/adr/`, `docs/specs/`, `docs/handoff/`) with stub READMEs
4. Copy config scaffold to `.sdd/config.yml`
5. Edit config to reflect reality (set `context.<name>_path` to null for skipped files; adjust if non-default paths)
6. Run `validate-config.sh`; fix-and-retry on FAIL (cap 3 attempts)
7. Ensure `.sdd/local.yml` is gitignored
8. Single commit
9. Report and direct user to `sdd-coordinator`

## Step 1: Detect Existing Setup

```bash
./spec-driven-development/scripts/discover-context.sh
```

Cache the JSON output. For each convention file: the corresponding key (`constitution`, `architecture`, `glossary`, `domain`) is either a string (file exists) or `null` (no file at the configured path, or config doesn't exist yet).

## Step 1.5: Build the Todo List

Before starting the per-file loop, build the progress todo list with the harness's todo/task tool. Use these items:

1. Constitution (`docs/constitution.md`)
2. Architecture (`docs/ARCHITECTURE.md`)
3. Glossary (`docs/GLOSSARY.md`)
4. Domain model (`docs/DOMAIN.md`)
5. Create `docs/adr/`, `docs/specs/`, `docs/handoff/` with READMEs
6. Copy config scaffold to `.sdd/config.yml`
7. Edit config to reflect skipped files
8. Run `validate-config.sh` (fix-and-retry loop)
9. `.gitignore` housekeeping
10. Commit

Mark each `in_progress` when you start it and `completed` the instant it's done. Never batch — the user reads this list to follow along with what you're doing.

## Step 2: Per-File Loop

Iterate convention files in this order: **constitution, architecture, glossary, domain.** For each:

### 2a. Detect

From the cached discovery output, check if the file at the default path (or configured path, if config already exists) is present.

Default paths the scaffold will set:
- Constitution: `docs/constitution.md`
- Architecture: `docs/ARCHITECTURE.md`
- Glossary: `docs/GLOSSARY.md`
- Domain: `docs/DOMAIN.md`

### 2b. Ask the User

**File does NOT exist** — ask:

> "Project doesn't have a `<filename>` yet. Want me to analyze the project and propose one? (yes/no)"

On no: record this file as **skipped**; continue to the next file.

**File DOES exist** — ask:

> "`<filename>` already exists. What would you like to do?
> - **Skip** — leave it as-is (default)
> - **Extend** — I'll analyze the project and propose additions / refinements to merge in
> - **Replace** — I'll analyze the project and propose a fresh draft to overwrite the existing file"

Record the chosen mode. On **Skip**: continue to the next file.

### 2c. Dispatch the Proposer Subagent

For modes Create, Extend, or Replace, dispatch a `general-purpose` subagent with the corresponding `proposing-X` skill:

| Convention file | Subagent skill |
|---|---|
| Constitution | `proposing-constitution` |
| Architecture | `proposing-architecture` |
| Glossary | `proposing-glossary` |
| Domain model | `proposing-domain-model` |

**Subagent dispatch prompt template:**

```
You are analyzing the project to propose content for a convention file.

Use the `<skill-name>` skill via the Skill tool.

REPO_ROOT: <absolute path to repo root>
MODE: create | extend | replace
EXISTING_CONTENT: (only for extend mode — the verbatim current file content)
FILE_PATH: <where the file will be written>

Return your findings (what you observed) and proposed content (the markdown
draft). Do not write to any file yourself; do not interact with the user.
```

The subagent returns:
- **`findings`** — structured observations grouped by category (what they read, what stood out)
- **`proposed_content`** — the markdown draft (for extend mode: a diff or additions section)

### 2d. Discuss with User

Present the findings + proposed_content to the user:

> "Here's what the analyzer found, and the draft it proposes:
>
> **Findings:**
> <findings>
>
> **Proposed content for `<filename>`:**
> <proposed_content>
>
> Want to: **approve** (write as-is) / **request changes** (tell me what to adjust) / **abort** (skip this file)?"

**On approve:** continue to 2e.

**On request changes:** capture the user's notes. Re-dispatch the proposer subagent with the original inputs PLUS the user's notes appended: "Address these specific changes the user asked for: <notes>". Loop back to 2d. **Cap: 3 iterations.** After 3 failed iterations, surface to the user with: "I've made 3 attempts and the proposal still isn't matching your intent. Want to (a) accept the current draft anyway, (b) skip this file entirely, or (c) write the content yourself?"

**On abort:** record as skipped; continue to the next file.

### 2e. Write the File

Atomic write to the target path:

```bash
# Write to .tmp, then atomic mv
cat > "$FILE_PATH.tmp" <<EOF
<proposed_content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **Extend** mode: the merged content (existing + additions) is what gets written, not just the additions.

Mark this file as **created/extended/replaced**, capture the final path (in case it differs from the scaffold default — rare).

### 2f. Next File

Continue to the next convention file in the order. Repeat until all four are settled.

## Step 3: Create Supporting Directories

```bash
mkdir -p docs/adr docs/specs docs/handoff
```

Write each stub README:

**`docs/adr/README.md`:**

```markdown
# Architecture Decision Records

Each ADR captures one significant architectural decision with context,
chosen approach, consequences, and alternatives considered.

Filename pattern: `NNNN-kebab-case-title.md` (zero-padded 4 digits).
Status lifecycle: Proposed → Accepted → (optionally) Superseded by ADR-NNNN | Deprecated.

ADRs are written by the `maintaining-adrs` skill during the SDD pipeline,
or manually by anyone with a decision worth capturing.
```

**`docs/specs/README.md`:**

```markdown
# Specs

Each subdirectory is one feature, with `spec.md`, `plan.md`, and
`state.json` (SDD pipeline state, deleted on completion).

Directory pattern: `NNN-kebab-name/` (zero-padded 3 digits).
```

**`docs/handoff/README.md`:**

```markdown
# Handoff Documents

Generated at the end of each SDD pipeline run (Stage 14). Each handoff
summarizes what was built, references the source artifacts (spec, plan,
ADRs), and gives a fresh agent enough context to continue work — for
example, when iterating on PR feedback in a new session.

Filename pattern: `YYYY-MM-DD-<kebab-title>.md`. Sortable by date.

Handoff docs are written by the `generating-handoff` skill. They redact
secrets (API keys, tokens, passwords, JWTs, private keys) so they're
safe to share or commit.
```

If any of these READMEs already exist with the same content, skip them. If they exist with different content, ask the user before overwriting.

## Step 4: Copy Config Scaffold

```bash
mkdir -p .sdd
cp ./project-bootstrap/scaffolds/config.yml .sdd/config.yml
```

This is a verbatim copy. **Do NOT regenerate the YAML.** The scaffold is the single source of truth for the config's shape and defaults.

## Step 5: Edit Config to Reflect Reality

For each convention file the user **skipped** (whether the file existed and they chose Skip, or it didn't exist and they declined to create one): set the corresponding `context.<name>_path` in `.sdd/config.yml` to `null` via the Edit tool.

For each convention file **created/extended/replaced**: if the final path differs from the scaffold default, update the corresponding key to the actual path.

Example: user skipped the glossary. Edit changes:

```yaml
  glossary_path: docs/GLOSSARY.md
```

to:

```yaml
  glossary_path: null
```

Do NOT touch any keys the user didn't ask about (preflight, grill, memory_file, finishing keep their scaffold defaults).

## Step 6: Validate

```bash
./spec-driven-development/scripts/validate-config.sh .sdd/config.yml
```

| Exit code | Action |
|---|---|
| `0` (PASS) | Proceed to Step 7 |
| `1` (FAIL) | Read the findings from stderr; fix each issue in `.sdd/config.yml` (or fix the underlying file/directory if it's an orphan path); re-run the validator. **Cap: 3 attempts.** After 3 failed attempts, halt and surface to user with the remaining findings. |
| `2` (config not found) | This shouldn't happen — Step 4 just copied it. Halt and surface as a serious error. |
| `3` (usage error) | Halt and surface — coordinator bug. |

For ambiguous fixes (e.g., orphan path → "should this be null, or did I write the wrong path?"), confirm with the user before editing.

## Step 7: `.gitignore` Housekeeping

If `.sdd/local.yml` is NOT already in `.gitignore`, append it:

```bash
# Check first
grep -qE '^\.sdd/local\.yml$' .gitignore 2>/dev/null || {
  echo "" >> .gitignore
  echo "# SDD per-developer overrides (committed config lives at .sdd/config.yml)" >> .gitignore
  echo ".sdd/local.yml" >> .gitignore
}
```

`.sdd/config.yml` itself is committed (it's project-wide config).

Per-feature state at `docs/specs/NNN-name/state.json` is committed during the SDD pipeline; no gitignore entry needed.

## Step 8: Commit

```bash
git add docs/constitution.md docs/ARCHITECTURE.md docs/GLOSSARY.md docs/DOMAIN.md \
        docs/adr/ docs/specs/ docs/handoff/ \
        .sdd/config.yml [.gitignore]
git commit -m "chore: initialize SDD project context"
```

Only `git add` the files that were actually created or modified in this run. Don't add files the user opted out of (skipped + file doesn't exist → not staged).

Use the standard project commit conventions if `git log` shows a different style (Conventional Commits, "feat:" prefixes, etc.).

## Step 9: Report

```
SDD bootstrap complete.

Convention files:
- docs/constitution.md — <created | extended | replaced | skipped (file exists) | skipped (declined)>
- docs/ARCHITECTURE.md — <...>
- docs/GLOSSARY.md — <...>
- docs/DOMAIN.md — <...>

Directories:
- docs/adr/ (with README)
- docs/specs/ (with README)
- docs/handoff/ (with README)

Config:
- .sdd/config.yml created and validated (PASS)
- Skipped files have their context.<name>_path set to null

Next steps:
- Run the sdd-coordinator skill to start your first feature
- Or, re-run bootstrapping-project later to extend a convention file
```

## Re-Running on an Existing Project

If `.sdd/config.yml` already exists when this skill starts, treat it as a re-run:

- The per-file loop still walks each convention file — but now Detect will find the configured path (not the default), and the discussion is more about Extend/Replace than Create.
- Step 4 (copy scaffold) is skipped if the config exists — the user already has one. Step 5 (edit to reflect reality) still runs: any newly-created file in this re-run gets its `<name>_path` set; any newly-skipped file gets nulled.
- Step 6 (validate) always runs.

The skill is safe to invoke repeatedly. It never destroys user-authored content without explicit Replace approval.

## Subagent Failure Protocol

If a proposer subagent returns malformed output (missing findings or proposed_content), times out, or crashes:

1. **Retry once** with the same inputs. Transient failures are common; one retry costs little.
2. If the retry also fails, surface to the user:

   > "The `<skill-name>` analyzer didn't return a usable proposal (reason: <observed issue>). Options:
   > - **Retry** (third attempt)
   > - **Skip this file** (proceed without)
   > - **Write the content yourself** (you provide the markdown; I'll save it)
   > - **Abort the whole bootstrap**"

3. Never substitute the coordinator's own analysis for the failed subagent's. The subagent is the read-heavy specialist; you don't pretend to do its job.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Doing the per-file analysis inline in the coordinator | Dispatch the proposer subagent; deep analysis is its job |
| Writing convention files without user approval of the proposal | Always discuss findings+proposal first; user approves before write |
| Overwriting an existing file in Extend mode | Extend merges; only Replace overwrites |
| Regenerating the YAML scaffold | Copy verbatim, then Edit specific keys |
| Skipping validate-config.sh | Mandatory; bootstrap isn't done until it passes |
| Looping the validator more than 3 times | Cap is 3; after that, surface to user |
| Bundling multiple commits (one per file) | One bootstrap = one commit |
| Auto-deciding Skip/Extend/Replace | Always ask the user explicitly |

## Red Flags

- About to dispatch two proposer subagents in parallel → STOP; sequential only
- About to write a convention file without showing the user the proposal first → STOP
- About to commit before `validate-config.sh` passes → STOP
- About to overwrite an existing file without the user picking Replace → STOP
- About to do the per-file deep analysis yourself inline → STOP; that's the subagent's job
- About to dispatch a sub-subagent from inside a proposer → not your concern; proposer subagents are leaf skills
