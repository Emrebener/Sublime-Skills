---
name: ss-workflow-generating-handoff
description: Use when the user wants a handoff document for the current session — a self-contained note that lets a fresh agent (or human) pick up the work in a new conversation. Reads conversation context (what was discussed, what was built, what's left, what's blocked), then writes one markdown file at $HOME/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<short-title>.md. Works for any kind of in-flight work, with no SDD pipeline assumptions.
---

# Generating Handoff

## Overview

Write a self-contained handoff document that captures everything a fresh agent or developer needs to continue this work in a new conversation — what was being done, why, where it stands, and what to do next. The handoff is a *bridge*: it points at code, branches, PRs, and external resources rather than duplicating them.

**Operating mode:** Read conversation context + lightweight project state (git log, working-tree status, key files touched). Write ONE new file outside the repo. Never modify other files.

**Announce at start:** "I'm using the ss-workflow-generating-handoff skill to write a handoff document."

## Hard Gates

- Do NOT include secrets, API keys, passwords, tokens, or other sensitive material — redact per the Redaction section below.
- Do NOT modify any file other than the new handoff document. The handoff lives outside the repo (`$HOME/.sublime-skills/handoffs/...`) — no commit, no `git add`.
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax. Handoffs are prose + references.
- Do NOT use your harness's todo/task tool or interactive-question tool while generating the handoff — write it in one pass from context you already have. If something critical is unknown, note it as an open concern rather than asking.
- Do NOT dispatch subagents. This skill writes one file.
- Do NOT invent details. If you don't know something (a PR URL, a test result, a stakeholder name), say so or omit — never fabricate.

## What This Skill Assumes

You are running in the same conversation as the work being handed off. The bulk of your input is the conversation itself — what the user asked for, what was tried, what worked, what didn't. The repo state (`git status`, `git log`, recent edits) is supporting evidence, not the primary source.

If you are being asked to write a handoff for work that happened in a *previous* conversation that you have no memory of, stop and tell the user: this skill is designed for live sessions, not retroactive reconstruction.

## Checklist

1. Gather conversation context — what was the goal, what was done, where it stands
2. Gather light project state — current branch, recent commits on this branch, working-tree status, key files touched
3. Pick a short title (2-5 kebab-case words) summarizing the work
4. Resolve `HANDOFF_DIR` and ensure it exists
5. Draft the handoff content (see Structure section)
6. Run the redaction sweep on everything you're about to write
7. Resolve the output path and write the file
8. Report the path back to the user

## Step 1: Conversation Context

From the conversation, extract:

- **Goal** — what the user wanted (1-2 sentences in their own framing, not a re-pitch)
- **What was actually done** — files created/changed, decisions made, commands run, results observed
- **Where it stands** — done / partially done / blocked / abandoned, and on which sub-parts
- **Open questions and unresolved decisions** — things flagged in conversation that aren't settled
- **Anything tried and ruled out** — so the next agent doesn't repeat dead-ends

If the conversation is long, focus on the most recent coherent thread of work, not every aside.

## Step 2: Project State

Run these and capture the salient bits:

```bash
git rev-parse --show-toplevel              # repo root → basename for path
git rev-parse --abbrev-ref HEAD            # current branch
git status --short                         # uncommitted changes
git log --oneline -20                      # recent commits (or use a base..HEAD range if you know the base)
```

If a feature branch was created during the session, use `git log --oneline <base>..HEAD` (often `main..HEAD`) for the commit list, plus `git diff --stat <base>..HEAD` for changed-files summary. If not, the last few commits are enough.

You do not need to read every changed file — knowing *which* files changed and what they're for is enough for a bridge document.

## Step 3: Short Title

2-5 kebab-case words pulled from the work itself. Examples:

- `add-csv-export`
- `fix-login-redirect`
- `refactor-auth-middleware`
- `wire-stripe-webhooks`

Avoid generic titles (`update-code`, `fixes`, `work-in-progress`).

## Step 4: Resolve Output Path

