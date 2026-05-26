---
name: ss-bs-bootstrapping-project
description: Use to set up a project for spec-driven development - walks the user through each convention file (constitution, architecture, testing, glossary, domain, design) and the agent memory file (CLAUDE.md/AGENTS.md/GEMINI.md/.agents.md) by loading the matching ss-bs-discovering-<topic> inline skill for each, then scaffolds .sublime-skills/config.yml and supporting directories. Asks once at the top whether to run the prescriptive suggestion pass alongside the descriptive scan. User-invoked, not part of the SDD pipeline.
---

# Bootstrapping Project

## Overview

You are the coordinator for project bootstrap. You hold the workflow's shape. The seven convention files (constitution, architecture, testing, glossary, domain, design, memory-file) are each handled by a dedicated `ss-bs-discovering-<topic>` skill loaded inline into your context. Each discovering-X skill performs its own code scan, conversation with the user, and atomic write — you don't reach inside its work, you just route to it. After all seven files are settled, you copy the config scaffold, edit it to reflect what was actually created, validate it, run the cross-artifact coherence check, and commit.

**Core principle:** Per-artifact discovery is a back-and-forth with the user, not a one-shot extraction. Code reveals *what*; the user reveals *why*. Each discovering-X skill orchestrates that conversation. Your job is the surrounding workflow (detection, opt-in switch, mode choice, config, coherence check, commit) — not the per-artifact discussion.

**Announce at start:** "I'm using the ss-bs-bootstrapping-project skill to set up SDD for this project."

## What This Skill Doesn't Do

