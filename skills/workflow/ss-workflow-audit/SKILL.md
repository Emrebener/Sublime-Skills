---
name: ss-workflow-audit
description: Use when the user wants to verify their project is ready to use the Sublime-Skills framework — checks the install (env var, on-disk integrity, required tooling), the project bootstrap state (config file present, validates, gitignore entries, SDD artifact dirs), each declared convention/context file (constitution, architecture, glossary, domain, design), the memory file, and optional tooling, then emits a per-section status table and an overall READY / READY-WITH-WARNINGS / NOT READY verdict. Read-only — never modifies any file.
---

# Audit

## Overview

Run a battery of read-only checks that answer one question: "Is this project ready to use the Sublime-Skills framework?" Each check is reported with a status (`PASS` / `FAIL` / `WARN` / `INFO` / `N/A`) and a short detail line. At the end, print an overall verdict plus a concrete next-step list when anything is wrong.

**Operating mode:** Read-only. No edits, no commits, no script invocations that mutate state. Safe to run repeatedly.

**Announce at start:** "I'm using the ss-workflow-audit skill to check whether this project is ready for Sublime-Skills."

## Hard Gates

- This skill MUST NOT modify any file. No `mkdir`, no `touch`, no `git add`, no `cp`. Only reads, greps, and stat-style checks.
- Do NOT attempt to fix anything inline. The output is a report; remediation is the user's call (or another skill's job).
- Do NOT dispatch subagents. Run the checks inline and produce the report.
- Do NOT skip checks because earlier ones failed. Run them all and report what you found — the user wants the full picture, not the first failure.

## Status Vocabulary

| Status | Meaning |
|---|---|
| `PASS` | Check passed. Required-thing-is-present, optional-thing-is-present, or "all good." |
| `FAIL` | Essential check failed. The framework (or a major part of it) cannot run until this is fixed. |
| `WARN` | Non-essential check failed, OR a state was detected that probably isn't intentional (orphan files, missing recommendations). Framework still works. |
| `INFO` | Informational observation, no value judgment. Detected feature, version, optional thing present. |
| `N/A` | The thing being checked is explicitly disabled by config (e.g., context path is `null`). Not a failure. |

## Checklist

Run each section in order. Capture every result; do not abort early.

1. Environment (install + tooling)
2. Git repo state
3. Project bootstrap state
4. SDD artifact directories
5. Convention/context files
6. Memory file
7. Optional tooling
8. Compose the report (per-section tables + overall verdict)

## Section 1 — Environment

