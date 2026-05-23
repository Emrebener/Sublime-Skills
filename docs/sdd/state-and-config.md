# State and Configuration

This document covers two things that aren't artifacts in the user-facing sense but are critical to the pipeline working: the per-feature **state file** that tracks pipeline progress and enables resumption, and the per-repo `.sublime-skills/config.yml` **configuration file** that lets users override defaults.

---

## State file

### What it is

A JSON file at `docs/specs/NNN-<short-name>/state.json`, one per in-progress SDD run. It holds everything the coordinator needs to know to resume an interrupted pipeline from any stage.

### Lifecycle

| Stage | What happens to state.json |
|---|---|
| 0 (Preflight) | Does NOT exist yet. Preflight outputs (current branch) are held in coordinator's in-memory dict. |
| 1 (Discovery) | Still does not exist. Discovery outputs in memory. |
| 2 (Writing spec) | **Created** by `writing-specs`, atomic write. Pre-populated with feature_id, branch, paths. **Uncommitted.** |
| 3–11 | **Updated** at every stage boundary by the coordinator (atomic). **Uncommitted** throughout. |
| 12 (Choosing branch) | **Batch-committed** alongside spec/plan/ADRs in three thematic commits on the chosen branch. |
| 13 (Implementing) | Updated per-task with `tasks` transitions; committed inline with each task's code commits. |
| 14 (Testing) | Updated with `test_status` and `fix_iterations`. |
| 15 (Handoff) | Updated with `handoff_path`. |
| 16 (Memory file) | Updated with `memory_file_updated` and `memory_file_path`. |
| 17 (Finishing) | **Deleted** + commit (`chore(<feature_id>): SDD complete`). |

### Atomic write pattern

Every write is atomic:

```bash
# Write to .tmp, then atomically rename
cat > docs/specs/NNN-name/state.json.tmp <<EOF
{ ... }
EOF
mv docs/specs/NNN-name/state.json.tmp docs/specs/NNN-name/state.json
```

This prevents partial writes from corrupting state if the session dies mid-write.

### Schema

**The canonical schema lives at `spec-driven-development/scripts/state-schema.md`** (human-readable, complete field list + ownership + enums + stage mapping) and `state-schema.json` (machine-readable JSON Schema Draft 2020-12).

This document is a companion that shows worked examples and explains the lifecycle in narrative form. If schema details in this document and the canonical disagree, **the canonical wins** — please update this doc to match.

See `scripts/state-schema.md` for:
- Complete list of required and optional fields
- Field types and enum values
- Field ownership (who writes what, when)
- Full Stage Name Mapping table including `stages_skipped` enum
- Reference example (mid-implementation resume case)

Worked examples in this document are still accurate; if you spot drift, file it as a bug against `scripts/state-schema.md` first.

### Git policy

State.json (and the other SDD planning artifacts: spec.md, plan.md, ADRs) is **uncommitted through Stages 2–11**. The `choosing-feature-branch` skill at Stage 12 batch-commits all of these on the user's chosen branch in three thematic, path-scoped commits:

- `docs(<feature_id>): spec` — spec.md + state.json
- `docs(adr): N decisions for <feature_id>` — ADRs (skipped if none)
- `docs(<feature_id>): plan` — plan.md + state.json (updated)

From Stage 13 onward, state.json is committed alongside the stage's artifact:

- Stage 13 (implementation): per-task code commits include any state.json delta (tasks map transitions)
- Stage 15 (handoff): committed with handoff doc in `docs(<feature_id>): handoff document`
- Stage 16 (memory file): committed with memory file in `docs(memory): update from <feature_id>` (only if memory file was updated; usually no commit)
- Stage 17 (finishing): deletion is committed as `chore(<feature_id>): SDD complete`

**All commits use path-scoped `git add`.** No `git add .` / `git add -A` — preflight allows dirty working trees, so path-scoping is what protects the user's pre-existing dirty files.

**Squash-merge implication:** if the project squashes on merge, the state file's churn collapses into a single final commit. By the time the feature lands in main, only the spec, plan, ADRs, and handoff persist; the state file is gone.

**Mid-pipeline kill risk.** Through Stages 0–11 the state file is uncommitted. If the session dies and the user runs `git stash` or switches branches before Stage 12, the uncommitted artifacts can be displaced. Don't do destructive git operations on a run that hasn't reached Stage 12 yet.

### Resume protocol

The coordinator's first action on every invocation is a quick glob for active state files at `docs/specs/*/state.json`:

**No state files found** — fresh start. Confirm intent ("Start a new feature?") and proceed to Stage 0.