- It does NOT run the SDD pipeline. That's `ss-sdd-coordinator`.
- It does NOT write specs or plans. That's pipeline work.
- It does NOT enforce anything globally. Convention files are referenced by pipeline skills only if their `context.<name>_path` resolves to an existing file.
- It does NOT perform the per-file discovery itself. Each `discovering-X` skill handles its own scan, conversation, and write — you just route to the right one.
- It does NOT maintain multiple memory files. The bootstrap maintains exactly one (the user picks via ss-bs-discovering-memory-file's Step 0 when ambiguous).

## Hard Gates

- Do NOT skip the per-file detect+ask loop — every convention file gets its own decision point
- Do NOT regenerate the config YAML from scratch — copy the scaffold verbatim, then Edit specific keys
- Do NOT commit until `validate-config.sh` passes
- Do NOT run discovering-X skills in parallel — load them sequentially, one file at a time, so the user can reason about each
- Do NOT dispatch any discovering-X skill as a subagent. All seven are inline; load them via your harness's skill mechanism.
- Do NOT bypass a discovering-X skill — even if you "know what the proposal would be," the per-file conversation is the skill's job, not yours.
- Do NOT overwrite an existing convention file without explicit user direction (Replace mode requires affirmative user choice)
- Do NOT skip Step 2 (the opt-in switch). It threads `SUGGEST` into every discovering-X skill and must be asked exactly once per run (or read from config when `suggest.default` is `on` or `off`).
- Do NOT thread `SUGGEST=on` if the user picked "Descriptive only" or if config sets `suggest.default: off`.
- Do NOT skip Step 8 (coherence check). The check is mandatory before commit; the user can choose how to act on findings but cannot bypass the check itself.
- ALWAYS use the harness's interactive question tool when asking the user a yes/no or multi-choice question. Do NOT fall back to a plain-text prompt that forces the user to type their answer — every "Ask: ..." instruction below is meant to be a structured question, not a text prompt.
- ALWAYS use the harness's todo/task tool to track progress through the bootstrap. Build the initial list right after Step 1 (Detect): one todo per convention file (constitution, architecture, testing, glossary, domain, design, memory-file) plus one each for supporting directories, config copy, config edit-to-reflect-reality, validate-config, coherence check, gitignore, and the final commit. Mark `in_progress` when you start an item and `completed` immediately after — don't batch updates. Bootstrap is short but multi-step, and the user is watching this list to know which file you're working on.

## Checklist

Proceed through these in order:

1. Detect existing setup via discovery script
2. Suggestion-pass opt-in switch (one question; threads `SUGGEST=on|off` into every discovering-X invocation)
3. Per-file loop for the 7 convention files (constitution → architecture → testing → glossary → domain → design → memory-file): for each, detect → ask → load the matching `ss-bs-discovering-<topic>` skill inline → record outcome
4. Create supporting directories (`docs/adr/`, `docs/specs/`) with stub READMEs
5. Copy config scaffold to `.sublime-skills/config.yml`, create empty `.sublime-skills/config-local.yml`, and create `.sublime-skills/.gitignore` with both entries
6. Edit config to reflect reality (set `context.<name>_path` to null for skipped files; adjust if non-default paths)
7. Run `validate-config.sh`; fix-and-retry on FAIL (cap 3 attempts)
8. Run `coherence-check.sh`; surface findings; offer Address/Acknowledge/Show options (cap 3 coherence loops)
9. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
10. Single commit
11. Report and direct user to `ss-sdd-coordinator`

## Step 1: Detect Existing Setup

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/discover-context.sh
```

Cache the JSON output. For each convention file: the corresponding key (`constitution`, `architecture`, `testing`, `glossary`, `domain`, `design`) is either a string (file exists) or `null` (no file at the configured path, or config doesn't exist yet).

## Step 1.5: Build the Todo List

Before starting the per-file loop, build the progress todo list with the harness's todo/task tool. Use these items:

1. Constitution (`docs/CONSTITUTION.md`)
2. Architecture (`docs/ARCHITECTURE.md`)
3. Testing (`docs/TESTING.md`)
4. Glossary (`docs/GLOSSARY.md`)
5. Domain model (`docs/DOMAIN.md`)
6. Design (`docs/DESIGN.md`)
7. Agent memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md — discovery skill picks the canonical one)
8. Create `docs/adr/`, `docs/specs/` with READMEs
9. Copy config scaffold to `.sublime-skills/config.yml`, create empty `.sublime-skills/config-local.yml`, and create `.sublime-skills/.gitignore` with both entries
10. Edit config to reflect skipped files
11. Run `validate-config.sh` (fix-and-retry loop)
12. Run `coherence-check.sh` (cap 3 loops if Address chosen)
13. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
14. Commit

Mark each `in_progress` when you start it and `completed` the instant it's done. Never batch — the user reads this list to follow along with what you're doing.

## Step 2: Suggestion-Pass Opt-In Switch

Read `suggest.default` from `.sublime-skills/config.yml` (or from the scaffold's default `ask` if the file doesn't exist yet — the scaffold copy happens in Step 5, so on first run, treat `default` as `ask`).

- **`default: on`** — set `SUGGEST=on` for the run; skip the question; log "Suggestion pass: on (from config)" in the todo list.
- **`default: off`** — set `SUGGEST=off` for the run; skip the question.
- **`default: ask`** — ask:

```
Question: "Before the per-file walkthrough, one preference question:

Do you want me to also propose improvements where I see opportunities, or
just document what exists?"

Options:
  - "Descriptive only — document what's there (fastest, safest)"
  - "Descriptive + suggestions (Recommended — flags anti-patterns and
    missing-but-typically-valuable patterns, cited from evidence)"
  - "Skip bootstrap and run audit mode instead (for established projects
    where you want the deeper read)"
```

Map answers:
- "Descriptive only" → `SUGGEST=off`
- "Descriptive + suggestions" → `SUGGEST=on`
- "Skip bootstrap and run audit mode" → halt bootstrap, invoke `ss-bs-auditing-project`, exit

Hold `SUGGEST` for the duration of the run and pass it into every `ss-bs-discovering-<topic>` invocation in Step 3.

## Step 3: Per-File Loop

Iterate convention files in this order: **constitution, architecture, testing, glossary, domain, design, memory-file.** For each:

### 3a. Detect

From the cached discovery output, check if the file at the default path (or configured path, if config already exists) is present.

Default paths the scaffold will set:
- Constitution: `docs/CONSTITUTION.md`
- Architecture: `docs/ARCHITECTURE.md`
- Testing: `docs/TESTING.md`
- Glossary: `docs/GLOSSARY.md`
- Domain: `docs/DOMAIN.md`
- Design: `docs/DESIGN.md`
- Memory file: resolved by the discovery skill's Step 0 (use `memory_file.path` from config if set, else auto-detect, else ask the user)

### 3b. Ask the User

**File does NOT exist** — ask:

> "Project doesn't have a `<filename>` yet. Want me to analyze the project and propose one? (yes/no)"

On no: record this file as **skipped**; continue to the next file.

**File DOES exist** — ask:

> "`<filename>` already exists. What would you like to do?
> - **Skip** — leave it as-is (default)
> - **Extend** — I'll analyze the project and propose additions / refinements to merge in
> - **Replace** — I'll analyze the project and propose a fresh draft to overwrite the existing file"

Record the chosen mode. On **Skip**: continue to the next file.

### 3c. Load the Matching `discovering-X` Skill Inline

For modes Create, Extend, or Replace, route to the per-file skill, loading it inline. All seven convention files use the same uniform mechanism — no subagent dispatch, ever.

| Convention file | Skill loaded (inline) |
|---|---|
| Constitution | `ss-bs-discovering-constitution` |
| Architecture | `ss-bs-discovering-architecture` |
| Testing | `ss-bs-discovering-testing` |
| Glossary | `ss-bs-discovering-glossary` |
| Domain model | `ss-bs-discovering-domain-model` |
| Design | `ss-bs-discovering-design` |
| Memory file | `ss-bs-discovering-memory-file` |

**How to load:**

Load the matching `ss-bs-discovering-<topic>` skill inline (via your harness's skill mechanism). Pass these inputs (the skill's documented input convention):

```
Load skill: ss-bs-discovering-<topic>

