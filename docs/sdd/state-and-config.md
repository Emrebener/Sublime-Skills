# State and Configuration

This document covers two things that aren't artifacts in the user-facing sense but are critical to the pipeline working: the per-feature **state file** that tracks pipeline progress and enables resumption, and the per-repo `.sdd/config.yml` **configuration file** that lets users override defaults.

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
- Stage 15: deletion is committed (or amended into final commit, per project preference)

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

## Config file (`.sdd/config.yml`)

### What it is

A YAML file at `.sdd/config.yml` in the repo root. Optional — the pipeline works fine without it, using built-in defaults. Present when:
- `initializing-project-context` was run (creates it with defaults)
- The user created or edited it manually

### Full schema with defaults

```yaml
# .sdd/config.yml — SDD project configuration

# ── Paths ────────────────────────────────────────────────────────────
# Where the pipeline writes its artifacts. Defaults shown.
#
# handoff_dir may be either repo-relative (default, will be committed alongside
# the run) OR an absolute path (e.g., /home/user/sdd-handoffs/ or ~/notes/sdd/)
# to write handoffs OUTSIDE the repo. Absolute paths are not committed; the
# coordinator records the path in state.json and informs the user.
paths:
  spec_dir: docs/specs          # spec.md and plan.md live under spec_dir/NNN-name/
  adr_dir: docs/adr             # ADRs as NNNN-kebab.md
  handoff_dir: docs/handoff     # handoffs as YYYY-MM-DD-kebab.md (or abs path)

# ── Context file overrides ──────────────────────────────────────────
# Where to look for project convention files. Skills check these BEFORE
# the defaults in discover-context.sh. Empty list = use defaults.
context:
  constitution_paths: []        # e.g., [docs/principles.md]
  architecture_paths: []        # e.g., [docs/internal/ARCH.md]
  context_paths: []
  glossary_paths: []
  domain_paths: []
  context_map_paths: []

# ── Preflight (Stage 0) ─────────────────────────────────────────────
preflight:
  # Pattern for derived feature branch names; {short-name} substituted.
  # Used when user starts fresh from main/master.
  branch_pattern: "feat/{short-name}"

  # If true, work happens in .worktrees/<branch-name> instead of in-place.
  use_worktree: false

# ── Grill (Stage 5) ─────────────────────────────────────────────────
grill:
  # Max questions per grill session. Hard ceiling is 20 even with override.
  question_cap: 10

# ── Handoff (Stage 14) ──────────────────────────────────────────────
handoff:
  # If false, Stage 14 is skipped and handoff is added to stages_skipped.
  enabled: true

# ── Finishing (Stage 15) ────────────────────────────────────────────
finishing:
  # prompt: interactive 4-option menu (default)
  # leave: skip menu; leave branch as-is
  # merge-local: skip menu; merge into merge_target
  # pr: skip menu; push + create PR using pr_command
  # auto: PR if remote+pr_command, else merge-local, else leave
  mode: prompt

  # Base branch for merge / PR target.
  merge_target: main

  # Delete the feature branch after merge.
  delete_branch_after_merge: true

  # Explicit test command for finishing-sdd's pre-merge sanity check.
  # null = auto-detect (Makefile → npm → cargo → pytest → go → mvn → gradle, first match wins).
  # Set explicitly for Makefile-driven repos, nox/tox, monorepos, or anything that
  # doesn't fit the auto-detect priority list.
  test_command: null

  # PR command template. Default uses gh.
  # Placeholders: {title}, {body_file}.
  pr_command: "gh pr create --title '{title}' --body-file {body_file}"

  # PR body template. Used by finishing-sdd to compose the PR body.
  # Placeholders: {summary} (from spec Goal), {test_plan} (from acceptance scenarios),
  # {spec_link}, {plan_link}.
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

### How skills consume config

Each skill that's affected by config reads it explicitly. The pattern is:

1. Check if `.sdd/config.yml` exists.
2. If yes, parse it (skills do this themselves; the shared `discover-context.sh` doesn't parse YAML).
3. For each relevant key, prefer the config value over the default.

The coordinator caches the config once at session start (after `inspecting-state`) and passes relevant values into each skill dispatch.

### Common overrides

**Disable handoff for fast-iteration features:**

```yaml
handoff:
  enabled: false
```

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

**Custom context file locations (monorepo with nested ARCHITECTURE.md):**

```yaml
context:
  architecture_paths:
    - docs/internal/ARCH.md
    - services/billing/ARCH.md
    - services/checkout/ARCH.md
```

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
- Stages that depend on config (e.g., handoff if `handoff.enabled` changes) honor the new value

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