| Check | How to run | Status logic |
|---|---|---|
| `$SUBLIME_SKILLS_HOME` is set | `[ -n "$SUBLIME_SKILLS_HOME" ]` | PASS if set; FAIL otherwise. Detail: the value, or `unset` |
| `$SUBLIME_SKILLS_HOME` points at a real directory | `[ -d "$SUBLIME_SKILLS_HOME" ]` | PASS if directory; FAIL otherwise. Skip if previous check failed. |
| Install looks like Sublime-Skills | `[ -d "$SUBLIME_SKILLS_HOME/skills" ] && [ -d "$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework" ]` | PASS if both dirs exist; FAIL otherwise. Skip if previous check failed. |
| `git` available | `command -v git` | PASS / FAIL |
| `python3` available | `command -v python3` | PASS if found; WARN if missing (`validate-config.sh` has an awk fallback but it's shallower) |
| `python3` + `PyYAML` available | `python3 -c "import yaml" 2>/dev/null` | PASS if it succeeds; WARN if it fails (config validator falls back to awk and skips overlay validation) |

## Section 2 — Git Repo State

Use `git rev-parse --show-toplevel 2>/dev/null` as the gate; if it fails, the cwd is not in a git repo.

| Check | How to run | Status logic |
|---|---|---|
| Inside a git repo | `git rev-parse --git-dir >/dev/null 2>&1` | PASS if exits zero; FAIL otherwise. If FAIL, mark the remaining git/project checks `N/A` with detail "not in a git repo" and continue. |
| Repo root | `git rev-parse --show-toplevel` | INFO — the path |
| Current branch | `git branch --show-current` | PASS if non-empty (named branch); WARN if empty (detached HEAD — most SDD stages need a branch). Detail: the branch name or `(detached HEAD)` |
| Working tree clean | `git status --porcelain` | PASS if no output; INFO with `<N> uncommitted change(s)` otherwise. Dirty tree does not block the framework. |

## Section 3 — Project Bootstrap State

All paths are repo-rooted via `git rev-parse --show-toplevel`. If not in a git repo, mark this entire section `N/A`.

| Check | How to run | Status logic |
|---|---|---|
| `.sublime-skills/` directory | `[ -d .sublime-skills ]` | PASS / FAIL. FAIL means bootstrap has not been run — surface "run `ss-bs-bootstrapping-project`" in remediation. |
| `.sublime-skills/config.yml` exists | `[ -f .sublime-skills/config.yml ]` | PASS / FAIL |
| Config validates | Run `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-config.sh"` (capture stdout + stderr + exit code) | PASS on exit 0; FAIL on exit 1 or 2. Detail: paste the validator's summary line, and include up to the first 5 `FAIL:` lines from stderr in the report. Skip this check if `$SUBLIME_SKILLS_HOME` or config.yml are missing — mark `N/A` with detail explaining why. |
| `.sublime-skills/config-local.yml` (optional overlay) | `[ -f .sublime-skills/config-local.yml ]` | INFO — present (overlay active) or absent (no per-developer overrides). Either is fine. |
| `.sublime-skills/.gitignore` exists | `[ -f .sublime-skills/.gitignore ]` | PASS / FAIL. Bootstrap creates it. |
| Gitignore covers `state.json` | `grep -qxE 'state\.json' .sublime-skills/.gitignore` | PASS if the line is present; FAIL otherwise. This is the gitignore entry that keeps SDD's per-run state file out of git. |
| Gitignore covers `config-local.yml` | `grep -qxE 'config-local\.yml' .sublime-skills/.gitignore` | PASS if present; WARN if missing (per-developer overlay would otherwise be committed). |
| Stale `state.json` present | `[ -f .sublime-skills/state.json ]` | INFO if present (orphan from a previous SDD pipeline; preflight will clean it up next run); silent if absent. |

## Section 4 — SDD Artifact Directories

Skip if not in a git repo.

| Check | How to run | Status logic |
|---|---|---|
| `docs/specs/` exists | `[ -d docs/specs ]` | PASS / FAIL. Created by bootstrap. |
| `docs/adr/` exists | `[ -d docs/adr ]` | PASS / FAIL. Created by bootstrap. |
| `docs/specs/README.md` exists | `[ -f docs/specs/README.md ]` | INFO — bootstrap creates a stub. Absence is harmless but worth noting. |
| `docs/adr/README.md` exists | `[ -f docs/adr/README.md ]` | INFO — same as above. |

## Section 5 — Convention / Context Files

For each of the five context keys (`constitution_path`, `architecture_path`, `glossary_path`, `domain_path`, `design_path`):

1. Read the value via `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/get-config-value.sh" context <key> .sublime-skills/config.yml`
2. Classify:
   - Empty output / `null` / `~` → `N/A` with detail "not configured (this project doesn't have one)"
   - Non-null + file exists at the path (resolved relative to repo root if not absolute) → `PASS` with detail showing the path
   - Non-null + file does not exist → `FAIL` with detail "orphan path: `<path>` does not exist" (validate-config.sh also catches this — duplicate is intentional so the audit table reads on its own)

If `$SUBLIME_SKILLS_HOME` is unset or config.yml is missing, mark this entire section `N/A` with one shared detail line ("config not loaded — see Section 3").

All five are optional individually, but if every one of them is `N/A`, add a single WARN row at the bottom of the section: "no convention files configured at all — consider running `ss-bs-bootstrapping-project` to capture project conventions."

## Section 6 — Memory File

The memory file is what SDD's Stage 16 (`ss-sdd-maintaining-memory-file`) writes to. It's optional — Stage 16 is skipped if no memory file is found.

1. Read `memory_file.path` from config (same script as Section 5)
2. If a non-null path is set:
   - File exists → `PASS` with detail showing the path
   - File doesn't exist → `FAIL` with detail "config-pinned memory file does not exist: `<path>`"
3. If `null` (auto-detect mode), check repo root in this order: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.agents.md`. First match → `PASS` with detail showing which one was found. None match → `WARN` with detail "no memory file found — Stage 16 will be skipped automatically."

Also read `memory_file.character_limit` and surface it as `INFO` (e.g., `character_limit: 40000`). Helps the user spot accidental overrides.

## Section 7 — Optional Tooling

| Check | Reason | Status logic |
|---|---|---|
| `gh` (GitHub CLI) | Required by the `ss-agile-*` skill family | INFO — present or absent. Not a failure either way unless the user is asking about agile readiness specifically. |

If the user's invocation mentioned a specific skill family (e.g., "audit for agile"), promote the relevant rows from INFO to FAIL when missing. By default, treat all of Section 7 as informational.

## Composing the Report

Produce one markdown response that contains:

1. A short one-line preamble: where the audit ran (`Repo: <repo-root>` or `(not in a git repo)`).
2. One table per section, in order, using this layout:

   ```markdown
   ### Section <N> — <title>

   | Check | Status | Detail |
   |---|---|---|
   | <name> | `PASS` | <detail> |
   | <name> | `FAIL` | <detail> |
   ```

   Wrap each status in backticks so the column reads cleanly. Keep the detail concise — one line, no wrapping. If a check produced an error message worth preserving (e.g., validator stderr), put it in a fenced block *below* the table, not in the cell.

3. The **Overall verdict** as the final section, one of:

   - **`READY`** — every essential check is `PASS` (any number of `INFO` / `N/A` rows is fine).
   - **`READY-WITH-WARNINGS`** — every essential check is `PASS`, but at least one `WARN` row exists. Framework works; some things are likely worth fixing.
   - **`NOT READY`** — at least one `FAIL` row in any section. Name the blockers and the recommended remediation.

   The "essential" checks for verdict purposes:

   - Section 1: env-var set, install integrity, git available
   - Section 2: in a git repo
   - Section 3: config.yml exists, config validates, gitignore covers `state.json`
   - Section 5 and 6 `FAIL` rows (orphan-path / orphan-pinned-memory) — these are config integrity issues
   - Section 4 only matters for SDD; `FAIL` rows there bump the verdict to `READY-WITH-WARNINGS`, not `NOT READY`, unless the user asked specifically about SDD readiness.

4. If the verdict is `READY-WITH-WARNINGS` or `NOT READY`, end with a short bulleted **Next steps** list — one bullet per actionable item, naming the skill or command that fixes it:

   - "Set `SUBLIME_SKILLS_HOME` — see `docs/SETUP.md` in the Sublime-Skills repo."
   - "Run `ss-bs-bootstrapping-project` to scaffold `.sublime-skills/config.yml` and the docs directories."
   - "Edit `.sublime-skills/config.yml`: `context.architecture_path` points to a file that doesn't exist."
   - "Create a memory file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, or `.agents.md`) at the repo root if you want Stage 16 to run."

Keep the entire report tight. The whole thing should fit on one screen for a healthy project.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Auto-fixing something during the audit ("the gitignore was missing so I created it") | Forbidden. Report only. The user runs the remediation. |
| Bailing on first FAIL | Run every section. The user wants the full picture. |
| Marking optional things as FAIL | Convention files / memory file / `gh` are all optional. Use `N/A`, `WARN`, or `INFO` instead. |
| Pasting validator's full stderr into the table cell | Put the first few `FAIL:` lines in a fenced block below the table, not in a cell. Cells are one line. |
| Reading config.yml manually with grep/sed | Use `get-config-value.sh` — that's the single source of truth for layered config reads (config-local.yml overlay semantics). |
| Forgetting to skip checks gracefully when prerequisites are missing | If `$SUBLIME_SKILLS_HOME` is unset, don't try to invoke `validate-config.sh`; mark dependent checks `N/A` with a brief explanation. |
| Inventing checks not listed here | The skill defines the contract. If new things become essential, edit this SKILL.md, don't add ad-hoc checks at runtime. |

## Red Flags

- About to run `mkdir`, `touch`, `cp`, `git add`, or any edit during the audit → STOP. Read-only.
- About to dispatch a subagent to "investigate" a failure → STOP. The audit reports; it doesn't diagnose deeper.
- About to ask the user a clarifying question before running checks → STOP. The checks are deterministic; just run them and report.
- About to claim "ready" when an essential check failed → STOP. Re-read the verdict rules above.
