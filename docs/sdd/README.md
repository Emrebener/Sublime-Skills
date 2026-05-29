# Spec-Driven Development (SDD) — Documentation

A reliable, AI-friendly workflow for taking a feature idea from rough description to implemented code, with a 12-stage pipeline driven by 16 coordinated skills (ss-sdd-coordinator + 15 phase/subagent skills) plus 6 shared scripts and 2 state-schema files. A per-feature state file carries data between stages and coordinates the per-task subagents at Stage 8.

This document set is the canonical reference. The skill files under `skills/spec-driven-development/<skill>/SKILL.md` are the operational specs that the AI executes; these docs are the human-readable explanations of how everything fits together.

---

## TL;DR

You invoke `ss-sdd-coordinator` with a feature description. It walks the pipeline:

```
preflight → discover → spec → auto spec-review → ADRs → user approval
        ↓
plan
        ↓
settle feature branch + batch-commit
        ↓
per-task implementation (one implementer per task) + one mandatory final cross-cutting review
        ↓
optional feature testing
        ↓
optional memory-file maintenance
        ↓
finishing (`git merge --no-ff` to `main`, safe-delete the feature branch, `rm` state)
```

Along the way, **subagent-handled** stages run in fresh context: the spec auto-review, ADR maintenance, per-task implementation (one implementer subagent per task) followed by a single mandatory final cross-cutting code-quality review, feature testing, and memory-file maintenance. The coordinator stays thin: a state machine and a dispatcher. Phase-specific knowledge lives in dedicated skills loaded just-in-time.

A single global state file at `.sublime-skills/state.json` carries data between stages — the structured outputs each subagent writes back (ADR list, per-task statuses, etc.) and the per-task coordination record `ss-sdd-implementing-plans` shares with its implementer subagents. It's permanently gitignored — local-only orchestration metadata, created by Stage 0 (preflight) as a minimal shell and deleted by Stage 11 (finishing). Not a resume mechanism: SDD runs end-to-end in one conversation.

---

## Table of contents

1. **[pipeline.md](pipeline.md)** — every stage of the 12-stage pipeline explained in detail. Inputs, outputs, mechanism (inline vs subagent), failure handling.
2. **[skills.md](skills.md)** — reference for all 16 skills, the 6 shared scripts, and the canonical state schema. What each one does, when it's invoked, what it reads, what it writes.
3. **[artifacts.md](artifacts.md)** — full format specifications for every artifact: spec, plan, ADRs. With templates and worked examples.
4. **[state-and-config.md](state-and-config.md)** — state file schema (every field, who owns it), lifecycle, the `.sublime-skills/config.yml` schema with all defaults and overrides.
5. **[operations.md](operations.md)** — subagent dispatch mechanics, validation scripts, project conventions (TDD discipline, `[NO-TDD]` criteria, diagram prohibitions), and troubleshooting common issues.
6. **[rationale.md](rationale.md)** — design rationale. Why a thin coordinator + many skills, why no external dependencies, why abort-only preflight, comparisons to spec-kit/brainstorming/kiro.

---

## Quickstart

