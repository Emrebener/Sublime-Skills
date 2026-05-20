---
name: initializing-project-context
description: Use to bootstrap a project for spec-driven development - constitution, architecture overview, glossary, ADR/spec directories, and SDD config. Invoked manually by the user; not part of the SDD pipeline. Each artifact is opt-in.
---

# Initializing Project Context

## Overview

One-time setup that lays down the foundation files the SDD pipeline consults during spec/plan writing and reviews. Everything is optional — pick what fits.

**Core principle:** Generate scaffolds with guided questions, not blank files. A populated stub is more useful than an empty template.

**Announce at start:** "I'm using the initializing-project-context skill to bootstrap SDD for this project."

## What This Skill Doesn't Do

- It does NOT run the SDD pipeline. That's `sdd-coordinator`.
- It does NOT write specs or plans. That's for the pipeline.
- It does NOT enforce anything globally. Each artifact it creates is referenced by pipeline skills only if present.

## Checklist

The coordinator (or directly-invoking user) MUST proceed through these in order:

1. Detect existing setup
2. Confirm what to set up — present an opt-in menu
3. For each chosen artifact, run its guided sub-flow
4. Create supporting directories (`docs/adr`, `docs/specs`, `.sdd`)
5. Write `.sdd/config.yml` with reasonable defaults
6. Commit the initial scaffolding
7. Report

## Step 1: Detect Existing Setup

Run the discovery script:

```bash
./spec-driven-development/scripts/discover-context.sh
```

For each existing artifact: don't overwrite. Either skip it in the opt-in menu, or offer to extend/edit it instead of recreate.

## Step 2: Opt-In Menu

Present this menu (skipping items the user already has):

```
SDD project setup — pick what to set up. You can pick any combination:

[ ] 1. Project constitution (docs/constitution.md)
       Project-wide principles the SDD pipeline checks against.
[ ] 2. Architecture overview (ARCHITECTURE.md or docs/ARCHITECTURE.md)
       High-level structure of the system; helps the pipeline situate features.
[ ] 3. Domain glossary (GLOSSARY.md or docs/GLOSSARY.md)
       Canonical names for domain concepts. Useful for domain-rich projects.
[ ] 4. Domain model (DOMAIN.md or docs/DOMAIN.md)
       Conceptual entities and their relationships. Useful when domain logic is complex.
[ ] 5. Context map (CONTEXT-MAP.md)
       For monorepos with multiple bounded contexts.
[ ] 6. SDD config (.sdd/config.yml)
       Paths (spec/adr/handoff dirs), preflight options, grill cap, handoff toggle, finishing mode + test command + PR command. Strongly recommended.
[ ] 7. ADR, spec, and handoff directories (docs/adr/, docs/specs/, docs/handoff/)
       Just create the empty directories with README stubs.

Pick (e.g., "1, 2, 6, 7"):
```

Don't ask one yes/no per item — single multi-select is faster.

## Step 3: Guided Sub-Flows

### 3.1 Project Constitution

Ask the user how many principles to author (suggest 3-7; cap at 10). For each principle, ask:

> "Principle #N — what's the rule? Phrase it as MUST / SHALL where it's non-negotiable, or as SHOULD where it's a strong default with rare exceptions."

After each principle, ask for a one-line **rationale** ("why is this a rule for us?").

Write `docs/constitution.md`:

```markdown
# Project Constitution

**Version:** 1.0.0
**Adopted:** YYYY-MM-DD

## Overview

A short paragraph (you can edit this) describing the spirit of the document: these are the rules every feature must comply with. Amendments require a version bump.

## Principles

### Principle 1 — <Name>

<Rule statement using MUST / SHALL / SHOULD.>

**Rationale:** <One-line rationale.>

### Principle 2 — <Name>

...

## Amendment Procedure

- PATCH: clarification, wording, typo (no semantic change)
- MINOR: new principle added or guidance materially expanded
- MAJOR: backward-incompatible removal or redefinition

Record version + date on every change.
```

