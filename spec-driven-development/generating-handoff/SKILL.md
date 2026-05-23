---
name: generating-handoff
description: Use when dispatched as a subagent during the handoff stage of an SDD pipeline run, after implementation and testing complete and before finishing. Reads the entire SDD context (spec, plan, ADRs, state file, git log) and writes a redacted handoff document at $HOME/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<short-title>.md (path provided by the coordinator) that lets a fresh agent (or human) continue the work.
---

# Generating Handoff

## Overview

Write a self-contained handoff document that captures everything a fresh agent or developer needs to continue work on this feature — without forcing them to re-read the entire spec, plan, ADR set, and git history. Reference the source artifacts by path; don't duplicate them.

**Core principle:** A handoff document is a *bridge*, not a duplicate. It points at the source artifacts with enough context that the next agent knows what to read and why.

**Operating mode:** Read project + SDD artifacts + git log. Write ONE new file. Never modify other files.

**Announce at start:** "I'm using the generating-handoff skill to write the handoff document."

## Hard Gates

- NEVER commit `.sublime-skills/state.json`. It is permanently gitignored. Do NOT bypass via `git add -f`, `--force`, `git update-index`, or any other mechanism. See `state-schema.md` "Git policy" for the full list.
- Do NOT duplicate ADR content. Reference ADRs by path + one-line summary only.
- Do NOT duplicate large spec/plan sections. Reference + brief summary.
- Do NOT include secrets, API keys, passwords, tokens, or other sensitive material — redact per the Redaction section below.
- Do NOT modify any file other than the new handoff document.
- Do NOT use Mermaid, C4, PlantUML, ASCII art, or any other diagram syntax. Handoffs are prose + references — same prohibition that applies to specs and plans. The `validate-handoff.sh` script catches the labeled syntaxes (Mermaid, PlantUML, C4); ASCII art is on honor system.
- Do NOT use todo/task tools. The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools. Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents. You are a leaf skill.

## What You Get From the Coordinator

The dispatch prompt includes:

- `STATE_PATH` — absolute path to the SDD state file (read this to know what stages ran, ADRs created, tests passed, etc.)
- `SPEC_PATH` — absolute path to spec.md
- `PLAN_PATH` — absolute path to plan.md
- `ADR_PATHS` — list of ADR paths created or modified during this run (may be empty)
- `BRANCH` — feature branch name
- `BASE_SHA` — first commit on this branch
- `HEAD_SHA` — current HEAD
- `HANDOFF_DIR` — absolute directory provided by the coordinator under `$HOME/.sublime-skills/handoffs/<repo-basename>/`. Treat it as an opaque write destination; no relative/absolute detection logic.

## Checklist

1. Read all inputs (state, spec, plan, ADRs)
2. Get git log between BASE_SHA and HEAD_SHA
3. Build the handoff content (see Structure section)
4. Run redaction sweep on everything before writing
5. Resolve the output path (`<HANDOFF_DIR>/YYYY-MM-DD-<short-title>.md`)
6. Write the content to `<output-path>.tmp`
7. Validate the staged file (run `validate-handoff.sh <output-path>.tmp`); on issues, edit the `.tmp` file and re-validate until it passes
8. Atomic `mv <output-path>.tmp <output-path>`
9. Report

## Step 1: Read Inputs

