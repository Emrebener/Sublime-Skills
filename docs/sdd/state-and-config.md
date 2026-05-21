# State and Configuration

This document covers two things that aren't artifacts in the user-facing sense but are critical to the pipeline working: the per-feature **state file** that tracks pipeline progress and enables resumption, and the per-repo `.sublime-skills/config.yml` **configuration file** that lets users override defaults.

---

## State file

### What it is

A JSON file at `docs/specs/NNN-<short-name>/state.json`, one per in-progress SDD run. It holds everything the coordinator needs to know to resume an interrupted pipeline from any stage.

### Lifecycle

| Stage | What happens to state.json |
|---|---|
| 0 (Preflight) | Does NOT exist yet. Preflight outputs are held in coordinator's in-memory dict. |
| 1 (Discovery) | Still does not exist. Discovery outputs in memory. |
| 2 (Writing spec) | **Created** by `writing-specs`, atomic write. Pre-populated with feature_id, branch, paths, preflight outcomes from in-memory. |
| 3-13 | **Updated at every stage boundary** by the coordinator (atomic). Stage 12 (`implementing-plans`) also updates `tasks` per-task. |
| 14 (Handoff) | Updated with `handoff_path`. |
| 15 (Finishing) | **Deleted** for Merge/PR/Discard. **Kept** for Keep-As-Is. |

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

State.json is **committed alongside the relevant artifact**:

- Stage 2: committed with `spec.md` in `spec(NNN): initial draft`
- Stage 5: committed with updated `spec.md` in `spec(NNN): grill session updates`
- Stage 6: committed with new ADRs in `docs(adr): NNNN from spec NNN`
- Stage 7: committed if any spec/ADR edits happened during approval
- Stage 8: committed with `plan.md` in `plan(NNN): initial draft`
- Stage 12: committed at end of implementation in `chore(NNN): mark implementation complete`
- Stage 14: committed with handoff doc in `docs(NNN): handoff document`
- Stage 15: committed with memory file in `docs(memory): update from NNN-short-name` (only if memory file was updated; usually no commit)
- Stage 16: deletion is committed (or amended into final commit, per project preference)

No standalone "update state" commits — state always rides along with content.

**Squash-merge implication:** if the project squashes on merge, the state file's churn collapses into a single final commit. By the time the feature lands in main, only the spec, plan, ADRs, and handoff persist; the state file is gone.

### Resume protocol

The coordinator's first action on every invocation is to load `inspecting-state`, which produces a structured report. Based on the report:

**Case: 0 active runs, on main/master, clean tree**
- Treat as fresh start
- Confirm intent: "Start a new feature?"