REPO_ROOT:        <absolute path to repo root>
MODE:             create | extend | replace
SUGGEST:          on | off  ← from Step 2
EXISTING_CONTENT: (only for extend / replace — the verbatim current file content)
FILE_PATH:        <target path — e.g., docs/CONSTITUTION.md, docs/ARCHITECTURE.md,
                   docs/TESTING.md, docs/GLOSSARY.md, docs/DOMAIN.md, docs/DESIGN.md,
                   or whatever the config'd context.<name>_path resolves to>
```

The skill handles the entire interaction itself — code scan, user discussion (one question at a time, structured choices, free-form where appropriate), draft preview, refinement loop (cap 3 iterations), and atomic write. **You do NOT run a separate discuss-and-write step for any convention file** — each discovering-X skill performs both internally.

When the skill returns control to you, it reports one of:

- `created` — file written via the Build path (or, for design only, `created via build` / `created via import from <path>`)
- `extended` — merged content written (extend mode)
- `replaced` — full draft written over previous content (replace mode)
- `skipped (declined mid-skill)` — user bailed out partway through the skill's own flow

Record that outcome alongside the path, then proceed to 3d.

### 3d. Next File

Continue to the next convention file in the order. Repeat until all seven are settled.

## Step 4: Create Supporting Directories

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

ADRs are written by the `ss-sdd-maintaining-adrs` skill during the SDD pipeline,
or manually by anyone with a decision worth capturing.
```

**`docs/specs/README.md`:**

```markdown
# Specs

Each subdirectory is one feature, containing `spec.md` and `plan.md`.

Directory pattern: `NNN-kebab-name/` (zero-padded 3 digits).
```

If any of these READMEs already exist with the same content, skip them. If they exist with different content, ask the user before overwriting.

## Step 5: Copy Config Scaffold and Create Local Overlay

### 5a. Migrate pre-update configs (re-run only)

If `.sublime-skills/config.yml` already exists, check for missing keys introduced in this bootstrap version:

```bash
CONFIG=.sublime-skills/config.yml
NEEDS_MIGRATION=false
grep -q "^  testing_path:" "$CONFIG" || NEEDS_MIGRATION=true
grep -q "^suggest:" "$CONFIG" || NEEDS_MIGRATION=true
```

If `NEEDS_MIGRATION=true`, ask the user:

```
Question: "Your config is from an older bootstrap version that doesn't know about the testing artifact or the suggestion-pass switch. Add the missing keys with safe defaults?"
Options:
  - "Yes — add testing_path: null and suggest.default: ask" (Recommended)
  - "No — abort bootstrap so I can review manually"
```

On Yes: use `Edit` to insert the missing keys.
- For `testing_path`, insert below `architecture_path` in the `context:` block:
  ```yaml
    testing_path: null                            # added by config-migration
  ```
- For the `suggest:` block, append at end of file:
  ```yaml

  suggest:
    default: ask
  ```

On No: halt with a clear message: "Aborted: please add testing_path and suggest.default to config manually, then re-run bootstrap."

After migration (or if no migration needed), continue with the existing Step 5 logic.

