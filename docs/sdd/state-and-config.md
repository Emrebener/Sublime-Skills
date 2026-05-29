# State and Configuration

This document covers two things that aren't artifacts in the user-facing sense but are critical to the pipeline working: the per-feature **state file** that carries data between stages and coordinates subagents, and the per-repo `.sublime-skills/config.yml` **configuration file** that lets users override defaults.

---

## State file

### What it is

A JSON file at `.sublime-skills/state.json` — a single global file representing the one active SDD run (absent between runs). It holds the orchestration record the coordinator and per-task subagents share within a conversation, plus the structured outputs each subagent writes back (ADR list, per-task statuses, etc.). It is NOT a resume mechanism — SDD runs end-to-end inside a single conversation, where conversation context tells the coordinator where it is. Any leftover state file from a dead prior conversation is silently removed by preflight at the next fresh run.

### Lifecycle

| Stage | What happens to state.json |
|---|---|
| 0 (Preflight) | **Created** as a minimal shell at the end of preflight, after all validation passes. Contains only the always-required fields (`started_at`, `updated_at`, `current_stage: "preflight"`, empty `stages_completed` / `stages_skipped`, empty `tasks`). Any pre-existing file is treated as an orphan from a dead prior pipeline and silently removed before the shell is written. **Gitignored from the start.** |
| 1 (Discovery) | Coordinator advances `current_stage` to `discovering` at the stage boundary. Discovery outputs (`short_name`, `work_type`, etc.) are held in coordinator memory and persisted by `ss-sdd-writing-specs` at Stage 2. |
| 2 (Writing spec) | `ss-sdd-writing-specs` writes the feature-identifying fields into the existing shell: `feature_id`, `short_name`, `work_type`, `spec_path`. Atomic write. Coordinator then advances `current_stage`. |
| 3–6 | **Updated** at every stage boundary by the coordinator (atomic). Gitignored throughout. |
| 7 (Choosing branch) | Updated atomically (`current_stage: implementing`, `branch_name: "<chosen branch>"`). The spec / plan / ADRs are batch-committed in two thematic commits on the chosen branch; state.json is NOT in any commit. `branch_name` is later read by Stage 11 to know what to merge. |
| 8 (Implementing) | Updated per-task with `tasks` transitions (atomic, on disk only). |
| 9 (Testing) | Updated with `test_status` and `fix_iterations`. No state commit. |
| 10 (Memory file) | Updated with `memory_file_updated` and `memory_file_path`. No state commit (memory file itself is committed if updated). |
| 11 (Finishing) | Read for `branch_name`. Stage 11 runs `git checkout main && git merge --no-ff $branch_name && git branch -d $branch_name` (halt on any failure; state stays so the user can re-run Stage 11 after resolving). On success, state.json is **deleted** via plain `rm`. No commit. |

### Atomic write pattern

Every write is atomic:

```bash
# Write to .tmp, then atomically rename
cat > .sublime-skills/state.json.tmp <<EOF
{ ... }
EOF
mv .sublime-skills/state.json.tmp .sublime-skills/state.json
```

This prevents partial writes from corrupting state if the session dies mid-write.

### Schema

**The canonical schema lives at `skills/spec-driven-development/framework/state-schema.md`** (human-readable, complete field list + ownership + enums + stage mapping) and `state-schema.json` (machine-readable JSON Schema Draft 2020-12).

This document is a companion that shows worked examples and explains the lifecycle in narrative form. If schema details in this document and the canonical disagree, **the canonical wins** — please update this doc to match.

See `framework/state-schema.md` for:
- Complete list of required and optional fields
- Field types and enum values
- Field ownership (who writes what, when)
- Full Stage Name Mapping table including `stages_skipped` enum
- Reference example (mid-implementation snapshot)

Worked examples in this document are still accurate; if you spot drift, file it as a bug against `framework/state-schema.md` first.

### Git policy

`.sublime-skills/state.json` is **permanently gitignored** via `.sublime-skills/.gitignore`. It is never committed at any stage. The rule is enforced by:

1. The bootstrap creates `.sublime-skills/.gitignore` with `state.json` listed.
2. Each state-touching skill has a Hard Gate prohibiting `git add -f` / `--force` / any other bypass.
3. The canonical rule lives in `skills/spec-driven-development/framework/state-schema.md` under "Git policy (CRITICAL)".

The planning artifacts (spec.md, plan.md, ADRs) live at `docs/specs/<feature_id>/` and `docs/adr/`. They are uncommitted through Stages 2-6, then batch-committed by `ss-sdd-choosing-feature-branch` at Stage 7 in two thematic commits:

- `docs(<feature_id>): spec and plan` — spec.md + plan.md
- `docs(adr): N decisions for <feature_id>` — ADRs (skipped if none)

From Stage 8 onward, commits happen per stage by the active skill, alongside their own artifacts (code, memory file, etc.) — never with state.json.

**All commits use path-scoped `git add`.** No `git add .` / `git add -A` — preflight allows dirty working trees, so path-scoping is what protects the user's pre-existing dirty files.

**Mid-pipeline branch operations are safer than before.** Because `.sublime-skills/state.json` is gitignored:
- `git checkout other-branch` leaves the state file in place
- `git stash -u` skips it (gitignored files aren't stashed even with `-u`)
- Branch operations don't disturb state

The planning artifacts (spec.md, plan.md, ADRs) still need protection through Stages 2-6 — they're untracked, so the same `git stash` / `git checkout` warning applies to them.

### Why the file exists

SDD runs end-to-end inside one conversation. The coordinator never "exits and re-enters" — conversation context already tells it which stage it's in. So the state file is not a resume mechanism. It exists for two concrete reasons:

1. **Subagent orchestration.** Dispatched subagents (reviewers, ADR maintainer, per-task implementers, tester, memory-file maintainer) die after they return. The coordinator records each subagent's structured outputs into state (`adr_results`, `tasks` transitions, `memory_file_*`, `reviewer_pushbacks`, etc.) so later stages and later subagents see them.
2. **Per-task coordination at Stage 8.** Each task is a fresh implementer subagent. The `tasks` map is how `ss-sdd-implementing-plans` decides which task to dispatch next: a task at `"in_progress"` (its subagent died before reporting completion) is re-dispatched from the start; `"pending"` tasks run in plan order; `"completed"` tasks are skipped.

That's the whole purpose. Cross-conversation resume, cross-machine recovery, multi-user collaboration, and recovery from destructive git operations are explicitly out of scope.

### Halt-and-continue cases

Two stages can halt the pipeline mid-run after partially modifying the working tree, in which case state stays on disk so the user can resolve the underlying issue and tell the coordinator to continue:

- **Stage 7 (`ss-sdd-choosing-feature-branch`) — commit failure.** Hook rejection, signing failure, missing identity. State has `current_stage: "choosing_branch"` and `branch_chosen` is NOT yet in `stages_completed`, so continuing re-runs Stage 7.
- **Stage 11 (`ss-sdd-finishing`) — merge failure.** Merge conflict, hook rejection, or signing failure on the merge commit. The skill leaves the working tree as-is and does NOT delete the state file; continuing re-runs Stage 11, which is naturally idempotent (`git merge --no-ff` on an already-merged branch returns 0 with "Already up to date").

Both paths are "user resolves, asks the coordinator to continue" — same conversation, no resume ceremony.

---

## Config file (`.sublime-skills/config.yml`)

### What it is

A YAML file at `.sublime-skills/config.yml` in the repo root. **The single source of truth** for project paths and per-stage behavior. Created by `ss-bs-bootstrapping-project` (in the `skills/project-bootstrap/` family), which copies the scaffold file verbatim — no AI regeneration.

**The config is required, not optional, and must be valid.** `ss-sdd-preflight` (Stage 0 of the SDD pipeline) runs `framework/validate-config.sh` as its first step on every invocation and halts on any non-zero exit (missing file, malformed YAML, orphan context path, unknown key). The framework reads every path from this file (context files, memory file, etc.); running without a valid config is unsupported, not a degraded mode.

The scaffold lives at `skills/project-bootstrap/scaffolds/config.yml` and is what gets copied. If you want to change the defaults across all new projects, edit the scaffold; if you want to change one repo's behavior, edit its `.sublime-skills/config.yml`.

### Full schema with defaults

Mirror of the scaffold file. Each key is explicit — there is **no** auto-fallback search; the discovery script and skills consult config for every path.

```yaml
# ── Context files ───────────────────────────────────────────────────
# Single explicit path per artifact. null means "this project doesn't
# have one." There is no auto-fallback to other locations — if you move
# a file, update this block.
context:
  constitution_path: docs/CONSTITUTION.md
  architecture_path: docs/ARCHITECTURE.md
  glossary_path: docs/GLOSSARY.md
  domain_path: docs/DOMAIN.md
  design_path: docs/DESIGN.md

# ── Branching (Stage 7) ─────────────────────────────────────────────
branching:
  # Pattern for derived feature branch names; {short-name} substituted.
  # Used by the `ss-sdd-choosing-feature-branch` skill (Stage 7) when offering
  # to create a feature branch. Bug-fix runs (state.work_type == "fix")
  # use `fix/{short-name}` automatically.
  branch_pattern: "feat/{short-name}"

# ── Memory file maintenance (Stage 10) ──────────────────────────────
# Stage 10 itself is user-prompted at runtime; this block only configures
# which file is maintained and the size budget. There is no `enabled`
# toggle — the user decides per-run.
memory_file:
  # Explicit path. null = auto-detect at repo root in order:
  # CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md (first match wins).
  # If nothing matches, Stage 10 auto-skips without prompting.
  path: null

  # Soft cap on memory file size (characters). Skill warns at 90% of
  # this value and refuses to push past 100% (must prune first).
  character_limit: 40000
```

**Stages 9 (testing) and 10 (memory file) are user-prompted at runtime**, not config-toggled. The coordinator asks `yes/no` per run. If you want to skip both every time, just answer `no` when prompted — but most users will want to make the choice per feature.

**There is no `finishing:` config block.** Stage 11 (`ss-sdd-finishing`) runs a fixed workflow: print summary → `git checkout main && git merge --no-ff <branch_name>` → `git branch -d <branch_name>` on merge success → `rm .sublime-skills/state.json`. The merge strategy (`--no-ff`), base branch (`main`), delete-safety (`-d` not `-D`), and local-only behavior (no push) are constants, not configurables.

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

The other keys (context, the rest of branching, the rest of memory_file) fall through to `config.yml`'s values.

**Git.** `config.yml` is committed; `config-local.yml` is gitignored. The bootstrap creates `.sublime-skills/.gitignore` (with `config-local.yml` and `state.json` entries) in Step 5; Step 9 is a re-run safety net that re-appends any missing entry. Each developer's overlay is their own; no one else sees it.

**Validation.** `validate-config.sh` reads both files, sanity-checks the overlay's block + key names (typo'd keys like `finshing:` or `mode_x:` fail), then merges the overlay into the base before running the existing structural checks. Type errors, enum errors, and orphan paths in the merged result are caught regardless of which file the offending value came from. Overlay-specific findings are prefixed with `config-local.yml:` so it's clear where to fix them.