**Case: 0 active runs, on a non-default branch (no state file)**
- Pre-state-file interruption suspected (preflight ran but writing-specs didn't)
- Ask user: resume from Stage 1, start fresh, or abandon
- Never silently pick

**Case: 1 active run, valid state**
- Announce: "Resuming feature X at stage Y"
- Confirm with user: "Resume? (yes/no)"
- On yes: jump to the appropriate stage based on `current_stage`
- On no: ask what user wants (start fresh / inspect state / abandon)

**Case: 2+ active runs**
- List all of them with their stages
- Ask user which to resume
- Never silently pick

**Case: Malformed state**
- Show user what's broken (parse error, missing required fields, etc.)
- Offer: repair (user-guided), discard and start fresh, or abort coordinator
- Never silently overwrite

### Mid-stage interruption

The coordinator's `current_stage` field indicates the stage that's IN PROGRESS. After completion, it advances to the next stage and adds the completion marker to `stages_completed`.

If the session dies between "stage starts" and "stage completes":
- `current_stage` still shows the in-progress stage
- `stages_completed` doesn't yet include that stage
- On resume, the coordinator re-runs that stage from the start

Re-running a stage is safe because:
- Stage 2 (writing-specs): re-renders the spec.md (idempotent given the same understanding)
- Stage 3/9 (reviewers): re-dispatches the reviewer (subagent is fresh anyway)
- Stage 5 (grill): the user can decide to skip if previous grill already happened
- Stage 6 (ADRs): subagent checks for duplicates against existing ADRs
- Stage 8 (writing-plans): re-renders the plan.md
- Stage 12 (implementation): `tasks` map tells the loop which tasks are done

### Mid-task interruption (Stage 12)

If Stage 12 was interrupted mid-task:
- `current_stage`: `implementing`
- `tasks`: shows `T###: "in_progress"` for the task that was running
- `stages_completed`: doesn't include `implementation_complete`

On resume:
- Coordinator notes T### is in_progress
- Re-dispatches T### from the start (fresh implementer subagent — context isolation guarantees safety)
- Continues the loop

Per-task work is fully isolated; re-dispatching is safe. No need for fine-grained per-step state.

### Cross-machine resume

If a user pulls the feature branch on a different machine and re-invokes the coordinator:
- The state file comes along with the branch (it's committed)
- `inspecting-state` finds it
- Coordinator resumes normally

Provided git history is intact, cross-machine resume works without ceremony.

---

## Config file (`.sublime-skills/config.yml`)

### What it is

A YAML file at `.sublime-skills/config.yml` in the repo root. **The single source of truth** for project paths and per-stage behavior. Created by `bootstrapping-project` (in the `project-bootstrap/` family), which copies the scaffold file verbatim — no AI regeneration.

**The config is required, not optional, and must be valid.** `preflight-checks` (Stage 0 of the SDD pipeline) runs `scripts/validate-config.sh` as its first step on every invocation and halts on any non-zero exit (missing file, malformed YAML, orphan context path, unknown key). The framework reads every path from this file (spec_dir, adr_dir, handoff_dir, context files, memory file, etc.); running without a valid config is unsupported, not a degraded mode.

The scaffold lives at `project-bootstrap/scaffolds/config.yml` and is what gets copied. If you want to change the defaults across all new projects, edit the scaffold; if you want to change one repo's behavior, edit its `.sublime-skills/config.yml`.

### Full schema with defaults

Mirror of the scaffold file. Each key is explicit — there is **no** auto-fallback search; the discovery script and skills consult config for every path.

```yaml
# ── Paths ────────────────────────────────────────────────────────────
# handoff_dir may be either repo-relative (default; committed alongside the
# run) OR absolute / ~ -expanded (e.g. /home/user/sdd-handoffs/) to write
# handoffs OUTSIDE the repo. Absolute paths are not committed; the
# coordinator records the resolved path in state.json.
paths:
  spec_dir: docs/specs          # spec.md, plan.md, state.json live under spec_dir/NNN-name/
  adr_dir: docs/adr             # ADRs as NNNN-kebab.md
  handoff_dir: docs/handoff     # handoffs as YYYY-MM-DD-kebab.md (or absolute path)

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

# ── Preflight (Stage 0) ─────────────────────────────────────────────
preflight:
  # Pattern for derived feature branch names; {short-name} substituted.
  # Used when starting fresh from main/master. Bug-fix runs use
  # `fix/{short-name}` automatically.
  branch_pattern: "feat/{short-name}"

  # If true, work happens in .worktrees/<sanitized-branch>/ rather than
  # the main checkout. Lets you continue unrelated work in the main
  # checkout while an SDD run is in progress.
  use_worktree: false

# ── Grill (Stage 5) ─────────────────────────────────────────────────
grill:
  # Soft cap on questions per grill session. Hard ceiling is 20 even
  # with an override.
  question_cap: 10

# ── Memory file maintenance (Stage 15) ──────────────────────────────
# Stage 15 itself is user-prompted at runtime; this block only configures
# which file is maintained and the size budget. There is no `enabled`
# toggle — the user decides per-run.
memory_file:
  # Explicit path. null = auto-detect at repo root in order:
  # CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md (first match wins).
  # If nothing matches, Stage 15 auto-skips without prompting.
  path: null

  # Soft cap on memory file size (characters). Skill warns at 90% of
  # this value and refuses to push past 100% (must prune first).
  character_limit: 40000

# ── Finishing (Stage 16) ────────────────────────────────────────────
finishing:
  # prompt       — interactive 4-option menu (default)
  # leave        — skip menu; leave branch as-is
  # merge-local  — skip menu; merge into merge_target
  # pr           — skip menu; push + create PR via pr_command
  # auto         — PR if remote+pr_command, else merge-local, else leave
  mode: prompt

  # Base branch for merge / PR target.
  merge_target: main

  # Delete the feature branch after a local merge.
  delete_branch_after_merge: true

  # Explicit test command for finishing-sdd's pre-merge sanity check.
  # null = auto-detect (Makefile → npm → cargo → pytest → go → mvn → gradle).
  # Set explicitly for Makefile-driven repos, nox/tox, monorepos, etc.
  test_command: null

  # PR command template. Placeholders: {title}, {body_file}.
  pr_command: "gh pr create --title '{title}' --body-file {body_file}"

  # PR body template. Placeholders: {summary} (from spec Goal),
  # {test_plan} (from acceptance scenarios), {spec_link}, {plan_link}.
  pr_body_template: |
    ## Summary
    {summary}

    ## Test plan
    {test_plan}

    ## Spec
    {spec_link}

    ## Plan
    {plan_link}
```

**Stages 14 (handoff) and 15 (memory file) are user-prompted at runtime**, not config-toggled. The pattern matches Stage 13 (testing): the coordinator asks `yes/no` per run. If you want to skip both every time, just answer `no` when prompted — but most users will want to make the choice per feature.

### Config overlay (`config-local.yml`)

Alongside `config.yml`, the bootstrap also creates an empty `.sublime-skills/config-local.yml`. This is a per-developer overlay layered on top of the base config, modelled on the `appsettings.json` + `appsettings-{env}.json` pattern from .NET.

**Layering rule.** When skills read a config value at `<block>.<key>`, the central reader scripts (`get-config-value.sh`, `discover-context.sh`) look in `config-local.yml` first. If the key is present there (including an explicit `null`), that value wins. Otherwise the read falls through to `config.yml`. There is no deep merge — the schema is flat (block → scalar), so per-key precedence is sufficient.

**Schema.** `config-local.yml` uses the same schema as `config.yml`, but every key is optional. You override only the keys you care about. Example:

```yaml
# .sublime-skills/config-local.yml — per-developer overrides
preflight:
  use_worktree: true
finishing:
  mode: pr
```

The other keys (paths, context, grill, memory_file, the rest of preflight + finishing) fall through to `config.yml`'s values.

**Git.** `config.yml` is committed; `config-local.yml` is gitignored. The bootstrap appends `.sublime-skills/config-local.yml` to `.gitignore` in Step 7. Each developer's overlay is their own; no one else sees it.

**Validation.** `validate-config.sh` reads both files, sanity-checks the overlay's block + key names (typo'd keys like `finshing:` or `mode_x:` fail), then merges the overlay into the base before running the existing structural checks. Type errors, enum errors, and orphan paths in the merged result are caught regardless of which file the offending value came from. Overlay-specific findings are prefixed with `config-local.yml:` so it's clear where to fix them.

**Empty is fine.** A zero-byte `config-local.yml` is treated as "no overrides." The bootstrap creates it empty on a fresh project.

**Awk fallback.** When python3 + PyYAML are unavailable, `validate-config.sh` falls back to an awk-based scanner that validates the base config only. If `config-local.yml` exists in that mode, the validator emits a `WARN` saying overlay validation was skipped.

### How skills consume config

Each skill that depends on config reads it explicitly. The pattern is:

1. Read config via the central scripts. `get-config-value.sh <block> <key>` returns a single scalar; `discover-context.sh` returns the bulk of paths as JSON. Both scripts honor `config-local.yml` overlay automatically. Skills that need list-typed or multi-line values (currently just `finishing.pr_body_template`) should also overlay manually if they parse the YAML themselves.
2. Use the value verbatim. There is **no auto-fallback** to other locations — if a key is null or absent in both files, that's the answer.
3. If `.sublime-skills/config.yml` is missing entirely or fails `validate-config.sh`, the project hasn't been bootstrapped for SDD; the user should run `bootstrapping-project` first.

The coordinator caches the config once at session start (after `inspecting-state`) and passes relevant values into each skill dispatch.

### Common overrides

**Always create a PR, no interactive menu:**

```yaml
finishing:
  mode: pr
  pr_command: "gh pr create --title '{title}' --body-file {body_file}"
```

**Always leave the branch alone at the end:**

```yaml
finishing:
  mode: leave
```

**Use worktrees:**

```yaml
preflight:
  use_worktree: true
```

(The skill will verify `.worktrees/` is gitignored before creating one. If it's not, the skill adds it to `.gitignore` and commits before proceeding.)

**Custom paths:**

```yaml
paths:
  spec_dir: docs/features
  adr_dir: docs/decisions
  handoff_dir: docs/handoffs
```

**Memory file maintenance (CLAUDE.md / AGENTS.md / etc.):**

```yaml
memory_file:
  path: "CLAUDE.md"        # or AGENTS.md, GEMINI.md, .agents.md, or absolute path
  character_limit: 40000   # the widely-recommended soft cap for Claude Code
```

`path: null` auto-detects at repo root (CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md). If nothing matches, Stage 15 auto-skips without prompting. When a path IS resolved, the coordinator prompts `yes/no` per run — answer `no` if this particular run doesn't deserve attention. Most runs result in "no update needed" anyway.

**Explicit test command (Makefile, nox, monorepo, etc.):**

```yaml
finishing:
  test_command: "make test"
# or
finishing:
  test_command: "nox -s tests"
```

When set, `finishing-sdd`'s Step 1 sanity check runs exactly this command instead of auto-detecting. Required for any project whose entry point doesn't match the auto-detect priority list (Makefile/npm/cargo/pytest/go/mvn/gradle).

**Handoff outside the repo (not committed):**

```yaml
paths:
  handoff_dir: /home/user/sdd-handoffs    # absolute path
  # or
  handoff_dir: ~/notes/sdd                # tilde expanded to $HOME
```

When `handoff_dir` resolves outside the repo's working tree, the handoff file is written but NOT staged or committed. The path is recorded in `state.json` so other tooling can find it. The state-file commit at Stage 14 only includes `state.json`, not the handoff itself.

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
- Stages that depend on config (e.g., `paths.handoff_dir` or `memory_file.path`) honor the new value

If a config field is renamed or removed in a future SDD version:
- Old config files keep working (unrecognized keys are ignored)
- The coordinator emits a warning if it sees deprecated keys

---

## Worked example: a state file mid-implementation

Suppose feature `003-user-auth` is being implemented; the user just started task T004 and the session died. The state file looks like:

```json
{
  "feature_id": "003-user-auth",
  "short_name": "user-auth",
  "started_at": "2026-05-20T14:32:00Z",
  "updated_at": "2026-05-20T16:45:00Z",
  "branch": "feat/user-auth",
  "spec_path": "docs/specs/003-user-auth/spec.md",
  "plan_path": "docs/specs/003-user-auth/plan.md",
  "current_stage": "implementing",
  "stages_completed": [
    "preflight", "discovering", "spec_written",
    "spec_auto_reviewed", "adrs_maintained", "spec_approved",
    "plan_written", "plan_auto_reviewed", "plan_approved"
  ],
  "stages_skipped": [
    "spec_second_review", "spec_grill",
    "plan_second_review"
  ],
  "preflight": {
    "worktree_path": null,
    "original_branch": "main"
  },
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

**What the next session sees:**

1. Coordinator runs `inspecting-state`. Report: "1 active run found: 003-user-auth at stage `implementing`. Tasks: 3 completed, 1 in_progress, 3 pending."
2. Coordinator confirms with user: "Resume SDD run for 003-user-auth at task T004? (yes/no)"
3. On yes: coordinator loads `implementing-plans`. The skill notes T004 is in_progress, re-dispatches T004 with a fresh implementer subagent.
4. T004 completes, coordinator marks it complete in state file, moves on to T005.

No re-reading the entire history; the state file is enough.

---

## Validating state file integrity

`inspecting-state` validates each state file it finds. Issues it flags:

- **Unparseable JSON** → reports the parse error
- **Missing required fields** → reports which are missing
- **Inconsistent state** — e.g., `tasks` is non-empty but `plan_path` is null (plan stage should have come first)
- **Stage progression violation** — e.g., `current_stage: "implementing"` but `stages_completed` doesn't include `plan_approved`

For each issue, the report includes specific evidence (line numbers, field paths, expected vs actual).

The coordinator decides what to do with the report (offers user repair / discard / abort options).

`inspecting-state` itself never modifies the state file. Repair, if requested, is the coordinator's job (with user guidance).