- `STATE_PATH` — note: feature_id, current_stage, stages_completed, stages_skipped, test_status, fix_iterations, branch, ADR results
- `SPEC_PATH` — read in full; extract: Goal, story titles + priorities, FR summary count, SC summary count, edge cases summary
- `PLAN_PATH` — read in full; extract: Architecture sentence, tech stack, phase summary (count of tasks per phase)
- Each ADR path — read enough to get the title and status; do NOT read full content (you're linking, not summarizing)

## Step 2: Git Log

```bash
git log --oneline "$BASE_SHA..$HEAD_SHA"
git diff --stat "$BASE_SHA..$HEAD_SHA"
```

Capture:
- Commit count
- Files changed (with file count + line additions/deletions)
- Notable commit messages — those that imply architectural or scope-level changes (use judgment)

## Step 3: Build Content

See Handoff Structure section below for the exact format.

## Step 4: Redaction Sweep

Before writing, run the redaction sweep on every string that will go into the handoff doc — including text you copied from spec/plan/git log, and your own generated summaries.

**Patterns to redact (replace with `[REDACTED]`):**

| Pattern | Example matches |
|---|---|
| OpenAI / Anthropic keys | `sk-...`, `sk-ant-...` (40+ chars) |
| AWS access keys | `AKIA...` (20 chars), `ASIA...` |
| GitHub tokens | `ghp_...`, `gho_...`, `ghu_...`, `ghs_...`, `ghr_...` |
| Generic high-entropy strings labeled as secrets | `password = "<10+ chars>"`, `secret = "<10+ chars>"`, `token = "<10+ chars>"`, `api_key = "<10+ chars>"` |
| JWT-shaped strings | `eyJ...` three base64 chunks separated by dots |
| URLs with embedded credentials | `https?://<user>:<pass>@<host>` |
| Common env var names with values | `*_SECRET=...`, `*_PASSWORD=...`, `*_TOKEN=...`, `*_KEY=...` (where value is more than 6 chars) |
| SSH private key markers | `-----BEGIN [A-Z ]+PRIVATE KEY-----` and following content |

**Rules:**
- When in doubt, redact. Over-redaction is recoverable (the source files still exist and aren't being shared); under-redaction is not.
- If you redact something, note in the doc: "1 secret-like value redacted in <section name>"
- Never include literal env-var values. If you mention an env var, refer to it by name only: `OPENAI_API_KEY (value redacted)`.
- If the spec or plan contains placeholder text like `<your-api-key-here>`, leave it as-is (it's already a placeholder).

After redaction, do a second-pass scan — sometimes one redaction reveals another nearby. Keep going until a full pass produces no new redactions.

## Step 5: Resolve Output Path

Filename: `YYYY-MM-DD-<short-title>.md`

- `YYYY-MM-DD` — today's date (from `date -u +%Y-%m-%d`)
- `<short-title>` — 2-5 kebab-case words pulled from the spec's title or short name. Examples: `user-auth`, `export-csv`, `fix-payment-timeout`

Full path: `<HANDOFF_DIR>/YYYY-MM-DD-<short-title>.md`

`HANDOFF_DIR` is the absolute path provided by the coordinator. No tilde expansion or path-shape detection is needed. The coordinator has already created the directory; the skill writes the file directly into it.

If a file at that exact path already exists (rare but possible — same-day re-run, or same short name as a previous handoff), append `-<N>` where `<N>` is the next available integer.

## Step 6: Write Staged File

Write the (redacted) handoff content to `<output-path>.tmp` first. This is the file the validator will check; the final `<output-path>` is only created on a successful validation.

## Step 7: Validate

```bash
./spec-driven-development/framework/validate-handoff.sh <output-path>.tmp
```

The validator knows to strip `.tmp` from the filename for the pattern check. If validation fails: edit `<output-path>.tmp` directly to address each CRITICAL finding, then re-run the validator. Do not proceed to Step 8 until validation returns `PASS`.

Common CRITICAL failures and fixes:
- **Missing required section** → add the section
- **Potential unredacted secret matching pattern** → redact (replace literal value with `[REDACTED]`); re-run Step 4's two-pass redaction sweep on the rest of the doc to be safe
- **Sensitive env var value assignment** → strip the value, leave the name only

## Step 8: Atomic Move

```bash
mv "<output-path>.tmp" "<output-path>"
```

## Step 9: Report

Return to the coordinator:

```
Handoff written: <output-path>
- Redactions performed: <count>
- Source artifacts referenced: spec, plan, <N> ADRs
- Git span: <BASE_SHA>..<HEAD_SHA> (<N> commits, <M> files changed)
- Validation: passed
```

---

## Handoff Structure

```markdown
# Handoff: <Spec Title>

**Feature ID:** NNN-<short-name>
**Branch:** <branch-name>
**Date generated:** YYYY-MM-DD
**Status:** <Implementation complete | Testing passed | Testing skipped | Testing failed (escalated)>

## Quick context

<2-3 sentences. What was built, for whom, why. Use domain vocabulary from the glossary if present.>

## Source artifacts

- **Spec:** [<path>](<path>) — <one-line summary of the goal>
- **Plan:** [<path>](<path>) — <one-line summary of approach>
- **ADRs created/touched in this run:**
  - [ADR-NNNN](<path>) — <one-line title>
  - [ADR-NNNN](<path>) — <one-line title>
  (Omit this list if no ADRs were created or touched.)
- **Prior relevant ADRs:** (only include if the spec or plan explicitly cites them)
  - [ADR-NNNN](<path>) — <one-line title>

## What got built

<2-4 paragraphs. Walk through the implementation at a level that lets a fresh reader orient. Use these anchors:
- Architecture choice and why (reference the ADR if there is one; don't duplicate)
- Major files / modules added or changed (list them with one-line responsibility each — keep it tight)
- Notable patterns followed (e.g., "follows the existing repository pattern in src/repositories/")
- Anything non-obvious that would surprise someone reading the diff cold>

## Build highlights (from git log)

- **Commits:** <N> commits between `<BASE_SHA>` and `<HEAD_SHA>`
- **Files changed:** <M> files, +<additions> / -<deletions> lines
- **Notable commits:** (list 2-5 commits that represent architectural or scope-level moments; not every commit)
  - `<sha>` — <message>

## Test status

<One paragraph reporting:
- Whether feature-level testing ran (Stage 14)
- Result: passed / passed_after_fixes / skipped (and reason) / failed (escalated)
- If failed/skipped: what was NOT verified that a fresh agent should manually check>

## Open concerns

<Bulleted list of anything that's not fully resolved:
- Open questions that didn't block implementation but should be addressed
- Known limitations or trade-offs (cite the ADR if there's one)
- Tests that were marked NO-TDD but probably should have tests later
- Areas where the implementer reported DONE_WITH_CONCERNS that weren't fully resolved

Use "None — implementation is clean" if there genuinely are none.>

## If you're continuing this work

<Practical guidance for a fresh agent picking up where this left off:
- Where to start reading (which file/function/test)
- What's tracked in the git log vs what's in the spec/plan
- If iterating on PR feedback: what's already been addressed vs what hasn't
- Any in-flight things (e.g., "branch hasn't been merged yet; awaiting PR review on <URL>")
- Any environment setup the next agent needs to know about (referenced by name only — no values)>

## Redactions

<If redactions were performed during generation, note them here so the reader knows the doc is not literally complete:
- "<count> secret-like values redacted across <section names>"
- "<count> env-var values referenced by name only"

If no redactions were needed: "None">

## Files not to look at (low signal)

<Optional. Only if applicable. List any files in the diff that are low-signal for understanding the feature (lockfiles, formatter-only changes, generated code) so the next reader doesn't waste time:
- `package-lock.json` — generated
- `dist/*` — build output

Omit if everything in the diff is meaningful.>
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Duplicating ADR content in the handoff doc | Link only, summarize in one line |
| Including secrets verbatim that "looked benign" | When in doubt, redact. Run the second-pass sweep. |
| Pasting raw git log output as a section | Distill: count + a few notable commits, not the full log |
| Writing a 3000-word handoff for a 1-day feature | Match scope to the work — terse is better than thorough here |
| Forgetting to validate via `validate-handoff.sh` | Required Step 7; runs on the staged `.tmp` content before the atomic mv |
| Recommending implementation details to the next agent | The plan covered that; handoff is about context, not direction |
| Putting forward-looking opinions about future scope | Open concerns is for known facts; "I think we should also..." goes in a new spec, not here |
| Including links to internal URLs without checking they don't leak (e.g., trace IDs that include secrets) | Treat any URL parameter that looks high-entropy as a candidate for redaction |
| Force-adding state.json with `git add -f` | NEVER. Zero exceptions. |
| Editing `.sublime-skills/.gitignore` mid-pipeline | NEVER. The ignore is permanent. |

## Red Flags

- About to copy a long block of spec text into the handoff → STOP; link + summarize
- About to write "TODO: add details about X" in the handoff → STOP; either find the detail and add it, or move it to Open concerns
- Spot a literal API key in the git log or code and considered whether to redact → REDACT
- Handoff getting longer than ~800 lines → STOP; you're duplicating source material
- About to invoke another skill (writing-specs, writing-plans, etc.) → STOP; you only write the handoff doc
- About to type `git add -f .sublime-skills/state.json` → STOP
- About to edit `.sublime-skills/.gitignore` → STOP
