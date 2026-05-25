---
name: ss-bs-auditing-project
description: Use to re-evaluate an already-bootstrapped project for drift, incoherence, and improvement opportunities. Sibling to ss-bs-bootstrapping-project — re-uses the same per-file discovery skills via MODE=audit with SUGGEST=on always. Leads with the cross-artifact coherence check; commits stage-by-stage so the user can accept some changes and decline others. Run cases: quarterly project health checks, post-refactor sweeps, new-contributor onboarding prep, ad-hoc "this doc feels stale" investigations.
---

# Auditing Project

## Overview

You are the coordinator for project audit. You re-evaluate an already-bootstrapped project — drift, incoherence, improvement opportunities. The per-file discovery skills (the seven `ss-bs-discovering-<topic>` skills) are loaded inline in audit mode; you don't reach inside their work, you route to them.

**Audit ≠ bootstrap re-run.** Bootstrap re-run with SUGGEST=on adds missing entries and surfaces suggestions, but doesn't compare the existing artifact against current code state. Audit does — that's the drift check (Step 1.6 per discovery skill). Audit also commits stage-by-stage, so the user can accept some changes and decline others.

**Sibling relationship:** This skill mirrors `ss-bs-bootstrapping-project`'s structure (Hard Gates, Checklist, Step-by-step, Common Mistakes, Red Flags) but diverges in three fundamental ways: coherence runs FIRST (drives the per-stage loop, not just a gate before commit), SUGGEST is always on (no opt-out), and commits are per-stage rather than bundled. The bootstrap coordinator handles first-time setup, config copy, and directory creation; this skill assumes all of that is already done.

**Announce at start:** "I'm using the ss-bs-auditing-project skill to audit your bootstrap artifacts for drift and opportunities."

## What This Skill Doesn't Do

- It does NOT bootstrap a project that has no artifacts yet. That's `ss-bs-bootstrapping-project`. Audit's preflight verifies config + ≥1 artifact and redirects if missing.
- It does NOT auto-fix problems in the codebase. Audit suggests changes to documentation; humans make code changes.
- It does NOT bundle commits. Each audited stage is its own commit so the user can accept selectively.
- It does NOT persist a report file. Findings and summary are conversation-only.
- It does NOT maintain multiple memory files (same constraint as bootstrap — one per project).

## Hard Gates

