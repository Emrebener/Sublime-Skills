---
name: inspecting-state
description: Use to read and report SDD state without modifying anything — invoked by the coordinator at session start (resume detection) and by the user directly to check status of in-progress SDD runs.
---

# Inspecting State

## Overview

Read-only utility that locates all SDD state files in the repo, validates each one's schema, and reports what's there. The coordinator uses this as its first action on every invocation; the user can invoke it directly to check status without entering the pipeline.

**Core principle:** Inspection is observation, not decision. This skill reports facts; the coordinator (or user) decides what to do with the report.

**Operating mode:** STRICTLY READ-ONLY. Does not modify any file, dispatch any subagent, or invoke any other skill.

**Announce at start:** "I'm using the inspecting-state skill to check current SDD state."

## Hard Gates

- Do NOT modify any file (no atomic-write attempts; no state recovery)
- Do NOT dispatch subagents
- Do NOT make decisions ("resume" vs "fresh start") — only report what's there
- Do NOT invoke other skills

## Checklist

1. Run the discovery script to find active state files
2. Read each found state file
3. Validate each against the schema
4. Check git for branch signals that hint at pre-state-file interruption
5. Produce the report

## Step 1: Discover State Files

```bash
./spec-driven-development/scripts/discover-context.sh
```

The output's `active_states` array lists every `docs/specs/*/state.json` path in the repo. There may be:
- **0** — no in-progress SDD runs (but check git for pre-state-file interruption signals)
- **1** — single in-progress run, usual case
- **2+** — multiple in-progress runs; usually because a prior run was paused mid-pipeline

## Step 2: Read Each State File

For each state path:
1. Read the JSON
2. If unparseable: mark `malformed: true` with the parse error
3. If parseable: extract key fields (see Report Format)

## Step 3: Validate Each Against Schema

The canonical schema is `spec-driven-development/scripts/state-schema.md` (human-readable) and `state-schema.json` (machine-readable). Validate each state file against that schema — these are the single source of truth, not a local copy.

**Required fields:** `feature_id`, `short_name`, `started_at`, `updated_at`, `branch`, `spec_path`, `current_stage`, `stages_completed`, `stages_skipped`, `preflight` (with `original_branch`), `tasks`.

**Optional fields, present after specific stages advance:** `plan_path` (after Stage 8), `adr_results` (after Stage 6, may be `[]`), `test_status` and `fix_iterations` (after Stage 13), `final_review_completed` (after Stage 12 final review), `handoff_path` (after Stage 14), `memory_file_updated` and `memory_file_path` (after Stage 15), `reviewer_pushbacks` (any stage; `[]` initial), `spec_auto_review_iterations` and `plan_auto_review_iterations` (after the relevant review stages).

**Validation checks to perform:**

1. **JSON parseable** — if not, mark `malformed: true` with the parse error
2. **Required fields present** — list any missing
3. **Enum values valid** — `current_stage` must be in the Stage Name Mapping; each `stages_completed` entry must be in the allowed set; each `tasks.T###` value must be `pending|in_progress|completed`; `test_status` must be in the documented set or `null`
4. **Internal consistency** — `tasks` non-empty but `plan_path` is null is inconsistent (plan should precede implementation); `current_stage: implementing` but `stages_completed` doesn't include `plan_approved` is inconsistent; `handoff_path` non-null but `handoff` not in `stages_completed` is inconsistent

For each state file, mark validation issues:
- `missing_required_fields: [...]`
- `invalid_enum_values: [...]` (field name → bad value)
- `unexpected_state: "<description>"` — e.g., `tasks` is non-empty but `plan_path` is null

If a JSON Schema validator is available in the environment (e.g., `ajv`, `python -m jsonschema`), running it against `state-schema.json` catches structural issues for free. The skill does NOT require a specific validator — manual checks against the schema document are also valid.

## Step 4: Check Pre-State Git Signals

Even if no state files exist, the user may have been interrupted between preflight and Stage 2 (writing-specs). Check this signal — but tightly, to avoid false positives on every non-default branch.

```bash
git branch --show-current               # current branch
```

Flag "possible pre-state interruption" ONLY when ALL of these are true:

1. **No active state files exist** — `active_states` is empty. If any state file exists anywhere in the repo, the user has in-flight work tracked elsewhere; the current branch being non-default is not a pre-state signal.
2. **Current branch matches an SDD branch pattern** — default patterns: `feat/*` (matches `feat/<short-name>`) or `fix/*` (matches `fix/<short-name>`). Branches like `chore/cleanup`, `wip/scratch`, `experiment/foo`, `dependabot/...` do NOT match and should NOT trigger this signal.
3. **Branch is not the default, develop, or a release/hotfix branch** — explicitly excludes `main`, `master`, `develop`, `release/*`, `hotfix/*`.

If all three are true, include "possible pre-state interruption" in the report. Otherwise, do not — the user is on an unrelated branch and the coordinator should treat the state as "no active runs."

If the user has a custom `preflight.branch_pattern` in `.sublime-skills/config.yml` that doesn't match the `feat/*` or `fix/*` shape, this detection may miss their interruption — that's acceptable; the coordinator's interactive prompts catch the case at confirmation time. False positives are worse than false negatives here.

## Step 5: Produce Report

Output format:

```markdown
## SDD State Report

**Active runs found:** <N>
**Pre-state interruption suspected:** yes | no
**Current branch:** <branch>

### Run 1: <feature_id>

- **Path:** docs/specs/<feature_id>/state.json
- **Short name:** <short-name>
- **Started:** <ISO-8601>
- **Last updated:** <ISO-8601>
- **Branch:** <state.branch>
- **Branch match with current:** yes | no (state.branch == current branch?)
- **Current stage:** <current_stage>
- **Stages completed:** <list, summarized to last 3 if long>
- **Stages skipped:** <list>
- **Tasks:** <N completed> / <N in_progress> / <N pending> (omit if empty)
- **Test status:** <test_status or "n/a">
- **ADRs created in this run:** <count>
- **Validation:** ok | issues: <list of issues>

### Run 2: (if any)

(same shape)

### Pre-State Interruption Signals (if applicable)

- On branch `<branch>` (non-default), no matching state file
- Likely interrupted between Stage 0 (preflight) and Stage 2 (writing-specs)

### Summary

<One sentence: what the coordinator (or user) should do next. Examples:
- "No active runs; safe to start fresh."
- "One active run for `003-user-auth` at stage `implementing` (3/8 tasks done), branch matches current — resume by re-invoking coordinator."
- "One active run for `003-user-auth` on branch `feat/user-auth`, but current branch is `chore/cleanup` — coordinator should ask user how to route (no auto-resume)."
- "Two active runs found; coordinator should ask user which to resume."
- "Pre-state interruption detected on branch `feat/user-auth`; coordinator should offer to resume from discovery or start fresh."
- "State file for `003-user-auth` is malformed (missing `feature_id`); coordinator should ask user how to proceed.">
```

## How the Coordinator Uses This

At session start, the coordinator's very first action is to load this skill and run it. The coordinator does NOT decide anything; it reads the report and acts on it per its own resume protocol:

- **0 active runs + no pre-state signals** → fresh start
- **0 active runs + pre-state signals** → ask user about resume vs fresh
- **1 active run + valid state** → confirm resume with user, then proceed
- **2+ active runs** → ask user which to resume
- **Malformed state** → show user the issues, ask how to proceed

This skill produces the facts; the coordinator interprets.

## How a User Uses This Directly

A user can invoke this skill at any time to see current SDD state without entering the pipeline:

> "Use the inspecting-state skill to show me what SDD runs are in progress."

The skill produces the same report. No side effects.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Modifying a state file as part of "inspection" | Inspection is read-only; never write |
| Deciding "resume" or "fresh start" — telling the coordinator what to do | Report facts; coordinator decides |
| Dispatching subagents to read related files | Leaf skill; no dispatch |
| Skipping validation because the JSON parsed | Schema validation matters; report missing/unexpected fields |
| Ignoring pre-state interruption signals | They're the harder case to detect; specifically check git for them |
| Reporting in a free-form format | Use the structured Report Format; the coordinator parses it |

## Red Flags

- About to write to a state file → STOP; you are read-only
- About to dispatch a subagent → STOP; leaf skill
- About to ask the user a question → STOP; just produce the report
- About to invoke `writing-specs` or any other skill to "fix" a malformed state → STOP; report only