**One state file found** — ask "Resume `<feature_id>` at `<current_stage>`?". On yes, jump to the appropriate stage based on `current_stage`. On no, ask whether to start a fresh feature (leaves the existing state file alone) or abort.

**Multiple state files found** — list them; ask which to resume, or to start fresh. Multiple active runs are unusual; let the user pick.

The state file is in-session orchestration record-keeping. It enables resuming an interrupted run when the user re-invokes `sdd-coordinator` shortly after. It is not designed for cross-machine recovery, multi-user handoff, or recovery from arbitrary destructive git operations.

### Mid-stage interruption

The coordinator's `current_stage` field indicates the stage that's IN PROGRESS. After completion, it advances to the next stage and adds the completion marker to `stages_completed`.

If the session dies between "stage starts" and "stage completes":
- `current_stage` still shows the in-progress stage
- `stages_completed` doesn't yet include that stage
- On resume, the coordinator re-runs that stage from the start

Re-running a stage is safe because:
- Stage 2 (writing-specs): re-renders the spec.md (idempotent given the same understanding)
- Stage 3/9 (reviewers): re-dispatches the reviewer (subagent is fresh anyway)
- Stage 4 (grill): the user can decide to skip if previous grill already happened
- Stage 6 (ADRs): subagent checks for duplicates against existing ADRs
- Stage 8 (writing-plans): re-renders the plan.md
- Stage 12 (choosing-feature-branch): batch-commit failures halt the pipeline; the user resolves and re-invokes
- Stage 13 (implementation): `tasks` map tells the loop which tasks are done

### Mid-task interruption (Stage 13)

If Stage 13 was interrupted mid-task:
- `current_stage`: `implementing`
- `tasks`: shows `T###: "in_progress"` for the task that was running
- `stages_completed`: doesn't include `implementation_complete`

On resume:
- Coordinator notes T### is in_progress
- Re-dispatches T### from the start (fresh implementer subagent — context isolation guarantees safety)
- Continues the loop

Per-task work is fully isolated; re-dispatching is safe. No need for fine-grained per-step state.

---

## Config file (`.sublime-skills/config.yml`)

### What it is

A YAML file at `.sublime-skills/config.yml` in the repo root. **The single source of truth** for project paths and per-stage behavior. Created by `bootstrapping-project` (in the `project-bootstrap/` family), which copies the scaffold file verbatim — no AI regeneration.

**The config is required, not optional, and must be valid.** `preflight-checks` (Stage 0 of the SDD pipeline) runs `scripts/validate-config.sh` as its first step on every invocation and halts on any non-zero exit (missing file, malformed YAML, orphan context path, unknown key). The framework reads every path from this file (context files, memory file, etc.); running without a valid config is unsupported, not a degraded mode.

The scaffold lives at `project-bootstrap/scaffolds/config.yml` and is what gets copied. If you want to change the defaults across all new projects, edit the scaffold; if you want to change one repo's behavior, edit its `.sublime-skills/config.yml`.

### Full schema with defaults

Mirror of the scaffold file. Each key is explicit — there is **no** auto-fallback search; the discovery script and skills consult config for every path.

```yaml
# ── Context files ───────────────────────────────────────────────────
# Single explicit path per artifact. null means "this project doesn't
# have one." There is no auto-fallback to other locations — if you move
# a file, update this block.
context:
  constitution_path: docs/constitution.md
  architecture_path: docs/ARCHITECTURE.md
  glossary_path: docs/GLOSSARY.md
  domain_path: docs/DOMAIN.md
  design_path: docs/DESIGN.md

# ── Branching (Stage 12) ────────────────────────────────────────────
branching:
  # Pattern for derived feature branch names; {short-name} substituted.
  # Used by the `choosing-feature-branch` skill (Stage 12) when offering
  # to create a feature branch. Bug-fix runs (state.work_type == "fix")
  # use `fix/{short-name}` automatically.
  branch_pattern: "feat/{short-name}"

# ── Grill (Stage 4) ─────────────────────────────────────────────────
grill:
  # Soft cap on questions per grill session. Hard ceiling is 20 even
  # with an override.
  question_cap: 10

# ── Memory file maintenance (Stage 16) ──────────────────────────────
# Stage 16 itself is user-prompted at runtime; this block only configures
# which file is maintained and the size budget. There is no `enabled`
# toggle — the user decides per-run.
memory_file:
  # Explicit path. null = auto-detect at repo root in order:
  # CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md (first match wins).
  # If nothing matches, Stage 16 auto-skips without prompting.
  path: null

  # Soft cap on memory file size (characters). Skill warns at 90% of
  # this value and refuses to push past 100% (must prune first).
  character_limit: 40000
```