- Do NOT run on an un-bootstrapped project. Preflight (Step 1) hard-gates this.
- Do NOT skip Step 2 (cross-artifact coherence). It runs FIRST and drives the per-stage loop's prioritization — coherence is not a trailing gate here, it is the input to step selection.
- Do NOT bundle audit changes into one commit. Each stage gets its own commit so the user can accept selectively.
- Do NOT persist the audit report to a file. Conversation-only.
- Do NOT dispatch any discovery skill as a subagent. All seven are loaded inline (same constraint as bootstrap).
- Do NOT run audit on every stage by default. Step 3 asks the user which stages to revisit; respect the choice.
- ALWAYS surface coherence findings VERBATIM. Do not summarize, paraphrase, or restructure them — the script's canonical format is what the user sees.
- ALWAYS pass `SUGGEST=on` to every discovery skill invocation (audit's prescriptive-by-default rule; there is no opt-out).
- ALWAYS use the harness's interactive question tool for Step 3 (scope picker) and per-stage user prompts. Do NOT fall back to plain-text prompts.
- ALWAYS use the harness's todo/task tool. Build the audit todo list right after Step 2's coherence pass — one todo per chosen stage + final coherence re-check + summary report. Mark each `in_progress` when you start it and `completed` the instant it's done.

## Checklist

1. Preflight (verify config + ≥1 artifact; redirect to bootstrap if missing)
2. Cross-artifact coherence pass (Tier 1 — runs FIRST, drives the loop)
3. User picks scope (one of: prioritized fix / user-picks / full audit / report-only)
4. Build the audit todo list (one item per chosen stage + final coherence re-check + summary)
5. Per-stage audit loop: for each picked stage, load discovering-X with `MODE=audit, SUGGEST=on`; commit immediately on stage completion
6. Final coherence re-check
7. Summary report (conversation-only)

## Step 1: Preflight

### 1a. Verify config exists and validates

```bash
test -f .sublime-skills/config.yml || {
  echo "No bootstrap config at .sublime-skills/config.yml — this project hasn't been bootstrapped."
  echo "Run ss-bs-bootstrapping-project first."
  exit 1
}
"${SUBLIME_SKILLS_HOME:?SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup}"/skills/spec-driven-development/framework/validate-config.sh
```

If config is missing → halt; redirect user to `ss-bs-bootstrapping-project`. Do NOT auto-invoke bootstrap from here (that would surprise the user — confirm interactively first).

If validate-config fails → halt; surface the findings verbatim; suggest `ss-bs-bootstrapping-project` re-run to fix config issues. Audit cannot proceed against an invalid config.

### 1b. Verify at least one artifact exists

Run:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/discover-context.sh"
```

Parse the JSON output. Check that at least one of the 7 paths resolves to an existing file (the 6 context artifact paths plus the `memory_file.path`).

If 0 artifacts exist, ask:

```
Question: "Config exists but no artifacts have been created yet. Audit needs at least
one artifact to evaluate. Options:"

  - "Run bootstrap instead (recommended)"
  - "Continue anyway — I'll skip stages with no artifact"
```

On "Run bootstrap instead" → halt; surface the recommendation to the user and exit.
On "Continue anyway" → proceed; the per-stage loop (Step 5) will skip stages whose artifact doesn't exist.

## Step 2: Cross-Artifact Coherence Pass

Run the coherence checker:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/coherence-check.sh"
```

The exit codes and their meanings:

| Exit code | Meaning | Action |
|---|---|---|
| `0` | No findings | Surface "Coherence check: PASS (0 findings)." Continue to Step 3 — user may still want a per-stage audit even with clean coherence. |
| `1` | Findings present | Surface ALL findings VERBATIM (do not summarize). The findings drive Step 3's prioritized-fix option. |
| `2` | Config not found | Halt; surface; this shouldn't happen — preflight just verified it. |
| `3` | Usage error | Halt; surface as coordinator bug. |
| `4` | Internal error | Halt; surface; ask user to ensure python3 is available. |

When findings are present, group them by which discovery skill would fix them (read from each finding's `fix:` line). This grouping informs the prioritized-fix ordering in Step 3 — stages with CRITICAL findings cluster first, then WARNING, then INFO.

## Step 3: User Picks Scope

After surfacing the coherence findings (or the PASS message), ask:

```
Question: "How would you like to proceed?"

Options:
  - "Fix the top N coherence findings stage-by-stage (Recommended)" — auto-orders
    by where findings cluster; covers the stages with the most CRITICAL/WARNING
    findings first
  - "I'll pick which stages to revisit" — multi-select from the 7 stages
  - "Run a full audit on every stage" — invoke all 7 in audit mode
  - "Skip — I just wanted the coherence report" — exit with the findings as the report
```

Record the chosen stages list. If "Skip", jump to Step 7 (summary report) immediately.

**For "Fix the top N coherence findings":**
- If 0 coherence findings, fall back automatically to "I'll pick" (there is nothing to prioritize). Inform the user of the fallback.
- Otherwise, derive the prioritized list: stages whose findings include ≥1 CRITICAL first, then stages with WARNING only, then stages with INFO only.

**For "I'll pick which stages to revisit":**

```
Question: "Which stages would you like to audit?"

Multi-select from:
  - Constitution (docs/constitution.md)
  - Architecture (docs/ARCHITECTURE.md)
  - Testing (docs/TESTING.md)
  - Glossary (docs/GLOSSARY.md)
  - Domain model (docs/DOMAIN.md)
  - Design (docs/DESIGN.md)
  - Memory file (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md)

(Pre-check stages with coherence findings as a visual hint.)
```

**For "Run a full audit on every stage":**
Order is the same as bootstrap: constitution → architecture → testing → glossary → domain → design → memory file. Skip stages whose artifact doesn't exist (noting the skip in the summary).

## Step 4: Build the Audit Todo List

Using the harness's todo/task tool, create one todo per chosen stage plus two trailing todos:

1. \<Stage 1 from Step 3's chosen list\>
2. \<Stage 2\>
... (one per additional chosen stage) ...
N. Final coherence re-check
N+1. Summary report

Mark each todo `in_progress` when you start it and `completed` the instant it is done. Never batch updates — the user reads this list to follow along.

## Step 5: Per-Stage Audit Loop

For each stage in the chosen list, in priority order:

### 5a. Load the discovering-X skill in audit mode

Load the matching skill inline (via the harness's skill mechanism). Pass these inputs:

```
Load skill: ss-bs-discovering-<topic>

REPO_ROOT:        <absolute path to repo root>
MODE:             audit
SUGGEST:          on    ← always on for audit, no exception
EXISTING_CONTENT: <verbatim current artifact content, read fresh from the config'd path>
FILE_PATH:        <config'd path for this artifact>
```

The mapping from stage to skill:

| Stage | Skill loaded (inline) |
|---|---|
| Constitution | `ss-bs-discovering-constitution` |
| Architecture | `ss-bs-discovering-architecture` |
| Testing | `ss-bs-discovering-testing` |
| Glossary | `ss-bs-discovering-glossary` |
| Domain model | `ss-bs-discovering-domain-model` |
| Design | `ss-bs-discovering-design` |
| Memory file | `ss-bs-discovering-memory-file` |

The skill runs its full audit flow — Step 1 (silent scan) + Step 1.5 (diagnose, always on) + Step 1.6 (drift check) + Step 2 (announce findings + drift + diagnoses) + Step 3 (Q0 drift resolution → Q1 observed → Q1.5 suggested → Q2-Q5 per skill) + Step 4 (synthesize draft) + Step 5 (refine, cap 3) + Step 6 (atomic write). You do NOT reach inside this flow.

### 5b. Skill returns one of these outcomes

- `audited (changes made)` — the artifact was updated; FILE_PATH points to the new content
- `audited (no changes)` — drift / diagnose / Q1 produced no updates; the file is byte-identical to before
- `skipped (declined mid-skill)` — user aborted within the skill

### 5c. Commit immediately on `audited (changes made)`

```bash
git add <FILE_PATH>
git commit -m "audit: update <basename of FILE_PATH> — <one-line summary of what changed>"
```

The one-line summary comes from the skill's report — e.g., "declare cross-service boundaries", "fix 2 drift items + 1 suggestion accepted", "update runner from Jest to Vitest". The commit message is the user's audit trail; make it informative, not generic.

Per-stage commits are mandatory even for small changes. Do NOT defer commits to the end of the loop.

### 5d. No commit on `audited (no changes)` or `skipped`

Record in the audit summary that the stage was reviewed (no changes) or declined. No commit is created for these outcomes.

### 5e. Move to the next todo

Mark the current stage todo `completed`; move to the next stage in the list.

## Step 6: Final Coherence Re-Check

Re-run:

```bash
"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/coherence-check.sh"
```

Compare findings to the Step 2 findings:

- Findings present in Step 2 but NOT in Step 6 — resolved by the audit stages.
- Findings present in both Step 2 and Step 6 — still outstanding (user declined the relevant stage, or the fix didn't address the issue).
- Findings new in Step 6 (not in Step 2) — introduced by audit changes (rare but possible if a newly-added pointer references a file that doesn't yet exist).

Surface the comparison to the user before composing the summary. Do not combine this step with Step 7 — run the check, then compose the report.

## Step 7: Summary Report (Conversation-Only)

Surface this block to the user verbatim after Step 6:

```
Audit complete.

Stages updated:
- <basename> — <drift items fixed: N, suggestions accepted: M> (committed: <short sha>)
- <basename> — ...

Stages reviewed, no changes:
- <basename> — no drift, 0 suggestions accepted

Stages declined:
- <basename> — user declined to revisit

Stages skipped (no artifact):
- <basename> — artifact doesn't exist; run bootstrap to create

Coherence check progression:
- Before audit: <N findings (X CRITICAL, Y WARNING, Z INFO)>
- After audit:  <N findings (X CRITICAL, Y WARNING, Z INFO)>
- Resolved:     <list of resolved finding titles, or "none">
- Outstanding:  <list of outstanding finding titles, or "none">
- New:          <list of newly-introduced finding titles, or "none">

Next steps:
- The bootstrap config is unchanged (audit doesn't touch config; re-run
  ss-bs-bootstrapping-project to address any config-level changes).
- Outstanding coherence findings can be addressed by running
  ss-bs-bootstrapping-project in re-run mode and selecting the relevant
  stages, OR by running ss-bs-auditing-project again on just those stages.
```

Do NOT persist this report. The user can copy from the conversation if they want a record. Do not create any new files at this step.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Running audit on an un-bootstrapped project | Preflight should hard-gate; if it doesn't, fix the preflight — never auto-fall-through to bootstrap |
| Summarizing coherence findings instead of surfacing verbatim | Always verbatim — the script's format is the canonical surface; do not paraphrase |
| Bundling per-stage changes into one commit | Each stage = one commit; user must be able to accept selectively |
| Passing SUGGEST=off in audit mode | Audit is prescriptive-by-default; always SUGGEST=on, no exception |
| Auto-invoking bootstrap when preflight fails | Halt and redirect interactively; don't surprise the user |
| Persisting the audit report to docs/.audit-report-*.md or similar | Conversation-only — no file lifecycle |
| Skipping a stage's commit because "the change feels small" | Commit anyway; even tiny changes belong in their own stage commit |
| Combining Step 6 (re-check) into Step 7 (report) | Run the coherence check first, then compose the report from its output |
| Using the coherence findings to decide scope without asking the user | Step 3 is always a user question; auto-deciding scope would bypass the user |

## Red Flags

- About to dispatch a discovering-X as a subagent → STOP; inline only
- About to write a per-stage commit message that doesn't describe what changed → STOP; the message is the user's audit trail
- About to skip a stage's commit because "the change feels small" → STOP; commit anyway, even tiny changes
- About to combine the coherence re-check into the summary report → STOP; they're separate; run the check before composing the summary
- About to bundle multiple stages' diffs into one commit → STOP; per-stage only
- About to pass SUGGEST=off to a discovering skill → STOP; audit is always SUGGEST=on
- About to reach inside a discovering skill's conversation or write flow → STOP; you route to the skill, the skill owns its own flow
- About to run coherence as the last step (like bootstrap) instead of first → STOP; in audit, coherence runs first and drives the scope