**First-time setup on a project:** invoke `ss-bs-bootstrapping-project` (in the `skills/project-bootstrap/` family) manually. It walks you through seven convention files via inline conversational `ss-bs-discovering-<topic>` skills (constitution / architecture / testing / glossary / domain-model / design / memory-file) — with an optional opt-in suggestion-pass that flags anti-patterns and missing-but-typically-valuable patterns — and scaffolds:
- `docs/CONSTITUTION.md` (optional project-wide principles)
- `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `docs/GLOSSARY.md`, `docs/DOMAIN.md`, `docs/DESIGN.md` (optional scaffolds)
- Agent memory file at the user's chosen path (CLAUDE.md / AGENTS.md / GEMINI.md / .agents.md)
- `.sublime-skills/config.yml` (copied from `skills/project-bootstrap/scaffolds/config.yml`, validated by `validate-config.sh`)
- `docs/adr/`, `docs/specs/` directories with README stubs

After the per-file loop and config validation, bootstrap runs `coherence-check.sh` to verify cross-artifact consistency before commit. For re-evaluating an already-bootstrapped project (drift, incoherence, opportunities), use the sibling skill `ss-bs-auditing-project` instead.

For the full bootstrap walkthrough (steps, decision tree, re-run semantics, troubleshooting), see [../bootstrap.md](../bootstrap.md).

**Starting a feature:** invoke `ss-sdd-coordinator` from `main` (the common case) or from an existing feature branch you want to build on top of. It will:
1. Run preflight (warns and asks if your working tree is dirty; aborts on detached HEAD; creates the SDD state file shell)
2. Interview you to understand the feature
3. Write a spec, run the automated spec-review, capture ADRs
4. Get your approval on the spec + ADRs, then write a plan (no separate plan review or approval)
5. Settle the feature branch (auto-silent on `main` / on derived name; ambiguity prompt otherwise) and batch-commit spec / plan / ADRs
6. Execute the plan task-by-task with fresh implementer subagents, then one final cross-cutting code-quality review
7. Optionally run feature tests
8. Update the memory file if applicable
9. Merge the feature branch into `main` with `--no-ff` and safe-delete it on success (local only — no push)

**If a stage halts mid-run** (e.g., Stage 7 batch-commit hook rejection, Stage 11 merge conflict): the coordinator surfaces the error verbatim and leaves the state file in place. Fix the underlying issue, then tell the coordinator to continue — Stage 7 and Stage 11 are both idempotent on the second pass. Cross-conversation resume is NOT supported: if you start a new conversation, any leftover state file is treated as orphan and removed by preflight.

---

## File layout (what gets created where)

```
<repo-root>/
├── .sublime-skills/
│   ├── config.yml                         # project-wide SDD config (committed)
│   ├── config-local.yml                   # per-developer overrides (gitignored)
│   ├── .gitignore                         # gitignores state.json + config-local.yml
│   └── state.json                         # created at Stage 0, deleted at Stage 11 (gitignored)
├── docs/
│   ├── CONSTITUTION.md                    # optional, project principles
│   ├── ARCHITECTURE.md                    # optional, repo-level
│   ├── GLOSSARY.md                        # optional
│   ├── DOMAIN.md                          # optional
│   ├── DESIGN.md                          # optional, visual design system
│   ├── adr/
│   │   ├── README.md
│   │   ├── 0001-<title>.md
│   │   └── 0002-<title>.md
│   ├── specs/
│   │   ├── README.md
│   │   └── 001-<short-name>/
│   │       ├── spec.md                    # written in Stage 2
│   │       └── plan.md                    # written in Stage 6
│   └── sdd/                               # these docs
│       ├── README.md
│       ├── pipeline.md
│       └── ...
└── skills/spec-driven-development/        # the skills themselves (in $SUBLIME_SKILLS_HOME, not the user's repo)
    ├── ss-sdd-coordinator/SKILL.md
    ├── ss-sdd-preflight/SKILL.md
    ├── ... (14 more skills)
    └── framework/
        ├── discover-context.sh
        ├── get-config-value.sh             # scalar config helper
        ├── validate-config.sh
        ├── coherence-check.sh
        ├── validate-spec.sh
        ├── validate-plan.sh
        ├── state-schema.md                 # canonical state schema (human)
        ├── state-schema.json               # canonical state schema (JSON Schema)
        └── README.md
```

> Note: a handoff document is no longer part of the SDD pipeline. To generate one on demand (in any session, SDD or not), use the standalone `ss-workflow-generating-handoff` skill — it writes to `$HOME/.sublime-skills/handoffs/<repo-basename>/`, outside the repo.

---

## Key design properties at a glance

- **Self-contained.** No runtime dependencies on external skill families (superpowers, kiro, spec-kit, etc.).
- **In-conversation only.** SDD runs end-to-end inside a single conversation; conversation context tells the coordinator where it is. The gitignored state file at `.sublime-skills/state.json` is the data-carrier between stages and the orchestration record for per-task subagents — not a resume mechanism.
- **Coordinator is thin.** It's a state machine + dispatcher; all real work lives in dedicated phase-skills or subagents.
- **Fresh context per task.** Per-task implementation uses one fresh implementer subagent per task. The coordinator's context stays clean.
- **One review where it counts.** The spec gets a rigorous auto-review and an explicit user-approval gate. The plan — a mechanical rendering of the approved spec — gets neither; it's checked by the writer's self-review and, after implementation, a single mandatory final cross-cutting code-quality review over the whole branch diff. No per-task reviews.
- **Abort-fast preflight.** No magic cleanup. If the repo isn't in a fit state, the user fixes it manually.
- **No diagrams.** Mermaid, C4, PlantUML, and ASCII art are all blocked in specs and plans. Prose only.
- **TDD strict by default.** `[NO-TDD]` opt-out exists but is allowed only for tightly-scoped non-logic changes.
- **User-gated optional stages.** Feature testing and memory-file maintenance are opt-in per run (both default yes).
- **Findings via dedicated skill.** Spec-review output is processed via `ss-sdd-receiving-review-findings` — no performative agreement, verify before fixing, push back when the reviewer is wrong.

---

## Where to go next

- **Setting up a project for SDD for the first time?** → [../bootstrap.md](../bootstrap.md)
- **Want to understand the workflow?** → [pipeline.md](pipeline.md)
- **Want to know what each skill does?** → [skills.md](skills.md)
- **Need to write a spec by hand or understand the format?** → [artifacts.md](artifacts.md)
- **Hit a "state file" question or need to configure?** → [state-and-config.md](state-and-config.md)
- **Wondering about subagents or how to handle issues?** → [operations.md](operations.md)
- **Want to know why we built it this way?** → [rationale.md](rationale.md)