**Stages 14 (testing), 15 (handoff), and 16 (memory file) are user-prompted at runtime**, not config-toggled. The coordinator asks `yes/no` per run. If you want to skip all of them every time, just answer `no` when prompted — but most users will want to make the choice per feature.

**V1 does NOT include a `finishing:` config block.** Stage 17 (`finishing-sdd`) prints a summary and deletes the state file. No merge/PR/branch-deletion behavior is configurable — those are the user's call after SDD ends.

### Config overlay (`config-local.yml`)

Alongside `config.yml`, the bootstrap also creates an empty `.sublime-skills/config-local.yml`. This is a per-developer overlay layered on top of the base config, modelled on the `appsettings.json` + `appsettings-{env}.json` pattern from .NET.

**Layering rule.** When skills read a config value at `<block>.<key>`, the central reader scripts (`get-config-value.sh`, `discover-context.sh`) look in `config-local.yml` first. If the key is present there (including an explicit `null`), that value wins. Otherwise the read falls through to `config.yml`. There is no deep merge — the schema is flat (block → scalar), so per-key precedence is sufficient.

**Schema.** `config-local.yml` uses the same schema as `config.yml`, but every key is optional. You override only the keys you care about. Example:

```yaml
# .sublime-skills/config-local.yml — per-developer overrides
branching:
  branch_pattern: "feature/{short-name}"
memory_file:
  character_limit: 60000
```

The other keys (context, the rest of branching, grill, the rest of memory_file) fall through to `config.yml`'s values.

**Git.** `config.yml` is committed; `config-local.yml` is gitignored. The bootstrap appends `.sublime-skills/config-local.yml` to `.gitignore` in Step 7. Each developer's overlay is their own; no one else sees it.

**Validation.** `validate-config.sh` reads both files, sanity-checks the overlay's block + key names (typo'd keys like `finshing:` or `mode_x:` fail), then merges the overlay into the base before running the existing structural checks. Type errors, enum errors, and orphan paths in the merged result are caught regardless of which file the offending value came from. Overlay-specific findings are prefixed with `config-local.yml:` so it's clear where to fix them.

**Empty is fine.** A zero-byte `config-local.yml` is treated as "no overrides." The bootstrap creates it empty on a fresh project.

**Awk fallback.** When python3 + PyYAML are unavailable, `validate-config.sh` falls back to an awk-based scanner that validates the base config only. If `config-local.yml` exists in that mode, the validator emits a `WARN` saying overlay validation was skipped.

### How skills consume config

Each skill that depends on config reads it explicitly. The pattern is:

1. Read config via the central scripts. `get-config-value.sh <block> <key>` returns a single scalar; `discover-context.sh` returns the bulk of paths as JSON. Both scripts honor `config-local.yml` overlay automatically. Skills that need list-typed or multi-line values should overlay manually if they parse the YAML themselves.
2. Use the value verbatim. There is **no auto-fallback** to other locations — if a key is null or absent in both files, that's the answer.
3. If `.sublime-skills/config.yml` is missing entirely or fails `validate-config.sh`, the project hasn't been bootstrapped for SDD; the user should run `bootstrapping-project` first.

The coordinator caches the config once at session start (after the resume check) and passes relevant values into each skill dispatch.

### Common overrides

**Custom branch naming pattern:**

```yaml
branching:
  branch_pattern: "feature/{short-name}"
```

Used by `choosing-feature-branch` (Stage 12) when suggesting a feature branch name. Bug-fix runs (when `state.work_type == "fix"`) swap `feat/` to `fix/` automatically.

**Memory file maintenance (CLAUDE.md / AGENTS.md / etc.):**

```yaml
memory_file:
  path: "CLAUDE.md"        # or AGENTS.md, GEMINI.md, .agents.md, or absolute path
  character_limit: 40000   # widely-recommended soft cap for agent memory files
```

`path: null` auto-detects at repo root (CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md). If nothing matches, Stage 16 auto-skips without prompting. When a path IS resolved, the coordinator prompts `yes/no` per run — answer `no` if this particular run doesn't deserve attention. Most runs result in "no update needed" anyway.

**Custom context file locations:**

```yaml
context:
  constitution_path: docs/principles.md
  architecture_path: docs/internal/ARCH.md
  glossary_path: null               # this project doesn't have one
  design_path: null                 # CLI tool — no UI surface
```