```bash
mkdir -p .sublime-skills
[ -f .sublime-skills/config.yml ] || cp "$SUBLIME_SKILLS_HOME/skills/project-bootstrap/scaffolds/config.yml" .sublime-skills/config.yml
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

`.sublime-skills/.gitignore` is created as a two-entry file: `config-local.yml` (per-developer overlay) and `state.json` (per-run SDD state). It's committed (the ignore is project-wide convention). On a re-run, the file is left alone — see Step 9 for the append-if-missing logic that catches users who may have removed one of the entries.

All three patterns are idempotent — they create the file when it's missing, and leave any existing content alone on a re-run. This protects the user's hand-edits to any of these files across multiple bootstrap invocations.

The `cp` of the scaffold is a verbatim copy of `$SUBLIME_SKILLS_HOME/skills/project-bootstrap/scaffolds/config.yml`. **Do NOT regenerate the YAML.** The scaffold is the single source of truth for the config's shape and defaults; the bootstrap never produces config YAML from scratch.

`.sublime-skills/config-local.yml` is created as a zero-byte file. It's a per-developer overlay: any key set here shadows the matching key in `config.yml` when skills read config. The file is gitignored (Step 9), so each developer can populate it without affecting teammates.

Step 6 below still runs unconditionally — it edits specific keys in `config.yml` (sets `context.<name>_path` to `null` for skipped files) using the `Edit` tool, not by rewriting the file. So newly Skipped convention files are reflected even on a re-run that did not re-copy the scaffold.

## Step 6: Edit Config to Reflect Reality

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

## Step 7: Validate

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh" .sublime-skills/config.yml
```

