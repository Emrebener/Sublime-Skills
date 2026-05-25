# Project Bootstrap

A one-time, opinionated setup for spec-driven development on a fresh project. The bootstrap walks you through the seven convention files (constitution, architecture, testing, glossary, domain model, design system, memory file), scaffolds the `.sublime-skills/` config, creates the supporting directories, validates everything, and commits the result. After it runs, the project is ready for the SDD pipeline.

The bootstrap is a **separate skill family** from SDD — it lives at `skills/project-bootstrap/`, not `skills/spec-driven-development/`. You invoke it manually; the SDD coordinator never invokes it. Its job is preparing the ground; SDD's job is building on it.

> This doc is the human-readable narrative. The operational specs live in `skills/project-bootstrap/<skill>/SKILL.md`. If this doc and a SKILL.md disagree, the SKILL.md wins.

---

## Descriptive vs prescriptive — the suggestion pass

Bootstrap is **descriptive by default**: it captures what the codebase already does and codifies it. With the suggestion-pass opt-in (asked once at the top of the run), it also runs an evidence-grounded prescriptive pass per discovery skill — flagging anti-patterns and missing-but-typically-valuable patterns, each cited from specific file paths or counts in the codebase. The user picks which suggestions to accept; accepted ones land in the artifact with a provenance marker so audit can re-evaluate later.

See `docs/bootstrap-improvements-2026-05-25.md` for the full design.

---

## TL;DR

You invoke `ss-bs-bootstrapping-project`. It:

1. Runs `discover-context.sh` to see what's already there
2. Walks you through the seven convention files one at a time. For each: detect → ask Skip / Create / Extend / Replace → load the matching `ss-bs-discovering-<topic>` skill inline → the skill scans the code, asks you targeted questions, drafts the file, refines via tweak loop, and writes atomically
3. Creates `docs/adr/`, `docs/specs/` with stub READMEs
4. Copies `skills/project-bootstrap/scaffolds/config.yml` verbatim to `.sublime-skills/config.yml`, creates `.sublime-skills/config-local.yml` as an empty file, and creates `.sublime-skills/.gitignore` with `state.json` + `config-local.yml` entries (all idempotent — existing content is preserved on re-run)
5. Edits the config to null out paths for skipped files
6. Validates via `validate-config.sh` (fix-and-retry; cap 3)
7. Runs a cross-artifact coherence check and surfaces any structural issues
8. Ensures `.sublime-skills/.gitignore` contains both `state.json` and `config-local.yml` (Step 4 creates the file; this step is a re-run safety net)
9. Commits everything in one commit

The whole thing is **safe to re-run**. Subsequent runs let you extend convention files you previously skipped, refine ones you created, or replace stale ones — without overwriting anything you didn't approve.

---

## Cross-artifact coherence check

After all 7 stages complete and config is validated, bootstrap runs a structural coherence check across the artifacts. Findings are surfaced verbatim with severity (CRITICAL / WARNING / INFO) and a one-line fix hint. The user decides how to act: address now (loops back into the relevant discovery skills), acknowledge and commit, or expand a finding for details.

Coherence is also the first step of `ss-bs-auditing-project` (the sibling skill for re-evaluating existing projects).

---

## At a glance

| # | Step | Mechanism | Writes to disk? |
|---|---|---|---|
| 1 | Detect existing setup | Coordinator runs `discover-context.sh` | No |
| 1.5 | Build progress todo list | Coordinator uses harness todo tool | No |
| 2 | Per-file loop (×7) | Coordinator routes; `discovering-X` skill does the work | Yes (one file per discovering-X, atomic) |
| 3 | Create `docs/adr/`, `docs/specs/` | Coordinator (`mkdir` + stub READMEs) | Yes |
| 4 | Copy config scaffold + create local overlay + create gitignore | Coordinator (`cp` from scaffolds/ + `touch` of `config-local.yml` + heredoc-write of `.gitignore` if missing) | Yes (`.sublime-skills/config.yml`, `.sublime-skills/config-local.yml`, `.sublime-skills/.gitignore`) |
| 5 | Edit config to reflect skipped files | Coordinator (targeted in-place edits) | Yes (modifies `.sublime-skills/config.yml`) |
| 6 | Validate config | Coordinator runs `validate-config.sh`; fix-and-retry (cap 3) | No (read-only check) |
| 7 | Cross-artifact coherence check | Coordinator runs `coherence-check.sh`; surfaces findings | No (advisory; user decides action) |
| 8 | `.gitignore` housekeeping | Coordinator (re-run safety net — ensures `.sublime-skills/.gitignore` has both `state.json` and `config-local.yml`) | Possibly (`.sublime-skills/.gitignore`) |
| 9 | Single commit | Coordinator (`git add` specific files + `git commit`) | Yes (one commit) |
| 10 | Report | Coordinator (final summary message) | No |