Each key is a single explicit path or `null`. The SDD pipeline expects a single canonical pointer per artifact, not a list. If your project keeps a convention file at a non-default path (e.g., `docs/internal/ARCH.md`), point the corresponding `<name>_path` at it. `design_path: null` is the right choice for CLI tools, libraries, or backend services with no visual UI surface — the bootstrapper's `discovering-design` skill detects the absence of a UI surface during its code scan and surfaces Skip as the recommended option for such projects.

### Hard ceilings (not overridable)

A few values have hard ceilings that override config:

| Setting | Config | Hard ceiling |
|---|---|---|
| `grill.question_cap` | 10 (default) | 20 |
| Per-task spec-compliance review iterations | 3 (fixed) | — |
| Per-task code-quality review iterations | 3 (fixed) | — |
| Test fix-loop iterations | 3 (fixed) | — |
| Spec/plan review fix iterations | 2 (fixed) | — |

Iteration caps are deliberately not config-overridable. Hitting a cap means something is wrong with the plan or spec, and the user should be involved.

### What's NOT in config

The following are deliberately not config:

- Per-skill behaviors (each skill has its own internal rules; if you want to change them, edit the skill)
- The list of allowed `[NO-TDD]` categories (defined in `writing-plans` skill; changing them requires a skill edit)
- The redaction patterns in `generating-handoff` (defined in the skill)
- The diagram prohibitions (Mermaid, C4, PlantUML, ASCII — defined in skills)
- Subagent prompts (in the template files alongside the orchestrating skills)

If you want to change one of these, edit the corresponding skill file. The config is for project-wide preferences that vary per repo, not for per-pipeline behavior knobs.

---

## Interaction between state and config

The config is **read** at session start by the coordinator. Some of its values are passed to skills as parameters; others affect the coordinator's own behavior.

The state file is **written** as the pipeline progresses. It doesn't reference the config directly (the config might change between sessions; the state file shouldn't capture a snapshot of it).

If the config changes mid-pipeline (rare but possible):
- The change takes effect on the next stage boundary
- Already-completed stages aren't re-run
- Stages that depend on config (e.g., `memory_file.path`) honor the new value

---

## Worked example: a state file mid-implementation

Suppose feature `003-user-auth` is being implemented; the user just started task T004 and the session died. The state file looks like:

```json
{
  "feature_id": "003-user-auth",
  "short_name": "user-auth",
  "started_at": "2026-05-20T14:32:00Z",
  "updated_at": "2026-05-20T16:45:00Z",
  "spec_path": "docs/specs/003-user-auth/spec.md",
  "plan_path": "docs/specs/003-user-auth/plan.md",
  "current_stage": "implementing",
  "stages_completed": [
    "preflight", "discovering", "spec_written",
    "spec_auto_reviewed", "adrs_maintained", "spec_approved",
    "plan_written", "plan_auto_reviewed", "plan_approved"
  ],
  "stages_skipped": [
    "spec_grill", "spec_second_review",
    "plan_second_review"
  ],
  "adr_results": [
    {
      "id": "ADR-0003",
      "title": "Use JWT for session tokens",
      "status": "Accepted",
      "path": "docs/adr/0003-use-jwt-for-sessions.md"
    }
  ],
  "tasks": {
    "T001": "completed",
    "T002": "completed",
    "T003": "completed",
    "T004": "in_progress",
    "T005": "pending",
    "T006": "pending",
    "T007": "pending"
  },
  "test_status": null,
  "fix_iterations": 0,
  "final_review_completed": false,
  "handoff_path": null,
  "reviewer_pushbacks": [],
  "spec_auto_review_iterations": 1,
  "plan_auto_review_iterations": 1
}
```

**What the next invocation sees:**

1. Coordinator globs for state files; finds `docs/specs/003-user-auth/state.json`.
2. Coordinator confirms with user: "Resume `003-user-auth` at `implementing`?"
3. On yes: coordinator loads `implementing-plans`. The skill notes T004 is in_progress, re-dispatches T004 with a fresh implementer subagent.
4. T004 completes, coordinator marks it complete in state file, moves on to T005.

No re-reading the entire history; the state file is enough.

---

## Validating state file integrity

The state file is the contract that lets the coordinator resume — if it's malformed the coordinator can't reliably continue. The schema in `scripts/state-schema.md` / `state-schema.json` defines what valid means: required fields present, enum values from the documented sets, stage progression consistent (e.g., `current_stage: "implementing"` implies `plan_approved` is in `stages_completed`).

In practice, malformed state is rare — every writer uses the atomic `.tmp → mv` pattern, so a half-written file never replaces the previous good one. If it does happen (the user hand-edited the file, or some external tool corrupted it), the coordinator surfaces the issue to the user rather than guessing. Repair is the user's call, not the coordinator's.
