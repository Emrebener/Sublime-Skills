# Spec-Driven Development (SDD) — Documentation

A reliable, resumable, AI-friendly workflow for taking a feature idea from rough description to merged code, with a 17-stage pipeline driven by 21 coordinated skills (sdd-coordinator + 20 phase/subagent skills) plus 6 shared scripts and 2 state-schema files.

This document set is the canonical reference. The skill files under `spec-driven-development/<skill>/SKILL.md` are the operational specs that the AI executes; these docs are the human-readable explanations of how everything fits together.

---

## TL;DR

You invoke `sdd-coordinator` with a feature description. It walks the pipeline:

```
preflight → discover → spec → reviews → ADRs → user approval
        ↓
plan → reviews → user approval
        ↓
per-task implementation (with two-stage review per task)
        ↓
optional feature testing
        ↓
handoff doc generation
        ↓
finishing (merge / PR / keep / discard)
```

Along the way, six **subagent-handled** stages run in fresh context: spec auto-review, optional 2nd spec-review, ADR maintenance, plan auto-review, optional 2nd plan-review, per-task implementation + per-task spec-compliance review + per-task code-quality review, feature testing, handoff generation. The coordinator stays thin: a state machine and a dispatcher. Phase-specific knowledge lives in dedicated skills loaded just-in-time.

Everything is resumable: a per-feature state file at `docs/specs/NNN-<short-name>/state.json` tracks current stage and per-task progress, committed alongside the spec and plan in git. If a session dies, the next session reads the state file first and picks up where it left off.

---

## Table of contents

1. **[pipeline.md](pipeline.md)** — every stage of the 17-stage pipeline explained in detail. Inputs, outputs, mechanism (inline vs subagent), failure handling.
2. **[skills.md](skills.md)** — reference for all 21 skills, the 6 shared scripts, and the canonical state schema. What each one does, when it's invoked, what it reads, what it writes.
3. **[artifacts.md](artifacts.md)** — full format specifications for every artifact: spec, plan, ADRs, handoff document. With templates and worked examples.
4. **[state-and-config.md](state-and-config.md)** — state file schema (every field, who owns it), resume protocol, the `.sdd/config.yml` schema with all defaults and overrides.
5. **[operations.md](operations.md)** — subagent dispatch mechanics, validation scripts, project conventions (TDD discipline, `[NO-TDD]` criteria, diagram prohibitions), and troubleshooting common issues.
6. **[rationale.md](rationale.md)** — design rationale. Why a thin coordinator + many skills, why no external dependencies, why abort-only preflight, comparisons to spec-kit/brainstorming/kiro.

---

## Quickstart

**First-time setup on a project:** invoke `bootstrapping-project` (in the `project-bootstrap/` family) manually. It walks you through each convention file via five inline conversational `discovering-<topic>` skills (constitution / architecture / glossary / domain-model / design) and scaffolds:
- `docs/constitution.md` (optional project-wide principles)
- `docs/ARCHITECTURE.md`, `docs/GLOSSARY.md`, `docs/DOMAIN.md`, `docs/DESIGN.md` (optional scaffolds)
- `.sdd/config.yml` (copied from `project-bootstrap/scaffolds/config.yml`, validated by `validate-config.sh`)
- `docs/adr/`, `docs/specs/`, `docs/handoff/` directories with README stubs

For the full bootstrap walkthrough (steps, decision tree, re-run semantics, troubleshooting), see [../bootstrap.md](../bootstrap.md).

**Starting a feature:** make sure you're on `main` (or `master`) with a clean working tree, then invoke `sdd-coordinator`. It will:
1. Run preflight checks (will abort if dirty or on a wrong branch — clean up first)
2. Interview you to understand the feature
3. Write a spec, run automated and optional manual reviews, capture ADRs
4. Get your approval, write a plan, run reviews, get your approval
5. Execute the plan task-by-task with fresh implementer + reviewer subagents
6. Optionally run feature tests
7. Generate a handoff doc
8. Wrap up (merge / PR / keep / discard) per your config or interactive choice

**Resuming an interrupted run:** just invoke `sdd-coordinator` again. It reads state first; if it finds an active run, it asks if you want to resume.

**Checking status without entering the pipeline:** invoke `inspecting-state` directly. It reports all active runs without making any changes.

---

## File layout (what gets created where)

```
<repo-root>/
├── .sdd/
│   └── config.yml                         # project-wide SDD config
├── docs/
│   ├── constitution.md                    # optional, project principles
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
│   │       ├── plan.md                    # written in Stage 8
│   │       └── state.json                 # written in Stage 2, deleted in Stage 16
│   ├── handoff/
│   │   ├── README.md
│   │   └── 2026-05-20-<title>.md          # written in Stage 14
│   └── sdd/                               # these docs
│       ├── README.md
│       ├── pipeline.md
│       └── ...
└── spec-driven-development/               # the skills themselves
    ├── sdd-coordinator/SKILL.md
    ├── preflight-checks/SKILL.md
    ├── ... (19 more skills)
    └── scripts/
        ├── discover-context.sh
        ├── get-config-value.sh             # scalar config helper
        ├── validate-spec.sh
        ├── validate-plan.sh
        ├── validate-handoff.sh
        ├── state-schema.md                 # canonical state schema (human)
        ├── state-schema.json               # canonical state schema (JSON Schema)
        └── README.md
```

---

## Key design properties at a glance

- **Self-contained.** No runtime dependencies on external skill families (superpowers, kiro, spec-kit, etc.).
- **Resumable.** Per-feature state file in git lets any session pick up where any other session left off.
- **Coordinator is thin.** It's a state machine + dispatcher; all real work lives in dedicated phase-skills or subagents.
- **Fresh context per task.** Per-task implementation uses fresh subagents (implementer + 2 reviewers). The coordinator's context stays clean.
- **Abort-fast preflight.** No magic cleanup. If the repo isn't in a fit state, the user fixes it manually.
- **No diagrams.** Mermaid, C4, PlantUML, and ASCII art are all blocked in specs and plans. Prose only.
- **TDD strict by default.** `[NO-TDD]` opt-out exists but is allowed only for tightly-scoped non-logic changes.
- **Two-stage per-task review.** Spec compliance → then code quality. Different reviewers, different focus.
- **User-gated optional stages.** 2nd spec/plan reviews, the grill, and feature testing are all opt-in per run.
- **Findings via dedicated skill.** Review output is processed via `receiving-review-findings` — no performative agreement, verify before fixing, push back when reviewer is wrong.
- **Handoff doc at the end.** A redacted, summary-style document that lets a fresh agent continue work without re-reading everything.

---

## Where to go next

- **Setting up a project for SDD for the first time?** → [../bootstrap.md](../bootstrap.md)
- **Want to understand the workflow?** → [pipeline.md](pipeline.md)
- **Want to know what each skill does?** → [skills.md](skills.md)
- **Need to write a spec by hand or understand the format?** → [artifacts.md](artifacts.md)
- **Hit a "state file" question or need to configure?** → [state-and-config.md](state-and-config.md)
- **Wondering about subagents or how to handle issues?** → [operations.md](operations.md)
- **Want to know why we built it this way?** → [rationale.md](rationale.md)