| Exit code | Action |
|---|---|
| `0` (PASS) | Proceed to Step 8 |
| `1` (FAIL) | Read the findings from stderr; fix each issue in `.sublime-skills/config.yml` (or fix the underlying file/directory if it's an orphan path); re-run the validator. **Cap: 3 attempts.** After 3 failed attempts, halt and surface to user with the remaining findings. |
| `2` (config not found) | This shouldn't happen — Step 5 just copied it. Halt and surface as a serious error. |
| `3` (usage error) | Halt and surface — coordinator bug. |

For ambiguous fixes (e.g., orphan path → "should this be null, or did I write the wrong path?"), confirm with the user before editing.

## Step 8: Cross-Artifact Coherence Check

Run the coherence checker:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/coherence-check.sh"
```

| Exit code | Meaning | Action |
|---|---|---|
| `0` (PASS) | No findings; artifacts are internally consistent | Proceed to Step 9. |
| `1` (findings present) | One or more findings on stdout | Surface ALL findings verbatim to the user (do not summarize). Then ask the options below. |
| `2` (config missing) | Should not happen — Step 5 just created config | Halt and surface as serious error. |
| `3` (usage error) | Coordinator bug | Halt and surface. |
| `4` (internal error) | python3 missing or YAML unparseable | Halt and surface; coherence check is mandatory for bootstrap. |

### When findings are present

Ask:

```
Question: "How would you like to proceed?"
Options:
  - "Address findings now" (Recommended if any CRITICAL)
  - "Acknowledge and commit as-is"
  - "Show details for one finding"
```

**Address findings now:**
1. For each finding, identify the relevant `discovering-X` skill (the finding's "fix" line names it).
2. Loop back into Step 3's per-file loop with `MODE=extend` for just those skills.
3. After all addressed, re-run `coherence-check.sh`.
4. If new findings appear, ask the same question again.
5. **Cap at 3 coherence loops.** After the third, surface:

   > "We've done three rounds of coherence fixes and findings remain. Want to:
   > (a) commit with the remaining findings noted in the conversation, or
   > (b) abort the bootstrap (no commit)?"

**Acknowledge and commit as-is:** proceed to Step 9. Findings are NOT added to the commit message.

**Show details for one finding:** the user picks one; expand the context lines. Then re-ask the three options.

## Step 9: `.gitignore` Housekeeping

Ensure `.sublime-skills/.gitignore` contains both required entries. Step 5 created the file when missing; this step handles the re-run case where a developer may have removed an entry:

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

## Step 10: Commit

```bash
git add docs/CONSTITUTION.md docs/ARCHITECTURE.md docs/TESTING.md docs/GLOSSARY.md docs/DOMAIN.md docs/DESIGN.md \
        <memory-file-path-from-step-3> \
        docs/adr/ docs/specs/ \
        .sublime-skills/config.yml .sublime-skills/.gitignore
git commit -m "chore: initialize SDD project context"
```

Only `git add` the files that were actually created or modified in this run. Don't add files the user opted out of (skipped + file doesn't exist → not staged).

Note: `<memory-file-path-from-step-3>` is whatever `discovering-memory-file` resolved (CLAUDE.md, AGENTS.md, etc.) — only include if that stage created/modified a file.

Use the standard project commit conventions if `git log` shows a different style (Conventional Commits, "feat:" prefixes, etc.).

## Step 11: Report

```
SDD bootstrap complete.

Convention files:
- docs/CONSTITUTION.md — <created | extended | replaced | skipped (file exists) | skipped (declined)>
- docs/ARCHITECTURE.md — <...>
- docs/TESTING.md — <...>
- docs/GLOSSARY.md — <...>
- docs/DOMAIN.md — <...>
- docs/DESIGN.md — <...>
- <memory-file-path> — <...>

Directories:
- docs/adr/ (with README)
- docs/specs/ (with README)

Config:
- .sublime-skills/config.yml created/migrated and validated (PASS)
- .sublime-skills/.gitignore created with state.json and config-local.yml entries
- Skipped files have their context.<name>_path set to null
- Suggestion pass: <on / off> (this run)

Coherence check: <PASS | N findings (acknowledged | addressed in N loops)>

Next steps:
- Run the ss-sdd-coordinator skill to start your first feature
- Or, re-run ss-bs-bootstrapping-project later to extend a convention file
- Or, run ss-bs-auditing-project for a deeper opinionated re-evaluation
```

## Re-Running on an Existing Project

If `.sublime-skills/config.yml` already exists when this skill starts, treat it as a re-run:

- The per-file loop still walks each convention file — but now Detect will find the configured path (not the default), and the discussion is more about Extend/Replace than Create.
- Step 5 (copy scaffold) is skipped if the config exists — the user already has one. Step 5a (config-migration) runs first to add any missing keys from newer bootstrap versions. Step 6 (edit to reflect reality) still runs: any newly-created file in this re-run gets its `<name>_path` set; any newly-skipped file gets nulled.
- Step 7 (validate) always runs.
- Step 8 (coherence check) always runs.

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
| Dispatching a discovering-X skill as a subagent | All seven are inline — load them in the coordinator's own context. A subagent dispatch would break the interactive Q&A flow. |
| Running multiple discovering-X skills in parallel | Sequential, one file at a time, so the user can reason about each. |
| Re-doing the user discussion or write after a discovering-X returns | The skill already discussed + wrote internally — your job is to record the outcome and move on. |
| Writing convention files directly from the coordinator | The discovering-X skill is the single source of truth for its file's content. |
| Overwriting an existing file in Extend mode | Extend merges; only Replace overwrites. |
| Regenerating the YAML scaffold | Copy verbatim, then Edit specific keys. |
| Skipping validate-config.sh | Mandatory; bootstrap isn't done until it passes. |
| Looping the validator more than 3 times | Cap is 3; after that, surface to user. |
| Bundling multiple commits (one per file) | One bootstrap = one commit. |
| Auto-deciding Skip/Extend/Replace | Always ask the user explicitly. |
| Skipping Step 2 (opt-in switch) | Mandatory — threads SUGGEST through every stage |
| Skipping Step 8 (coherence check) | Mandatory — check before commit; user decides how to act |
| Looping coherence fixes more than 3 times | Cap is 3; surface "commit-with-remaining or abort" after the third |
| Adding coherence findings to the commit message | Findings are conversation-only; do not pollute commit log |
| Forgetting to thread SUGGEST into a discovering-X invocation | Every discovering-X call MUST include SUGGEST (on or off); auditable in transcript |
| Ignoring the config-migration sub-step on re-runs | Pre-update configs lack testing_path / suggest block; migrate or abort |

## Red Flags

- About to load two discovering-X skills in parallel → STOP; sequential only
- About to do the per-file scan or discussion yourself inline in the coordinator → STOP; that's the discovering-X skill's job
- About to dispatch a discovering-X as a subagent → STOP; all seven are inline — load them in the coordinator's own context
- About to write a convention file from the coordinator → STOP; the discovering-X skill writes
- About to commit before `validate-config.sh` passes → STOP
- About to commit before `coherence-check.sh` has been run → STOP
- About to overwrite an existing file without the user picking Replace → STOP
- About to re-prompt the user for the same file after a discovering-X already returned → STOP; the conversation already happened inside the skill
