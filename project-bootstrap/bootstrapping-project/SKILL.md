---
name: bootstrapping-project
description: Use to set up a project for spec-driven development - walks the user through each convention file (constitution, architecture, glossary, domain, design) by loading the matching discovering-<topic> inline skill for each, then scaffolds .sublime-skills/config.yml and the supporting directories. User-invoked, not part of the SDD pipeline.
---

# Bootstrapping Project

## Overview

You are the coordinator for project bootstrap. You hold the workflow's shape. The five convention files (constitution, architecture, glossary, domain, design) are each handled by a dedicated `discovering-<topic>` skill loaded inline into your context. Each discovering-X skill performs its own code scan, conversation with the user, and atomic write — you don't reach inside its work, you just route to it. After all five files are settled, you copy the config scaffold, edit it to reflect what was actually created, validate it, and commit.

**Core principle:** Per-artifact discovery is a back-and-forth with the user, not a one-shot extraction. Code reveals *what*; the user reveals *why*. Each discovering-X skill orchestrates that conversation. Your job is the surrounding workflow (detection, mode choice, config, commit) — not the per-artifact discussion.

**Announce at start:** "I'm using the bootstrapping-project skill to set up SDD for this project."

## What This Skill Doesn't Do

- It does NOT run the SDD pipeline. That's `sdd-coordinator`.
- It does NOT write specs or plans. That's pipeline work.
- It does NOT enforce anything globally. Convention files are referenced by pipeline skills only if their `context.<name>_path` resolves to an existing file.
- It does NOT perform the per-file discovery itself. Each `discovering-X` skill handles its own scan, conversation, and write — you just route to the right one.

## Hard Gates

- Do NOT skip the per-file detect+ask loop — every convention file gets its own decision point
- Do NOT regenerate the config YAML from scratch — copy the scaffold verbatim, then Edit specific keys
- Do NOT commit until `validate-config.sh` passes
- Do NOT run discovering-X skills in parallel — load them sequentially, one file at a time, so the user can reason about each
- Do NOT dispatch any discovering-X skill as a subagent. All five are inline; load them via your harness's skill mechanism.
- Do NOT bypass a discovering-X skill — even if you "know what the proposal would be," the per-file conversation is the skill's job, not yours.
- Do NOT overwrite an existing convention file without explicit user direction (Replace mode requires affirmative user choice)
- ALWAYS use the harness's interactive question tool when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool to track progress through the bootstrap. Build the initial list right after Step 1 (Detect): one todo per convention file (constitution, architecture, glossary, domain, design) plus one each for supporting directories, config copy, config edit-to-reflect-reality, validate-config, gitignore, and the final commit. Mark `in_progress` when you start an item and `completed` immediately after — don't batch updates. Bootstrap is short but multi-step, and the user is watching this list to know which file you're working on.

## Checklist

Proceed through these in order:

1. Detect existing setup via discovery script
2. For each convention file (constitution → architecture → glossary → domain → design): detect → ask → load the matching `discovering-<topic>` skill inline → record outcome
3. Create supporting directories (`docs/adr/`, `docs/specs/`) with stub READMEs
4. Copy config scaffold to `.sublime-skills/config.yml` and create empty `.sublime-skills/config-local.yml` (preserving any existing local overrides)
5. Edit config to reflect reality (set `context.<name>_path` to null for skipped files; adjust if non-default paths)
6. Run `validate-config.sh`; fix-and-retry on FAIL (cap 3 attempts)
7. Ensure `.sublime-skills/config-local.yml` is gitignored
8. Single commit
9. Report and direct user to `sdd-coordinator`

## Step 1: Detect Existing Setup

```bash
./spec-driven-development/scripts/discover-context.sh
```