### 3.2 Architecture Overview

Walk user through these sections, one at a time:

- **System summary** — one paragraph: what does this system do at a high level?
- **Major components / modules** — list with one-line responsibility each
- **Runtime topology** — what processes/services run? Where? How do they talk?
- **Data stores** — what databases/queues/caches? Each with one-line purpose
- **External integrations** — what third-party services? Each with one-line purpose
- **Boundaries** — what's in scope for this codebase vs out (clear delineation)

For each section: ask the question, accept their answer (paragraph or list), move on. Don't grill — this is a scaffold, not the spec.

Write to `ARCHITECTURE.md` at repo root (or `docs/ARCHITECTURE.md` if user prefers `docs/` for everything — ask once at start of this sub-flow).

### 3.3 Domain Glossary

Ask: "Which 10-30 domain terms most need canonical definitions?" Walk through each:

> "Term: <user provides>
> Definition (≤2 sentences):"

Write to `GLOSSARY.md`:

```markdown
# Glossary

## A

### Authorization
<Definition.>

## B

### Bounded context
<Definition.>

(alphabetical, grouped by first letter)
```

### 3.4 Domain Model

Ask user to list 3-15 core entities. For each:

- **Name** (canonical, from glossary if defined there)
- **What it represents** (one paragraph)
- **Key attributes** (3-10 bullet points, conceptual — no DB columns)
- **Key relationships** (which other entities does it relate to, and how)
- **Lifecycle** (states it can be in, transitions between them — if applicable)

Write to `DOMAIN.md`.

### 3.5 Context Map (Monorepo)

Only if the user confirmed this is a monorepo. Ask:

- "List the bounded contexts (e.g., `billing`, `catalog`, `checkout`)."
- For each context: directory path, brief purpose, allowed dependencies on other contexts.

Write to `CONTEXT-MAP.md`:

```markdown
# Context Map

## Contexts

### billing
- **Path:** `services/billing/`
- **Purpose:** subscription pricing, invoicing, payment retries
- **Depends on:** identity (read-only)

### catalog
- **Path:** `services/catalog/`
- **Purpose:** product definitions and availability
- **Depends on:** none

(... etc)

## Allowed Dependency Edges

billing → identity
checkout → catalog, identity, billing
```

### 3.6 SDD Config

Write `.sdd/config.yml` with reasonable defaults. Show the user the proposed config and ask for confirmation:

```yaml
# SDD configuration. Pipeline skills read this; overrides for paths,
# finishing behavior, and harness tool names.

# Optional: where the pipeline writes specs, plans, ADRs, handoffs.
# Defaults: docs/specs/NNN-short-name/, docs/adr/, docs/handoff/
paths:
  spec_dir: docs/specs
  adr_dir: docs/adr
  handoff_dir: docs/handoff

# Where convention/context files live. Skills also check default
# locations (repo root, docs/) — these are overrides.
context:
  constitution_paths: []   # e.g., [docs/principles.md]
  architecture_paths: []
  glossary_paths: []
  domain_paths: []
  context_map_paths: []

# Preflight behavior.
preflight:
  branch_pattern: "feat/{short-name}"   # also: "fix/{short-name}" auto-selected if user describes a bugfix
  use_worktree: false                    # if true, work happens in .worktrees/<branch-name>

# Grill stage.
grill:
  question_cap: 10   # hard ceiling 20 even with override

# Handoff stage.
handoff:
  enabled: true       # set false to skip the handoff stage

# Finishing stage.
finishing:
  mode: prompt                # prompt | leave | merge-local | pr | auto
  merge_target: main
  delete_branch_after_merge: true
  test_command: null          # explicit test command; null = auto-detect (Make/npm/cargo/pytest/go/mvn/gradle)
  pr_command: "gh pr create --title '{title}' --body-file {body_file}"

```

User can edit before commit.

### 3.7 ADR, Spec, and Handoff Directories

```bash
mkdir -p docs/adr docs/specs docs/handoff
```