```bash
REPO_BASENAME=$(basename "$(git rev-parse --show-toplevel)")
HANDOFF_DIR="$HOME/.sublime-skills/handoffs/$REPO_BASENAME"
mkdir -p "$HANDOFF_DIR"
```

If the current working directory is not inside a git repo, fall back to using the basename of the cwd. If even that fails (no `$HOME`, no write access), surface the OS error verbatim and stop — don't pick a fallback location.

Filename: `YYYY-MM-DD-<short-title>.md` (date from `date -u +%Y-%m-%d`).

Full path: `$HANDOFF_DIR/YYYY-MM-DD-<short-title>.md`

If a file at that exact path already exists, append `-<N>` where `<N>` is the next available integer (`...-csv-export-2.md`).

## Step 5: Draft Content

See the Handoff Structure section below for the format. Match the length to the work — a 30-minute fix gets a short handoff; a multi-day feature gets more. Err on the side of *terse and pointed* over thorough.

## Step 6: Redaction Sweep

Before writing, scan every string you're about to put in the doc — including things copied from logs, command output, and your own summaries.

**Patterns to redact (replace literal value with `[REDACTED]`):**

| Pattern | Example matches |
|---|---|
| OpenAI / Anthropic keys | `sk-...`, `sk-ant-...` (20+ chars) |
| AWS access keys | `AKIA...` / `ASIA...` (20 chars) |
| GitHub tokens | `ghp_...`, `gho_...`, `ghu_...`, `ghs_...`, `ghr_...` |
| JWT-shaped strings | `eyJ...` three base64 chunks separated by dots |
| SSH/PGP private keys | `-----BEGIN [A-Z ]+PRIVATE KEY-----` and following content |
| URLs with embedded credentials | `https?://<user>:<pass>@<host>` |
| Sensitive env-var values | `*_SECRET=...`, `*_PASSWORD=...`, `*_TOKEN=...`, `*_API_KEY=...`, `*_KEY=...` where the value is more than 6 chars |
| Generic high-entropy values labeled as secrets in prose | `password = "<10+ chars>"`, `secret = "<10+ chars>"`, etc. |

**Rules:**

- When in doubt, redact. Over-redaction is recoverable (the source still exists locally); under-redaction is not (the handoff lives in `$HOME` and may be shared).
- Refer to env vars by name only: `STRIPE_SECRET_KEY (value redacted)`. Never include the value.
- Treat any URL query parameter that looks high-entropy (long random-looking strings, signed tokens) as a candidate for redaction.
- After redacting, do a second pass — sometimes one redaction reveals another nearby. Keep going until a full pass produces no new redactions.
- Count the redactions; note the total in the **Redactions** section of the handoff.

## Step 7: Write the File

Write the final, redacted content directly to `$HANDOFF_DIR/YYYY-MM-DD-<short-title>.md`. No commit — the file lives outside the repo by design.

## Step 8: Report

Tell the user:

```
Handoff written: <absolute-path>
- Title: <short-title>
- Branch: <branch-name>
- Redactions: <count>
```

If anything material was omitted because you weren't sure (e.g., a PR URL you couldn't confirm), say so in the report.

---

## Handoff Structure

The required sections are `Quick context`, `What got done`, `Where it stands`, `If you're continuing this work`, and `Redactions`. The optional sections (`Things tried and ruled out`, `Open questions`, `Project state`, `Files & references`, `Files not to look at`) are there when they earn their place — skip any that would be empty or fluff for the work at hand.

