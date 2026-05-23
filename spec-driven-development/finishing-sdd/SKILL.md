---
name: finishing-sdd
description: Use during the finishing stage of an SDD pipeline run (Stage 17), after implementation (and any optional testing, handoff, and memory-file stages) are complete. Validates the state file, prints a summary report of what the pipeline produced, then deletes the state file via plain `rm` (no commit — the file is gitignored). V1 explicitly does NOT manage branches or merges — the user decides what to do with the feature branch.
---

# Finishing SDD

## Overview

Close out an SDD run. This is bookkeeping, not source-control management:

1. Read and validate the state file — confirm implementation actually completed.
2. Print a summary report of what the pipeline produced.
3. Delete `.sublime-skills/state.json` via plain `rm` (no commit — the file is gitignored throughout the pipeline).

That's it. No merging, no pull requests, no branch deletion, no test re-runs. Those are explicitly out of scope for V1 — the user decides what to do with the feature branch after SDD hands control back.

**Core principle:** SDD's responsibility ends at "implementation complete." Source control belongs to the user.

**Announce at start:** "I'm using the finishing-sdd skill to wrap up this SDD run."

## Hard Gates

- Do NOT proceed if `state.stages_completed` doesn't contain `implementation_complete`
- Do NOT proceed if the state file is malformed or unreadable
- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.

## Checklist

1. Validate state file
2. Print summary report
3. Delete state.json (plain `rm`, no commit)

## Step 1: Validate State

Read `.sublime-skills/state.json`. Confirm:

- The file parses as JSON.
- `stages_completed` is an array containing `implementation_complete`.

If either check fails: surface the issue and halt. Common reasons: malformed JSON (rare), or the user invoked finishing prematurely (before implementation finished).

Additionally, check `test_status`:

- If `test_status` is `passed` or `passed_after_fixes`: fine, proceed.
- If `test_status` is `skipped_user_choice` or `skipped_mcp_unavailable`: fine, proceed (the user knew testing was skipped).
- If `test_status` is `failed_escalated` OR `null` (when `testing` isn't in `stages_skipped`): prompt the user via the harness's interactive question tool: "Tests aren't in a passing state (`<test_status>`). Finish anyway?" Only proceed on explicit yes.

**No test re-run.** Stage 14 (feature testing) was the test gate; if it ran and passed, we trust the result. If it was skipped, the user already made that call.

## Step 2: Print Summary Report

Print a structured block to the user. Pull values from `state.json`:

```
SDD run complete: <feature_id>

  Short name:        <short_name>
  Started:           <started_at>
  Updated:           <updated_at>
  Branch:            <git branch --show-current>

  Artifacts:
    Spec:            <spec_path>
    Plan:            <plan_path or "(none)">
    Handoff:         <handoff_path or "(skipped)">
    Memory file:     <memory_file_path if memory_file_updated else "(no update)">

  ADRs created:      <count from adr_results>
    <list of ADR-NNNN — title for each>

  Tasks:             <N completed> / <N total> (from `tasks` map)
  Test status:       <test_status>
  Memory file updated: <memory_file_updated>

  Stages completed:  <count of stages_completed>
  Stages skipped:    <list from stages_skipped>
```

This is informational — the user reads it and now knows what the pipeline did. The artifacts (spec.md, plan.md, ADRs, handoff doc, memory file) are all already committed; this report just summarizes their existence.

## Step 3: Delete State File

State is gitignored and untracked — use plain `rm`, NOT `git rm`:

```bash
rm .sublime-skills/state.json
```

No commit follows. The SDD run is complete; the spec / plan / ADRs committed across Stages 12-16 ARE the output.

**If `git rm` is tempting: don't.** It would fail with "did not match any files" because the file is not tracked. Do NOT fall back to `git rm -f` or `git rm --cached` — there is nothing to untrack.

### If the state file is already deleted

If `.sublime-skills/state.json` doesn't exist when this step runs (rare — e.g., the user removed it manually mid-failure):

```bash
[ -f .sublime-skills/state.json ] && rm .sublime-skills/state.json || true
```

Report "state file already removed; nothing to do."

After deletion: SDD run is done. The user now decides what to do with the feature branch — merge it, open a PR, leave it for later. That's their call.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Re-running the test suite | NEVER — Stage 14 (feature testing) was the test gate. |
| Asking the user whether to delete the state file | NEVER — state.json is tool metadata; the user doesn't curate it. Just `rm` it; no commit. |
| Trying to merge, push, create a PR, or delete the branch | NEVER — V1 doesn't manage source control. The user does that after SDD ends. |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |
| Using `git rm` instead of plain `rm` for the state deletion | NEVER. The file is untracked; `git rm` would fail. Use plain `rm`. |

## Red Flags

- About to run `git merge`, `git push`, `gh pr create`, `git branch -d`, or any branch/remote operation → STOP; out of scope for V1
- About to re-run the test suite → STOP; not this skill's job in V1
- About to skip the `implementation_complete` check → STOP; the gate is non-negotiable
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP
- About to `git rm` state.json → STOP; it's untracked, use plain `rm`