Cache the JSON output. For each convention file: the corresponding key (`constitution`, `architecture`, `glossary`, `domain`, `design`) is either a string (file exists) or `null` (no file at the configured path, or config doesn't exist yet).

## Step 1.5: Build the Todo List

Before starting the per-file loop, build the progress todo list with the harness's todo/task tool. Use these items:

1. Constitution (`docs/constitution.md`)
2. Architecture (`docs/ARCHITECTURE.md`)
3. Glossary (`docs/GLOSSARY.md`)
4. Domain model (`docs/DOMAIN.md`)
5. Design (`docs/DESIGN.md`)
6. Create `docs/adr/`, `docs/specs/` with READMEs
7. Copy config scaffold to `.sublime-skills/config.yml` and create empty `.sublime-skills/config-local.yml`
8. Edit config to reflect skipped files
9. Run `validate-config.sh` (fix-and-retry loop)
10. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
11. Commit

Mark each `in_progress` when you start it and `completed` the instant it's done. Never batch — the user reads this list to follow along with what you're doing.

## Step 2: Per-File Loop

Iterate convention files in this order: **constitution, architecture, glossary, domain, design.** For each:

### 2a. Detect

From the cached discovery output, check if the file at the default path (or configured path, if config already exists) is present.

Default paths the scaffold will set:
- Constitution: `docs/constitution.md`
- Architecture: `docs/ARCHITECTURE.md`
- Glossary: `docs/GLOSSARY.md`
- Domain: `docs/DOMAIN.md`
- Design: `docs/DESIGN.md`

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

### 2c. Load the Matching `discovering-X` Skill Inline

For modes Create, Extend, or Replace, route to the per-file skill, loading it inline. All five convention files use the same uniform mechanism — no subagent dispatch, ever.

| Convention file | Skill loaded (inline) |
|---|---|
| Constitution | `discovering-constitution` |
| Architecture | `discovering-architecture` |
| Glossary | `discovering-glossary` |
| Domain model | `discovering-domain-model` |
| Design | `discovering-design` |

**How to load:**

Load the matching `discovering-<topic>` skill inline (via your harness's skill mechanism). Pass these inputs (the skill's documented input convention):

```
Load skill: discovering-<topic>

REPO_ROOT:        <absolute path to repo root>
MODE:             create | extend | replace
EXISTING_CONTENT: (only for extend / replace — the verbatim current file content)
FILE_PATH:        <target path — e.g., docs/constitution.md, docs/ARCHITECTURE.md,
                   docs/GLOSSARY.md, docs/DOMAIN.md, docs/DESIGN.md, or whatever
                   the config'd context.<name>_path resolves to>
```

The skill handles the entire interaction itself — code scan, user discussion (one question at a time, structured choices, free-form where appropriate), draft preview, refinement loop (cap 3 iterations), and atomic write. **You do NOT run a separate discuss-and-write step for any convention file** — each discovering-X skill performs both internally.

When the skill returns control to you, it reports one of:

- `created` — file written via the Build path (or, for design only, `created via build` / `created via import from <path>`)
- `extended` — merged content written (extend mode)
- `replaced` — full draft written over previous content (replace mode)
- `skipped (declined mid-skill)` — user bailed out partway through the skill's own flow

Record that outcome alongside the path, then proceed to 2d.

### 2d. Next File

Continue to the next convention file in the order. Repeat until all five are settled.

## Step 3: Create Supporting Directories

```bash
mkdir -p docs/adr docs/specs
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

Each subdirectory is one feature, containing `spec.md` and `plan.md`.

Directory pattern: `NNN-kebab-name/` (zero-padded 3 digits).
```

If any of these READMEs already exist with the same content, skip them. If they exist with different content, ask the user before overwriting.

## Step 4: Copy Config Scaffold and Create Local Overlay

```bash
mkdir -p .sublime-skills
[ -f .sublime-skills/config.yml ] || cp ./project-bootstrap/scaffolds/config.yml .sublime-skills/config.yml
[ -f .sublime-skills/config-local.yml ] || touch .sublime-skills/config-local.yml
if [ ! -f .sublime-skills/.gitignore ]; then
  cat > .sublime-skills/.gitignore <<'EOF'
# Per-developer config overlay (each developer's own; not committed)
config-local.yml

# SDD per-run state file (local-only orchestration metadata; never committed)
state.json
EOF
fi
```

`.sublime-skills/.gitignore` is created as a two-entry file: `config-local.yml` (per-developer overlay) and `state.json` (per-run SDD state). It's committed (the ignore is project-wide convention). On a re-run, the file is left alone — see Step 7 for the append-if-missing logic that catches users who may have removed one of the entries.

Both lines are idempotent — they create the file when it's missing, and leave any existing content alone on a re-run. This protects the user's hand-edits to either file across multiple bootstrap invocations.

The `cp` of the scaffold is a verbatim copy of `project-bootstrap/scaffolds/config.yml`. **Do NOT regenerate the YAML.** The scaffold is the single source of truth for the config's shape and defaults; the bootstrap never produces config YAML from scratch.

`.sublime-skills/config-local.yml` is created as a zero-byte file. It's a per-developer overlay: any key set here shadows the matching key in `config.yml` when skills read config. The file is gitignored (Step 7), so each developer can populate it without affecting teammates.

Step 5 below still runs unconditionally — it edits specific keys in `config.yml` (sets `context.<name>_path` to `null` for skipped files) using the `Edit` tool, not by rewriting the file. So newly Skipped convention files are reflected even on a re-run that did not re-copy the scaffold.

## Step 5: Edit Config to Reflect Reality

For each convention file the user **skipped** (whether the file existed and they chose Skip, or it didn't exist and they declined to create one): set the corresponding `context.<name>_path` in `.sublime-skills/config.yml` to `null` with a targeted in-place edit (do not regenerate the file).

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
./spec-driven-development/scripts/validate-config.sh .sublime-skills/config.yml
```

| Exit code | Action |
|---|---|
| `0` (PASS) | Proceed to Step 7 |
| `1` (FAIL) | Read the findings from stderr; fix each issue in `.sublime-skills/config.yml` (or fix the underlying file/directory if it's an orphan path); re-run the validator. **Cap: 3 attempts.** After 3 failed attempts, halt and surface to user with the remaining findings. |
| `2` (config not found) | This shouldn't happen — Step 4 just copied it. Halt and surface as a serious error. |
| `3` (usage error) | Halt and surface — coordinator bug. |

For ambiguous fixes (e.g., orphan path → "should this be null, or did I write the wrong path?"), confirm with the user before editing.

## Step 7: `.gitignore` Housekeeping

Ensure `.sublime-skills/.gitignore` contains both required entries. Step 4 created the file when missing; this step handles the re-run case where a developer may have removed an entry:

```bash
GIT_IGNORE=.sublime-skills/.gitignore
[ -f "$GIT_IGNORE" ] || touch "$GIT_IGNORE"

grep -qE '^config-local\.yml$' "$GIT_IGNORE" || {
  echo "" >> "$GIT_IGNORE"
  echo "# Per-developer config overlay (each developer's own; not committed)" >> "$GIT_IGNORE"
  echo "config-local.yml" >> "$GIT_IGNORE"
}

grep -qE '^state\.json$' "$GIT_IGNORE" || {
  echo "" >> "$GIT_IGNORE"
  echo "# SDD per-run state file (local-only orchestration metadata; never committed)" >> "$GIT_IGNORE"
  echo "state.json" >> "$GIT_IGNORE"
}
```

Both `.sublime-skills/config.yml` and `.sublime-skills/.gitignore` itself are committed (project-wide convention). The root `.gitignore` is NOT modified by this skill any more — all SDD-related ignores live under `.sublime-skills/`.

## Step 8: Commit

```bash
git add docs/constitution.md docs/ARCHITECTURE.md docs/GLOSSARY.md docs/DOMAIN.md docs/DESIGN.md \
        docs/adr/ docs/specs/ \
        .sublime-skills/config.yml [.gitignore]
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
- docs/DESIGN.md — <...>

Directories:
- docs/adr/ (with README)
- docs/specs/ (with README)

Config:
- .sublime-skills/config.yml created and validated (PASS)
- .sublime-skills/.gitignore created with state.json and config-local.yml entries
- Skipped files have their context.<name>_path set to null

Next steps:
- Run the sdd-coordinator skill to start your first feature
- Or, re-run bootstrapping-project later to extend a convention file
```

## Re-Running on an Existing Project

If `.sublime-skills/config.yml` already exists when this skill starts, treat it as a re-run:

- The per-file loop still walks each convention file — but now Detect will find the configured path (not the default), and the discussion is more about Extend/Replace than Create.
- Step 4 (copy scaffold) is skipped if the config exists — the user already has one. Step 5 (edit to reflect reality) still runs: any newly-created file in this re-run gets its `<name>_path` set; any newly-skipped file gets nulled.
- Step 6 (validate) always runs.

The skill is safe to invoke repeatedly. It never destroys user-authored content without explicit Replace approval.

## Inline Skill Failure Protocol

Each discovering-X skill has its own internal failure handling — tweak-iteration caps, start-over bailouts, abort options — and most issues resolve inside the skill. You only see a failure at this level if the skill itself crashes, returns an unrecognized outcome string, or returns control without writing the file when it claimed it would.

If that happens:

1. **Retry once** by re-loading the skill with the same inputs. Transient failures are common; one retry costs little.
2. If the retry also fails, surface to the user:

   > "The `<skill-name>` skill didn't complete cleanly (reason: <observed issue>). Options:
   > - **Retry** (third attempt)
   > - **Skip this file** (proceed without)
   > - **Write the content yourself** (you provide the markdown; I'll save it via atomic write at the configured path)
   > - **Abort the whole bootstrap**"

3. Never substitute the coordinator's own analysis for the failed skill's. The discovering-X skill is the source of truth for its file's content — you don't pretend to do its job, even when it's stuck.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Performing the per-file analysis or discussion in the coordinator | Load the matching discovering-X skill; it owns the scan + conversation. |
| Dispatching a discovering-X skill as a subagent | All five are inline — load them in the coordinator's own context. A subagent dispatch would break the interactive Q&A flow. |
| Running multiple discovering-X skills in parallel | Sequential, one file at a time, so the user can reason about each. |
| Re-doing the user discussion or write after a discovering-X returns | The skill already discussed + wrote internally — your job is to record the outcome and move on. |
| Writing convention files directly from the coordinator | The discovering-X skill is the single source of truth for its file's content. |
| Overwriting an existing file in Extend mode | Extend merges; only Replace overwrites. |
| Regenerating the YAML scaffold | Copy verbatim, then Edit specific keys. |
| Skipping validate-config.sh | Mandatory; bootstrap isn't done until it passes. |
| Looping the validator more than 3 times | Cap is 3; after that, surface to user. |
| Bundling multiple commits (one per file) | One bootstrap = one commit. |
| Auto-deciding Skip/Extend/Replace | Always ask the user explicitly. |

## Red Flags

- About to load two discovering-X skills in parallel → STOP; sequential only
- About to do the per-file scan or discussion yourself inline in the coordinator → STOP; that's the discovering-X skill's job
- About to dispatch a discovering-X as a subagent → STOP; all five are inline — load them in the coordinator's own context
- About to write a convention file from the coordinator → STOP; the discovering-X skill writes
- About to commit before `validate-config.sh` passes → STOP
- About to overwrite an existing file without the user picking Replace → STOP
- About to re-prompt the user for the same file after a discovering-X already returned → STOP; the conversation already happened inside the skill