Write `docs/adr/README.md`:

```markdown
# Architecture Decision Records

Each ADR captures one significant architectural decision with context,
chosen approach, consequences, and alternatives considered.

Filename pattern: `NNNN-kebab-case-title.md` (zero-padded 4 digits).
Status lifecycle: Proposed → Accepted → (optionally) Superseded by ADR-NNNN | Deprecated.

ADRs are written by the `maintaining-adrs` skill during the SDD pipeline,
or manually by anyone with a decision worth capturing.
```

Write `docs/specs/README.md`:

```markdown
# Specs

Each subdirectory is one feature, with `spec.md`, `plan.md`, and
`state.json` (SDD pipeline state, deleted on completion).

Directory pattern: `NNN-kebab-name/` (zero-padded 3 digits).
```

Write `docs/handoff/README.md`:

```markdown
# Handoff Documents

Generated at the end of each SDD pipeline run (Stage 14). Each handoff
summarizes what was built, references the source artifacts (spec, plan,
ADRs), and gives a fresh agent enough context to continue work — for
example, when iterating on PR feedback in a new session.

Filename pattern: `YYYY-MM-DD-<kebab-title>.md`. Sortable by date.

Handoff docs are written by the `generating-handoff` skill. They redact
secrets (API keys, tokens, passwords, JWTs, private keys) so they're
safe to share or commit.
```

## Step 4: Add `.sdd/` to `.gitignore` Exclusions Correctly

`.sdd/config.yml` should be **committed** (it's project-wide config). But if you create local-only state (e.g., per-developer overrides at `.sdd/local.yml`), gitignore that:

```
# .gitignore
.sdd/local.yml
```

Per-feature state at `docs/specs/NNN-name/state.json` is committed during the pipeline; no gitignore entry needed.

## Step 5: Commit the Scaffold

```bash
git add docs/constitution.md docs/ARCHITECTURE.md docs/GLOSSARY.md \
        docs/DOMAIN.md docs/CONTEXT-MAP.md docs/adr/ docs/specs/ docs/handoff/ \
        .sdd/config.yml [.gitignore]
git commit -m "chore: initialize SDD project context"
```

Only `git add` the files that were actually created in this run. Don't add `docs/<foo>` if the user opted out of that artifact.

## Step 6: Report

```
SDD bootstrap complete.

Created:
- docs/constitution.md (N principles)
- ARCHITECTURE.md (or docs/ARCHITECTURE.md)
- GLOSSARY.md (N terms)
- docs/DOMAIN.md (N entities)
- .sdd/config.yml
- docs/adr/ (with README)
- docs/specs/ (with README)
- docs/handoff/ (with README)

Skipped (your choice):
- DOMAIN.md
- CONTEXT-MAP.md

Next steps:
- Review the created files and adjust if needed
- Run the sdd-coordinator skill to start your first feature
```

## Re-Running on an Existing Project

If the discovery script finds existing artifacts, this skill offers to **edit/extend** them instead of recreating. Example flow for an existing constitution:

> "docs/constitution.md already exists. Options:
> 1. Skip (leave it alone)
> 2. Add one or more new principles to it
> 3. Show me the current version and let me edit/delete principles interactively"

Don't overwrite without explicit user direction.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Creating empty templates with `[TODO]` placeholders | Always guide the user through filling them; populated stub > empty template |
| Overwriting existing files | Detect first; offer edit/extend instead of recreate |
| Forcing the constitution if user only wanted config | Each artifact is independent; respect the opt-in menu |
| Forgetting to gitignore `.sdd/local.yml` (or whatever local-only paths the user defines) | The committed `config.yml` is fine; only local overrides are gitignored |
| Bundling all files into one mega-commit without describing it | Commit message should list what was created |

## Red Flags

- About to overwrite an existing file without asking → STOP
- About to write `[fill in here]` placeholders into a generated file → STOP; ask the user instead
- About to write more than one constitution principle without rationale → STOP; ask for rationale per principle