**No subagent dispatches anywhere in the bootstrap.** All seven discovering-X skills load inline.

---

## Coordinator entry

`ss-bs-bootstrapping-project` is the coordinator. Its job is the surrounding workflow (detection, mode choice, config, commit) — not the per-artifact discussion. Each discovering-X skill owns that.

When invoked, the coordinator announces itself ("I'm using the ss-bs-bootstrapping-project skill to set up SDD for this project") and proceeds to Step 1. If `.sublime-skills/config.yml` already exists, the coordinator treats this as a re-run (see [Re-running bootstrap](#re-running-bootstrap)).

---

## Step 1: Detect existing setup

```bash
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/discover-context.sh
```

The script emits JSON. The coordinator caches it. For each convention file, the corresponding key (`constitution`, `architecture`, `testing`, `glossary`, `domain`, `design`, `memory_file`) is either:

- A string (file exists at the configured or default path), or
- `null` (no file, or no config exists yet)

The coordinator uses these signals to drive Step 2a (detection) and Step 2b (the ask).

## Step 1.5: Build the progress todo list

Before the per-file loop, the coordinator builds a visible todo list via the harness's todo/task tool:

1. Constitution (`docs/constitution.md`)
2. Architecture (`docs/ARCHITECTURE.md`)
3. Testing (`docs/TESTING.md`)
4. Glossary (`docs/GLOSSARY.md`)
5. Domain model (`docs/DOMAIN.md`)
6. Design (`docs/DESIGN.md`)
7. Memory file (agent memory file)
8. Create `docs/adr/`, `docs/specs/` with READMEs
9. Copy config scaffold to `.sublime-skills/config.yml`, create empty `.sublime-skills/config-local.yml`, and create `.sublime-skills/.gitignore` with `state.json` + `config-local.yml` entries
10. Edit config to reflect skipped files
11. Run `validate-config.sh` (fix-and-retry loop)
12. Cross-artifact coherence check
13. Ensure `.sublime-skills/.gitignore` contains state.json + config-local.yml entries
14. Commit

Each item moves to `in_progress` when started and `completed` the instant it's done. Never batched — the user reads this list to follow along.

---

## Step 2: Per-file loop

Iteration order is fixed: **constitution → architecture → testing → glossary → domain model → design → memory file**. The order matters because later files reference earlier ones (e.g., architecture references domain terms; testing references frameworks from architecture; memory file synthesizes pointers to all prior artifacts).

### 2a. Detect

For each file: check the cached discovery output. Default paths:

- Constitution: `docs/constitution.md`
- Architecture: `docs/ARCHITECTURE.md`
- Testing: `docs/TESTING.md`
- Glossary: `docs/GLOSSARY.md`
- Domain: `docs/DOMAIN.md`
- Design: `docs/DESIGN.md`
- Memory file: (language-dependent; see agent harness config)

If the user's config (when re-running) overrides any path, the override wins.

### 2b. Ask the user

The coordinator asks one of two questions, depending on whether the file exists.

**File does NOT exist:**

> "Project doesn't have a `<filename>` yet. Want me to analyze the project and propose one? (yes/no)"

On `no`: record as **skipped**; continue to the next file. (In Step 5, `context.<name>_path` gets nulled.)

**File DOES exist:**

> "`<filename>` already exists. What would you like to do?
> - **Skip** — leave it as-is (default)
> - **Extend** — I'll analyze the project and propose additions / refinements to merge in
> - **Replace** — I'll analyze the project and propose a fresh draft to overwrite the existing file"

On **Skip**: continue to the next file. The file is preserved as-is; the config keeps its path.

The four modes — Create, Skip, Extend, Replace — are the entire decision surface. See [Decision tree](#decision-tree-skip--create--extend--replace) below for guidance.

### 2c. Load the matching `discovering-X` skill inline

For modes Create, Extend, or Replace, route to the per-file skill, loading it inline. All seven files use the same uniform mechanism — no subagent dispatch, ever.

| Convention file | Skill loaded (inline) |
|---|---|
| Constitution | `ss-bs-discovering-constitution` |
| Architecture | `ss-bs-discovering-architecture` |
| Testing | `ss-bs-discovering-testing` |
| Glossary | `ss-bs-discovering-glossary` |
| Domain model | `ss-bs-discovering-domain-model` |
| Design | `ss-bs-discovering-design` |
| Memory file | `ss-bs-discovering-memory-file` |

The coordinator passes the skill four inputs:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, or `replace`
- `EXISTING_CONTENT` — the verbatim current file content (only for extend/replace; empty for create)
- `FILE_PATH` — where to write (the configured `context.<name>_path` or the default)

The skill handles **everything inside its slot**: code scan, user discussion (one question per turn, structured choices, free-form where appropriate), draft preview, refinement loop (cap 3 iterations), and atomic write. The coordinator does NOT run a separate discuss-and-write step — each discovering-X performs both internally.

When the skill returns, it reports one outcome string:

- `created` — file written via Build path. (For design only: `created via build` or `created via import from <path>`.)
- `extended` — merged content written (extend mode)
- `replaced` — full draft written over previous content (replace mode)
- `skipped (declined mid-skill)` — user bailed out partway through the skill's own flow

The coordinator records the outcome and proceeds to the next file.

### 2d. Next file

Continue to the next convention file in the order. Repeat until all seven are settled. The coordinator never runs discovering-X skills in parallel — sequential only, so the user can reason about each.

---

## The discovering-X conversation pattern

All seven `ss-bs-discovering-<topic>` skills share the same six-step inline pattern. Differences live only in **what code each scans** and **what questions each asks** (see [Per-skill summaries](#per-skill-summaries) for the per-skill specifics).

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan                        │
│   → Step 2: announce findings                       │
│   → Step 3: targeted questions (one per turn)       │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 2: announce findings + gaps                │
│   → Step 3: targeted questions on gaps only         │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
└─────────────────────────────────────────────────────┘
```

**Key rules across all five skills:**

- ALWAYS use the harness's interactive question tool for yes/no and multi-choice questions. Never plain-text prompts that force free-form typing.
- ONE question per turn. No bundling.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text is reserved for genuinely open prompts (intent principles, alias notes, workflow exceptions, brand vibe).
- No Mermaid / C4 / PlantUML / ER-diagram syntax in any output file. Text only.
- Every proposition in the draft traces to either codebase evidence OR explicit user input. No truisms, no invented entities, no padded lists.
- Tweak loop caps at 3 iterations. After three, surface bail options ((a) keep current, (b) skip, (c) supply the file yourself).
- Extend mode merges, never overwrites. Only Replace overwrites.

The discovering-X skills are inline (loaded into the coordinator's context) — not subagents. The reason: each file mixes code-derivable signal with user-held intent. A subagent returns once and dies; it can't have the back-and-forth needed to settle "which principles matter," "which terms are load-bearing," "what's the vibe." Routing the conversation through the coordinator (subagent returns findings → coordinator paraphrases → user replies → re-dispatches) wastes turns and drifts intent.

Design is unique among the five in offering an additional **Import** path: if the user already has a DESIGN.md generated by an external tool (refero.design, Specify, Tokens Studio, hand-authored), `ss-bs-discovering-design` will verify it, preview it, and atomically copy it instead of running Build. The other four are Build-only.

---

## Per-skill summaries

The full per-skill detail — what each scans, what questions it asks, what it produces — lives in [skills.md](sdd/skills.md#ss-bs-discovering-constitution--ss-bs-discovering-architecture--ss-bs-discovering-glossary--ss-bs-discovering-domain-model--ss-bs-discovering-design) and in each SKILL.md. Quick reference:

| Skill | Reads | Asks user about | Produces |
|---|---|---|---|
| `ss-bs-discovering-constitution` | README, CONTRIBUTING, linter/formatter/CI configs, source patterns, security files | Confirm scanned principles → MUST/SHALL/SHOULD severity → intent principles code can't reveal | 3-7 MUST/SHALL/SHOULD principles with one-line rationales |
| `ss-bs-discovering-architecture` | Top-level dirs, build files, entry points, infra config (Docker / k8s / terraform), `.env.example` | Component grouping → out-of-scope → env-var-only integrations → non-code facts → cardinality | System summary, Components, Runtime topology, Data stores, External integrations, Boundaries |
| `ss-bs-discovering-testing` | Test dirs, runner configs, CI commands, coverage tooling, mocking patterns, fixtures | Test categories → frameworks → coverage gates → mocking discipline → naming conventions | Test categories, Runner & framework, Coverage, Mocking philosophy, Fixtures & factories, Conventions |
| `ss-bs-discovering-glossary` | Source identifiers (class / table / route names), inline comments, README | Term selection (≤30) → aliases / multi-naming → definition refinements during tweak loop | 10-30 alphabetical terms, each ≤2 sentences |
| `ss-bs-discovering-domain-model` | DB schemas, migrations, ORM models, type defs, test fixtures, state-machine code | Entity selection (≤15) → lifecycle completeness → cardinality → workflow exceptions | 3-15 entities with conceptual attributes, relationships (with cardinality), lifecycles |
| `ss-bs-discovering-design` | Tailwind config, CSS custom properties, theme/token files, `components/`, design-system deps | (Build) Vibe / theme intent → color role rules → component vocabulary → do's-and-don'ts. (Import) Verify + preview + confirm a user-supplied file. | Design system: theme, colors, typography, spacing, surfaces, components, do's & don'ts |
| `ss-bs-discovering-memory-file` | All prior artifacts + codebase patterns | Memory-file structure → scope (agents / features / time range) | Pointers to artifacts, Team members, Key decisions, Recent changes, Agent tools |

Each enforces per-skill caps (≤7 principles, ≤30 terms, ≤15 entities, ≤20 terms for testing) and writes its file atomically itself.

---

## Decision tree: Skip / Create / Extend / Replace

For each file, four choices. Here's how to pick.

### When to choose **Skip**

- The file doesn't exist AND your project genuinely doesn't need it (e.g., a small library doesn't need an architecture overview; a CLI tool doesn't need DESIGN.md; a one-person project may not need a constitution).
- The file exists and you're happy with it. Leave it alone.
- You're going to write/edit the file by hand and don't want the skill's involvement.

When you Skip, the coordinator nulls the corresponding `context.<name>_path` in `.sublime-skills/config.yml`. The SDD pipeline gracefully handles `null` — it just doesn't read the file. You can fill it in later by re-running the bootstrap.

### When to choose **Create**

(Only offered when the file doesn't exist.)

- You don't have the file and want one. The discovering-X skill scans your code, asks you targeted questions, and produces a draft for your review.

If the project has very little to scan (a fresh repo with no code yet), the skill will announce the lean signal and offer to continue (relying mostly on your answers) or skip.

### When to choose **Extend**

(Only offered when the file exists.)

- The existing file has gaps you'd like the skill to fill in based on current code state.
- New features have been added since the file was last updated, and you want the additions captured.
- You want a second opinion on what's missing, without losing what's already there.

The skill reads `EXISTING_CONTENT` carefully, identifies categories that aren't covered, and proposes **additions only**. Existing content is preserved verbatim except where you explicitly approve a conflict resolution (e.g., "the existing definition says X but the code does Y — how should I resolve?").

### When to choose **Replace**

(Only offered when the file exists.)

- The existing file is significantly out of date and a from-scratch rewrite is easier than reconciling.
- The file was hand-authored under a different convention and you want the skill to bring it in line.
- You've materially changed the project (rebrand, restructure, technology pivot) and want a fresh draft.

Replace is destructive — the existing file is fully overwritten by the new draft. The coordinator will not Replace without your explicit selection of that mode.

### Project-type defaults

| Project type | Constitution | Architecture | Glossary | Domain | Design |
|---|---|---|---|---|---|
| Web app (UI + backend) | Useful | Useful | Useful | Useful | Useful |
| Backend service (no UI) | Useful | Useful | Useful | Useful | Skip (no UI) |
| CLI tool | Useful | Lighter | Often skip | Often skip | Skip (no UI) |
| Library / SDK | Useful | Useful | Useful | Useful | Skip (no UI) |
| Mobile app | Useful | Useful | Useful | Useful | Useful |
| Static site / docs site | Lighter | Lighter | Often skip | Skip | Useful |
| Greenfield / nothing yet | Useful (light) | Skip until structure emerges | Skip until vocabulary emerges | Skip until entities emerge | Skip until UI emerges |

These are heuristics, not rules. The skill always lets you opt out of any specific file.

---

## Step 3: Create supporting directories

```bash
mkdir -p docs/adr docs/specs
```

Each gets a stub README with usage notes:

- `docs/adr/README.md` — ADR conventions (filename pattern, status lifecycle, who writes them)
- `docs/specs/README.md` — Spec directory pattern (`NNN-kebab-name/`)

If a README already exists with the same content, it's skipped. If a README exists with different content, the coordinator asks before overwriting.

---

## Step 4: Copy config scaffold, create local overlay, and create gitignore

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

All three patterns are **idempotent**: they create the missing file and leave any existing content untouched on a re-run. Hand-edits to any of these files are preserved across bootstrap invocations — the bootstrap never clobbers a config the user has customized.

The `cp` of the scaffold is a **verbatim copy** of `$SUBLIME_SKILLS_HOME/skills/project-bootstrap/scaffolds/config.yml`. The coordinator does NOT regenerate the YAML — the scaffold is the single source of truth for the config's shape and defaults. If you want to change defaults across all new projects, edit the scaffold; if you want to change one repo's behavior, edit its `.sublime-skills/config.yml` directly (after the bootstrap, in Step 5 or later).

The scaffold contains the full config schema with all defaults — see [state-and-config.md § Full schema with defaults](sdd/state-and-config.md#full-schema-with-defaults).

The second line creates `.sublime-skills/config-local.yml` as a zero-byte file when it doesn't already exist. This is the per-developer overlay — see [state-and-config.md § Config overlay (config-local.yml)](sdd/state-and-config.md#config-overlay-config-localyml) for how it works. The bootstrap creates it empty; developers populate it themselves with whatever overrides they want.

The third pattern (the `if` block) creates `.sublime-skills/.gitignore` with two entries: `config-local.yml` (per-developer overlay; each developer's own, not committed) and `state.json` (SDD per-run state file; local-only orchestration metadata, never committed). The file itself is committed (it's a project-wide convention). On a re-run, the file is left alone — Step 7 is the safety net that appends any entry a developer may have removed.

Step 5 (path-skipping edits) still runs unconditionally on every invocation. It uses the `Edit` tool to set specific keys in `config.yml` (e.g., `glossary_path: null` for a newly-skipped glossary) — it does not rewrite the file. So newly Skipped convention files are reflected even when the cp was a no-op.

---

## Step 5: Edit config to reflect reality

For each convention file the user **skipped** (whether the file existed and they chose Skip, or it didn't exist and they declined to create one): the coordinator sets the corresponding `context.<name>_path` in `.sublime-skills/config.yml` to `null` with a targeted in-place edit (no regeneration).

For each convention file **created/extended/replaced** at a non-default path: the coordinator updates the corresponding key to the actual path.

Example: user skipped the glossary. The Edit changes:

```yaml
  glossary_path: docs/GLOSSARY.md
```

to:

```yaml
  glossary_path: null
```

**Hard rule:** the coordinator does NOT touch any keys the user didn't ask about. `branching`, `grill`, `memory_file` — all keep their scaffold defaults. (`context` is the one block the bootstrap edits, per the skipped-file logic above.) If the user later wants a custom branch pattern or memory-file limit, they edit the config by hand. The bootstrap stays out of opinions it wasn't asked to hold.

---

## Step 6: Validate

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh" .sublime-skills/config.yml
```

| Exit code | Meaning | Coordinator action |
|---|---|---|
| `0` | PASS — config is valid | Proceed to Step 7 |
| `1` | FAIL — at least one issue | Read findings from stderr; fix each (edit `.sublime-skills/config.yml` or fix the underlying path); re-run. Cap: 3 attempts. After 3, halt and surface to user. |
| `2` | Config file not found | Shouldn't happen — Step 4 just copied it. Halt as a serious error. |
| `3` | Usage error | Halt — coordinator bug. |

Validator checks include:
- All required keys present (`context.<name>_path` for all five, `branching.branch_pattern`, `grill.question_cap`, `memory_file.path`, `memory_file.character_limit`)
- No unknown keys (catches schema drift)
- Each context path is either `null` or points to an actual existing file (orphan paths fail)

For ambiguous fixes (e.g., orphan path → "should this be null, or did I write the wrong path?"), the coordinator confirms with the user before editing.

---

## Step 7: `.gitignore` housekeeping

`.sublime-skills/.gitignore` is created in Step 4 with two entries: `config-local.yml` and `state.json`. Step 7 is a re-run safety net — it checks both entries are present and appends any that are missing.

`.sublime-skills/config-local.yml` is the per-developer overrides file (Step 4 creates it empty); the gitignore entry keeps each developer's content out of commits.

`.sublime-skills/state.json` is the SDD per-run state file. It's local-only orchestration metadata, created by Stage 2 and deleted by Stage 17. It's never committed.

The root `.gitignore` is NOT modified by this skill.

---

## Step 8: Commit

```bash
git add docs/constitution.md docs/ARCHITECTURE.md docs/GLOSSARY.md docs/DOMAIN.md docs/DESIGN.md \
        docs/adr/ docs/specs/ \
        .sublime-skills/config.yml [.gitignore]
git commit -m "chore: initialize SDD project context"
```

Only files that were actually created or modified in this run get staged. Skipped files that don't exist aren't staged.

If the project uses Conventional Commits, "feat:" prefixes, or a different style visible in `git log`, the coordinator matches that style.

Commit failures (pre-commit hook, signing, missing identity) are surfaced per the Commit Failure Protocol — never bypassed with `--no-verify`.

---

## Step 9: Report

The coordinator emits a final summary:

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
- Skipped files have their context.<name>_path set to null

Next steps:
- Run the ss-sdd-coordinator skill to start your first feature
- Or, re-run ss-bs-bootstrapping-project later to extend a convention file
```

---

## Re-running bootstrap

The bootstrap is safe to invoke repeatedly. It never destroys user-authored content without explicit Replace approval.

On a re-run:

- **Detect (Step 1)** picks up the existing `.sublime-skills/config.yml` and uses its `context.<name>_path` values (not the defaults). Files at non-default paths are detected at their actual locations.
- **Per-file loop (Step 2)** still walks each convention file, but for files that exist, the dialog is Skip / Extend / Replace (no Create option). For files that were previously skipped (path is `null` in config), the ask resets to Create / Skip.
- **Copy scaffold (Step 4)**: the `cp` of `config.yml` is skipped — the user already has a config. The coordinator does NOT regenerate or overwrite it. The `[ -f ... ] || touch` of `config-local.yml` runs unconditionally and is idempotent, so an existing local overlay is preserved verbatim.
- **Edit config (Step 5)** still runs. Any newly-created file in this re-run gets its `<name>_path` set; any newly-skipped file gets nulled.
- **Validate (Step 6)** always runs.
- **Commit (Step 8)** is single, just like the first run.

Common re-run scenarios:

| Why you're re-running | Typical pattern |
|---|---|
| You skipped a file and now want it | Create that file; Skip the others |
| The codebase changed significantly | Extend (or Replace) the affected files; Skip the others |
| You moved a convention file to a non-default path | Edit `.sublime-skills/config.yml` first, then re-run; the bootstrap picks up the new path |
| You want to add the DESIGN.md slot that the team's UI work now justifies | Create design; Skip the others |

---

## Bootstrap output → SDD pipeline integration

The bootstrap's job ends where SDD's begins. Once `.sublime-skills/config.yml` is valid and committed, you can invoke `ss-sdd-coordinator` and start features.

The SDD pipeline reads the bootstrap's output at several points:

- **`ss-sdd-coordinator` entry**: runs Stage 0 (`ss-sdd-preflight`) which is the single home for every pre-pipeline halt check — config validation via `validate-config.sh` first, then workspace + branch state. If config validation fails (orphan path, unknown key, missing required field), preflight halts with reason `config_invalid` / `config_missing` and directs the user to re-run `ss-bs-bootstrapping-project`. SDD's stance is: a valid config isn't optional, it's required. Once every check passes, preflight creates `.sublime-skills/state.json` as a minimal shell (silently removing any orphan file from a dead prior pipeline first).
- **`ss-sdd-discovering-requirements` (Stage 1)**: runs `discover-context.sh` to find the project convention files. Each file present is loaded; each file absent is skipped (null path → no read). The discovery conversation uses the project's domain vocabulary from `GLOSSARY.md`, the entities from `DOMAIN.md`, and the principles from `constitution.md` if any of these exist.
- **`ss-sdd-reviewing-specs` and `ss-sdd-reviewing-plans`**: read the constitution (if present) to check alignment, and the glossary (if present) to flag vocabulary drift.
- **`ss-sdd-writing-specs` and `ss-sdd-writing-plans`**: prefer the project's canonical vocabulary over synonyms, when a glossary is present.

If the user never bootstraps (or bootstraps with all five files Skipped), SDD still works — it just operates without project-specific context. The pipeline doesn't require any convention file to exist; they're additive.

---

## When to skip the whole thing

Bootstrap is not always worth running.

**Don't bootstrap when:**

- You're prototyping a throwaway repo and won't use SDD on it.
- Your project is so small (single file, ~50 lines) that a constitution / architecture / glossary / domain model would all be longer than the code.
- You only need SDD's plan-and-implement features without the convention-file scaffolding. In that case, manually create `.sublime-skills/config.yml` with all `context.*_path` set to `null` and you're done.

**Do bootstrap when:**

- You're starting a project you expect to grow.
- You're adopting SDD on an existing project and want to capture its current shape before changing things.
- A team is joining the project and would benefit from explicit principles, architecture, vocabulary.

The bootstrap is **fast** — most users finish all five files in 15-30 minutes depending on how much they want to refine. The cost-benefit is favorable for any project worth ~1 day of work or more.

---

## Troubleshooting

### "validate-config.sh failed with 'orphan path'"

**Cause:** a `context.<name>_path` points to a file that doesn't exist.

**Fix:** either set the path to `null` (if you intend to skip that convention file), or create the file at the configured path, or correct the path. The coordinator runs the validator in a fix-and-retry loop and will ask you which interpretation is right when it's ambiguous.

### "validate-config.sh failed with 'unknown key'"

**Cause:** the config has a key the validator doesn't recognize (typo, leftover from an older SDD version, hand-edited drift).

**Fix:** the validator names the offending key. Either remove it or rename it to the correct key. The allowed keys list is in `validate-config.sh` and mirrored in the scaffold (`skills/project-bootstrap/scaffolds/config.yml`).

### "validate-config.sh hit the 3-attempt cap"

**Cause:** after three fix-and-retry rounds, the config still doesn't pass.

**Fix:** the coordinator halts and surfaces the remaining findings. Investigate manually. Common causes: a path is supposed to exist but doesn't (the user expected to create that file later), or a key was renamed in a newer SDD version.

### "discovering-X skill returned `skipped (declined mid-skill)`"

**Cause:** during the inline skill's conversation, the user picked the Abort option (e.g., during the Step 4 approve/tweak/start-over/abort question, or when the tweak loop hit its iteration cap and the user picked option (b) "skip").

**Effect:** the coordinator records the outcome as skipped. The file is NOT created (Create mode) or NOT modified (Extend/Replace modes). The corresponding `context.<name>_path` will be nulled in Step 5.

**Fix:** if the skip was deliberate, no action needed. If accidental, re-run the bootstrap and pick Create / Extend / Replace again.

### "I want to keep my existing convention file but the bootstrap is trying to extend it"

**Cause:** during 2b, you picked Extend when you meant Skip.

**Fix:** during the discovering-X conversation, abort (Step 4 → "Abort — skip this file"). The file remains unchanged. The coordinator records `skipped (declined mid-skill)`.

### "The discovering-X skill keeps asking the same question across re-runs"

**Cause:** each invocation is a fresh conversation. The skill doesn't persist per-question answers across runs.

**Fix:** if a particular convention file is settled and you don't want to revisit it, choose Skip (not Extend) on re-runs.

### "Re-running bootstrap overwrote my hand-edits to the config"

**Cause:** this shouldn't happen — Step 5's Edit only touches `context.<name>_path` keys that match the user's Skip/Create/Extend/Replace decisions. Other keys are left alone.

**Fix:** check `git diff` for the actual delta. If keys outside the `context` block changed, that's a bug — file an issue against `ss-bs-bootstrapping-project`.

### "The bootstrap committed but I want to undo"

**Cause:** the bootstrap creates one commit. Undo is `git reset HEAD~1` (preserves working tree) or `git reset --hard HEAD~1` (discards changes). The bootstrap doesn't push — undo is fully local.

### "I want the bootstrap to support a sixth convention file"

**Cause:** the family currently has exactly five slots, hardcoded in the scaffold and the coordinator.

**Fix:** adding a slot requires changes to four places: (1) `skills/project-bootstrap/scaffolds/config.yml` adds `<new>_path`, (2) `skills/spec-driven-development/framework/validate-config.sh` adds the key to its allowed list, (3) `skills/spec-driven-development/framework/discover-context.sh` emits a `<new>` field in the JSON, (4) `ss-bs-bootstrapping-project/SKILL.md` adds the file to the per-file loop and routing table, and you need a new `ss-bs-discovering-<new>` skill. Not a small change, but mechanical. See the existing `design_path` addition in `git log` for a worked example.

---

## Audit — re-evaluating an established project

`ss-bs-auditing-project` is bootstrap's sibling for projects that have been live for a while. Differences from bootstrap re-run:

- Coherence runs FIRST, not last (drives the per-stage loop).
- Suggestion pass is always on (no opt-out — that's why you ran audit).
- Drift detection compares artifact content vs current code state.
- Per-stage commits enable selective acceptance.

Audit shares the same per-file discovery skills via a new `MODE=audit` value.

---

## Cross-references

- **Skill catalog** — [sdd/skills.md § discovering-X table](sdd/skills.md#ss-bs-discovering-constitution--ss-bs-discovering-architecture--ss-bs-discovering-glossary--ss-bs-discovering-domain-model--ss-bs-discovering-design) for the per-skill summary table
- **Skill source** — `skills/project-bootstrap/ss-bs-bootstrapping-project/SKILL.md` (coordinator) and `skills/project-bootstrap/ss-bs-discovering-<topic>/SKILL.md` (each inline skill)
- **Config schema** — [sdd/state-and-config.md § Config file](sdd/state-and-config.md#config-file-sddconfigyml) for the full config schema with defaults
- **Scaffold source** — `skills/project-bootstrap/scaffolds/config.yml` for the canonical defaults
- **Validation scripts** — [sdd/operations.md § Validation scripts](sdd/operations.md#validation-scripts) for `validate-config.sh` mechanics
- **SDD pipeline entry** — [sdd/pipeline.md § Pipeline entry point](sdd/pipeline.md#pipeline-entry-point) for how `ss-sdd-coordinator` consumes the bootstrap's output
- **Why inline, not subagent** — each discovering-X skill has a "Why This Skill Is Inline (Not a Subagent)" section; the short version: a subagent returns once and dies, but convention files mix code-derivable signal with user-held intent that requires conversation.