```markdown
# Handoff: <Short title in sentence case>

**Branch:** <branch-name>
**Date generated:** YYYY-MM-DD
**Status:** <one of: In progress | Blocked | Done locally, not pushed | Awaiting review | Abandoned>

## Quick context

<2-3 sentences. What the user wanted, why, in their framing. Use the user's vocabulary; don't re-pitch the task.>

## What got done

<2-5 short paragraphs OR a tight bulleted list. Walk through the work at a level that lets a fresh reader orient:
- Major files / modules added or changed (one-line responsibility each)
- Key decisions made and (briefly) why
- Patterns followed (e.g., "matches existing handler pattern in src/handlers/")
- Anything non-obvious that would surprise someone reading the diff cold

Reference files by path. Don't paste their contents.>

## Where it stands

<One short paragraph + optional bullets:
- What is complete and verified
- What is complete but unverified (and how to verify)
- What is partially done (and which sub-part is the next concrete step)
- What is blocked (and on what)>

## Things tried and ruled out

<Optional. Include if the conversation explored approaches that didn't work, so the next agent doesn't repeat them. Each item: what was tried, why it didn't work. One line each. Omit the section if there's nothing.>

## Open questions

<Optional. Bulleted list of unresolved questions or decisions that came up but weren't settled. Each one: the question, who's expected to answer it (user / owner / future agent), if known. Omit if there are none.>

## Project state

<Optional but usually included for in-flight work. A compact snapshot:
- Current branch: <name> (based on <base>)
- Commits on this branch: <N> (`<base-sha>..<head-sha>`)
- Uncommitted changes: <none | brief description>
- Recent notable commits (2-5 max):
  - `<sha>` — <message>

Omit if the work didn't touch git (e.g., a pure research / discussion session).>

## Files & references

<Optional. Pointers a fresh agent would want — external URLs, PR links, issue numbers, design docs, dashboards, etc. Each one: link + a one-line "why you'd open this". Omit if there are none.>

## If you're continuing this work

<Required. Practical guidance for the next agent:
- Where to start reading (which file/function/test)
- The next concrete action to take
- Any environment setup the next agent should know about (env vars by name only — no values; tools that must be installed; services that must be running)
- Anything in-flight (e.g., "branch hasn't been pushed yet", "PR is open at <URL> awaiting review on the X change")
- Constraints or context that isn't obvious from the code (deadlines, stakeholders, related work happening in parallel)>

## Redactions

<If any redactions were performed, note them so the reader knows the doc isn't literally complete:
- "<N> secret-like values redacted across <section names>"
- "<N> env-var values referenced by name only"

If no redactions were needed: "None">

## Files not to look at (low signal)

<Optional. List any files in the diff that are low-signal for understanding the work (lockfiles, formatter-only changes, generated code) so the next reader doesn't waste time. Omit if everything in the diff is meaningful.>
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Re-pitching the task instead of recording the user's framing | Quote / paraphrase the user; don't dress up the goal |
| Pasting full file contents or full git logs | Reference + distill; the source lives in the repo |
| Writing a long handoff for a small piece of work | Match length to scope — terse beats thorough here |
| Including secrets that "looked benign" | When in doubt, redact. Run the second-pass sweep. |
| Forward-looking opinions ("we should also...") in Open questions | Open questions = facts that need a decision. Opinions about future scope go in a separate planning doc, not here. |
| Forgetting to record what was *ruled out* | The next agent will repeat your dead-ends. One line per dead-end saves them an hour. |
| Naming environment values verbatim | Env vars by name only. `STRIPE_SECRET_KEY (value redacted)`. |
| Including signed URLs / trace IDs with embedded tokens | Treat high-entropy URL parameters as redaction candidates. |
| Committing the handoff file | NEVER. It lives in `$HOME/.sublime-skills/handoffs/...` outside the repo by design. |

## Red Flags

- About to copy a long block of code or log output into the handoff → STOP; reference + summarize.
- About to write "TODO: add details about X" → STOP; either fill it in or move X into Open questions.
- Spotted a literal credential in the working tree or command history and considered whether to redact → REDACT.
- Handoff getting longer than ~500 lines → STOP; you're duplicating source material that lives in the repo or in linked URLs.
- About to ask the user a clarifying question mid-write → STOP; this skill writes from context. If something is genuinely unknown, note it in Open questions and move on.
- About to `git add` or commit the handoff file → STOP; it lives outside the repo.