**Empty is fine.** A zero-byte `config-local.yml` is treated as "no overrides." The bootstrap creates it empty on a fresh project.

**Awk fallback.** When python3 + PyYAML are unavailable, `validate-config.sh` falls back to an awk-based scanner that validates the base config only. If `config-local.yml` exists in that mode, the validator emits a `WARN` saying overlay validation was skipped.

### How skills consume config

Each skill that depends on config reads it explicitly. The pattern is:

1. Read config via the central scripts. `get-config-value.sh <block> <key>` returns a single scalar; `discover-context.sh` returns the bulk of paths as JSON. Both scripts honor `config-local.yml` overlay automatically. Skills that need list-typed or multi-line values should overlay manually if they parse the YAML themselves.
2. Use the value verbatim. There is **no auto-fallback** to other locations — if a key is null or absent in both files, that's the answer.
3. If `.sublime-skills/config.yml` is missing entirely or fails `validate-config.sh`, the project hasn't been bootstrapped for SDD; the user should run `ss-bs-bootstrapping-project` first.

The coordinator caches the config once at session start (after Stage 0 preflight returns ready) and passes relevant values into each skill dispatch.

### Common overrides

**Custom branch naming pattern:**

```yaml
branching:
  branch_pattern: "feature/{short-name}"
```

Used by `ss-sdd-choosing-feature-branch` (Stage 7) when suggesting a feature branch name. Bug-fix runs (when `state.work_type == "fix"`) swap `feat/` to `fix/` automatically.

**Memory file maintenance (CLAUDE.md / AGENTS.md / etc.):**

```yaml
memory_file:
  path: "CLAUDE.md"        # or AGENTS.md, GEMINI.md, .agents.md, or absolute path
  character_limit: 40000   # widely-recommended soft cap for agent memory files
```

`path: null` auto-detects at repo root (CLAUDE.md → AGENTS.md → GEMINI.md → .agents.md). If nothing matches, Stage 10 auto-skips without prompting. When a path IS resolved, the coordinator prompts `yes/no` per run — answer `no` if this particular run doesn't deserve attention. Most runs result in "no update needed" anyway.

**Custom context file locations:**

```yaml
context:
  constitution_path: docs/principles.md
  architecture_path: docs/internal/ARCH.md
  glossary_path: null               # this project doesn't have one
  design_path: null                 # CLI tool — no UI surface
```

Each key is a single explicit path or `null`. The SDD pipeline expects a single canonical pointer per artifact, not a list. If your project keeps a convention file at a non-default path (e.g., `docs/internal/ARCH.md`), point the corresponding `<name>_path` at it. `design_path: null` is the right choice for CLI tools, libraries, or backend services with no visual UI surface — the bootstrapper's `ss-bs-discovering-design` skill detects the absence of a UI surface during its code scan and surfaces Skip as the recommended option for such projects.

### Hard ceilings (not overridable)

A few values have hard ceilings that override config:

| Setting | Config | Hard ceiling |
|---|---|---|
| Test fix-loop iterations | 3 (fixed) | — |
| Spec/plan review fix iterations | 2 (fixed) | — |

Iteration caps are deliberately not config-overridable. Hitting a cap means something is wrong with the plan or spec, and the user should be involved.

### What's NOT in config

The following are deliberately not config:

- Per-skill behaviors (each skill has its own internal rules; if you want to change them, edit the skill)
- The list of allowed `[NO-TDD]` categories (defined in `ss-sdd-writing-plans` skill; changing them requires a skill edit)
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
    "plan_written"
  ],
  "stages_skipped": [],
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
  "reviewer_pushbacks": [],
  "spec_auto_review_iterations": 1
}
```

**What `ss-sdd-implementing-plans` does on this state when it iterates:**

1. The skill reads `state.tasks` and sees T001-T003 `completed`, T004 `in_progress`, T005-T007 `pending`.
2. T004 was the task whose implementer subagent died before reporting completion. The skill re-dispatches T004 from the start with a fresh implementer subagent (per-task isolation makes this safe — partial work is either committed or lost).
3. On T004 completion, the skill marks it `completed` in state and continues to T005 in plan order.

The `tasks` map is the contract between the skill and the per-task subagents — that's how the next task gets picked up after each subagent dies.

---

## Validating state file integrity

The state file is the contract between the coordinator and its subagents — if it's malformed, the coordinator can't reliably hand work to the next subagent. The schema in `framework/state-schema.md` / `state-schema.json` defines what valid means: required fields present, enum values from the documented sets, stage progression consistent (e.g., `current_stage: "implementing"` implies `plan_approved` is in `stages_completed`).

In practice, malformed state is rare — every writer uses the atomic `.tmp → mv` pattern, so a half-written file never replaces the previous good one. If it does happen (the user hand-edited the file, or some external tool corrupted it), the coordinator surfaces the issue to the user rather than guessing. Repair is the user's call, not the coordinator's.
