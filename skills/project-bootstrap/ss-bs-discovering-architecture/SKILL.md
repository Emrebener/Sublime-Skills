---
name: ss-bs-discovering-architecture
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the architecture slot. Maps the project's layout, build configs, entry points, runtime topology, data stores, and integrations; then asks the user to confirm groupings, clarify boundaries, fill in non-code facts, and resolve cardinality. Writes docs/ARCHITECTURE.md (or the configured path) atomically.
---

# Discovering Architecture

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). Architecture facts come from two places — the code (layout, Dockerfiles, k8s manifests, dependency files, env vars) and the user's head (what's deliberately OUT of scope, why a relationship is N:N rather than 1:N, which integrations are critical-path vs nice-to-have, deployment topology not visible in repo). A subagent could extract the first half from one read pass but couldn't have the back-and-forth needed for the second. So this skill stays in the coordinator's context.

**Core principle:** Architecture is observed, not aspirational. Describe what the code actually is, not what someone wishes it was. If there are clear smells (a service half-extracted, a monolith hiding behind microservice naming), surface them to the user — don't paper over them, don't editorialize either.

**Announce at start:** "I'm using the ss-bs-discovering-architecture skill to build docs/ARCHITECTURE.md with you."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for architecture. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, or `replace`
- `EXISTING_CONTENT` — verbatim current architecture-file content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/ARCHITECTURE.md`; honors `context.architecture_path` config override if non-default)
- **`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text only for genuinely open prompts (boundaries, non-code facts).
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax in the proposed file — text only.
- Do NOT dispatch subagents. You're inline — you do the work.
- Do NOT speculate about architecture that isn't visible in the code OR explicitly stated by the user. No "we should have...", just "what is" or "what the user told me".
- Do NOT include code snippets longer than 2-3 lines — this is overview, not implementation.
- Do NOT claim a service exists when only its env var is set. Require SDK import OR docker-compose entry OR k8s manifest, OR the user explicitly confirming it.
- Do NOT overwrite an existing architecture doc in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT loop past 3 tweak iterations without surfacing bail options to the user.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read. If you need more reads, surface fewer suggestions instead of widening the budget.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT use severity MUST/SHALL for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (layout, build, …)     │
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings (+ diagnoses)         │
│   → Step 3: targeted questions (Q1, Q1.5 if SUGGEST,│
│             then Q2-Q5)                             │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 1.5: silent diagnose (if SUGGEST=on)       │
│   → Step 2: announce findings + gaps + diagnoses    │
│   → Step 3: targeted questions on gaps + Q1.5       │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
└─────────────────────────────────────────────────────┘
```

## Step 1: Code Scan (Silent — No User Narration Yet)

Read all of the following that exist. Don't narrate progress to the user — this happens silently, then you announce findings once in Step 2.

### 1a. Top-level layout

Run a tree-like listing of the repo's top 2-3 levels. Note:

- Source dirs (`src/`, `lib/`, `app/`, language-specific layouts)
- Service dirs (`services/`, `apps/`, `packages/`)
- Infra dirs (`infra/`, `terraform/`, `k8s/`, `docker/`, `deploy/`)
- Docs dirs (`docs/`, `documentation/`)
- Test dirs (`tests/`, `test/`, `__tests__/`, `spec/`)
- Generated / vendored (`node_modules/`, `vendor/`, `target/`, `build/`, `dist/` — usually ignore)

If you see multiple service-like subdirs (e.g., `services/billing/`, `services/checkout/`), this is a multi-service repo even if not formally a monorepo. Note that.

### 1b. Build / dependency files

Read the relevant ones:

- **JavaScript/TypeScript:** `package.json` (root + per-workspace if monorepo), `pnpm-workspace.yaml`, `lerna.json`, `nx.json`, `turbo.json`
- **Python:** `pyproject.toml`, `setup.py`, `requirements*.txt`, `Pipfile`, `poetry.lock`
- **Rust:** `Cargo.toml` (root + per-workspace), `Cargo.lock`
- **Go:** `go.mod`, `go.sum`
- **Java/Kotlin:** `pom.xml`, `build.gradle*`, `settings.gradle*`
- **Ruby:** `Gemfile`, `gemspec`
- **C#/.NET:** `*.csproj`, `*.sln`
- **Multi-language:** `Makefile`, `justfile`, `Taskfile.yml`

Extract: language(s), framework(s), key libraries (web framework, ORM, queue client, HTTP client, etc.), build tooling, package manager.

### 1c. Entry points

Identify them by looking for:
- `main`, `index`, `app`, `server`, `cli` files at common paths (`src/main.*`, `src/index.*`, `cmd/<name>/main.go`, `app/main.py`, etc.)
- Build outputs declared in `package.json`'s `bin` field or `scripts.start` / `scripts.dev`
- Worker / job entry points (look for `worker.*`, `job.*`, `cron.*`, or queue-consumer code patterns)
- CLI entry points (look for `argparse`/`clap`/`commander`/`click` imports)

For each entry point, one-line description: what process does it run? When is it invoked?

### 1d. Runtime topology

Read:
- `Dockerfile` and `Dockerfile.*` variants — what runtime is the prod artifact?
- `docker-compose.yml` and `docker-compose.*.yml` — local dev topology
- `k8s/*.yaml`, `manifests/*.yaml` — production topology
- `terraform/*.tf`, `pulumi/*.py`, `cdk/*.ts` — infrastructure-as-code
- `Procfile` — Heroku-style services
- `fly.toml`, `render.yaml`, `vercel.json`, `netlify.toml` — PaaS configs
- `serverless.yml`, `sam.yaml` — serverless

Extract: what processes run? Where? How do they communicate (HTTP, queues, RPC)? Is there a load balancer / API gateway / reverse proxy in front?

### 1e. Data stores

Look for:
- DB drivers in dependency lists: `pg`, `mysql2`, `psycopg`, `sqlx`, `gorm`, `prisma`, `mongoose`, `mongodb`, `redis`, etc.
- Connection-string env vars: `DATABASE_URL`, `REDIS_URL`, `KAFKA_BROKERS`, etc.
- Migration directories: `migrations/`, `db/migrations/`, `prisma/migrations/`
- `docker-compose.yml` services like `postgres`, `redis`, `clickhouse`, `kafka`, `rabbitmq`

For each store, one-line purpose: what does this codebase use it for? (If not obvious from config alone, note it and ask the user in Step 3.)

### 1f. External integrations

The fastest signal: `.env.example` / `.env.sample`. List the third-party services hinted at by env-var names:
- `STRIPE_*` → Stripe (payments)
- `SENDGRID_*` / `MAILGUN_*` / `RESEND_*` → email
- `OPENAI_*` / `ANTHROPIC_*` → LLM APIs
- `AWS_*` → AWS (S3, SQS, etc.)
- `SENTRY_*` / `DATADOG_*` → observability
- `AUTH0_*` / `CLERK_*` / `OKTA_*` → identity
- `TWILIO_*` → SMS/voice

Cross-reference with SDK imports in source (`import Stripe from 'stripe'`, etc.) to confirm. Env-var-only signals get flagged for the user in Step 3 — don't list them as confirmed integrations.

### 1g. Boundary signals

What's in scope for this codebase vs out:

- Monorepo with multiple apps → list which apps are part of this overview
- Vendored code in `vendor/` or `third_party/` → out of scope (don't describe it)
- Generated code (e.g., from OpenAPI schemas) → identify but don't describe internals
- External API contracts that this codebase implements vs depends on
- Anything explicitly documented as "this lives in another repo"

### 1h. Mode-specific reads

- **`create` mode:** ignore `EXISTING_CONTENT` (it's empty). Build candidate sections from scratch.
- **`extend` mode:** read `EXISTING_CONTENT` and identify which of the six sections are missing, outdated, or incomplete. Candidate additions focus on gaps.
- **`replace` mode:** ignore `EXISTING_CONTENT`. Build candidates fresh.

### 1i. Compile candidate sections in memory

Hold internally:
- System summary draft (one paragraph)
- Component list (capped at ~10 — group if more)
- Topology summary
- Data store list with purpose (mark unclear ones)
- Confirmed integrations (SDK + env-var) vs env-var-only (flag for Q3)
- Boundary signals (in/out)
- Open questions: ambiguous component groupings, env-var-only integrations, unclear topology, anything not visible from code

## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for anti-patterns and missing-but-typically-valuable structural decisions in the architecture. Every diagnose finding must be **evidence-cited** with specific file paths or concrete counts. Abstract "you should do X" findings are not allowed.

### 1.5a. Architecture diagnose categories

For each category below, scan additional files if needed (within the budget — see Hard Gates). Generate at most 5 candidate suggestions total across all categories, ranked by severity → evidence strength → impact.

- **Cross-service direct DB access.** If multiple services share a single DB and at least one service reads another's tables directly. Evidence: list at least 2-3 file paths showing the cross-table reads.
- **Synchronous service chains where async would add resilience.** Service A makes HTTP calls to service B inside a request handler with no queueing or fallback. Evidence: file paths showing the synchronous calls.
- **Shared mutable state across modules.** Module-level mutable maps, singletons, or DI containers being mutated post-init from multiple call sites. Evidence: file paths to definitions + call sites.
- **Missing boundaries / ownership for shared code.** A `common/`, `shared/`, or `lib/` directory imported by all services with no documented ownership rules. Evidence: directory path + import counts.
- **Missing API gateway for public surfaces.** Multiple services exposing public HTTP endpoints with no routing/auth layer in front. Evidence: list the services + their `app.listen`/equivalent.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline (e.g., "Declare cross-service DB access policy")
- `evidence`: specific file paths or counts (e.g., `services/billing/src/invoice.ts:34, .../report.ts:88, .../sync.ts:12`)
- `proposed_addition`: exact markdown text to add to the artifact (a new section, a new component entry, etc.)

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence (no MUST without observable harm).

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more file paths / higher counts = stronger)
3. Impact (changes that prevent bugs > changes that improve consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3 is skipped silently.

## Step 2: Announce Findings

One short message (3-6 sentences). State what you scanned and the headline finding. Example:

> "Here's what I picked up from the codebase: a pnpm monorepo with three services (`services/billing`, `services/checkout`, `services/catalog`), all TypeScript on Express + Prisma, sharing `packages/common`. Runtime: docker-compose locally, k8s in prod with nginx ingress. Data stores: Postgres (per-service schemas) + Redis (queues + sessions). Confirmed integrations: Stripe, SendGrid, Sentry. A few things I want to confirm with you — component grouping, what's out of scope, and a couple of env-var-only signals. I'll show you a draft after."

If `create` mode and the scan found very little structure:
> "I didn't find much structural signal — no Dockerfile, no k8s manifests, single `src/` directory. Looks like a small library or single-file tool. I can still build an architecture overview, but it'll be brief. Want to continue?"

If `extend` mode:
> "Your existing architecture doc covers [sections]. I scanned the codebase and found gaps in [areas]. I'll ask about those, then propose additions."

If `SUGGEST=on` AND Step 1.5 produced ≥1 candidate, extend the announcement with: "…and I noticed a few things worth considering that aren't currently codified — I'll show those after we confirm the observed candidates."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan and (for extend mode) the existing file already answered it.

### Q1 — Component grouping (multi-choice)

Only ask if the scan signal is ambiguous (e.g., multiple service-like dirs that could be one logical component, or a monorepo where the grouping affects the doc).

```
Question: "I see these components: [list]. How should they group in the architecture overview?"

Options (adapt to scan):
  - "Monolith — one component, single deployable"
  - "Layered — frontend / backend / infra"
  - "Service-oriented — each service its own component"
  - "Custom (I'll describe in free-form)"

Recommend the option matching the scan signal.
```

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some things I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to
include:"

Multi-select. For each Step 1.5 candidate, list as:
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>

Always include "None of these — keep the doc descriptive only" as the last option.
```

If the user picks none, treat as "no suggestions accepted" and proceed to Q2. Accepted suggestions are carried into Step 4 (Draft & Show) and rendered with provenance markers.

### Q2 — Boundaries / scope (free-form)

```
Question: "What's explicitly OUT of scope for this codebase? Examples:
- 'Mobile apps live in a separate repo (acme/mobile)'
- 'We don't host email — third-party (Postmark) handles it'
- 'No data warehousing — read-only event firehose to BigQuery downstream'
- 'Catalog data comes from an upstream service we don't own'

Free-form text. Skip if everything visible in this repo is in scope (I'll write 'nothing material is out of scope' explicitly so it's clear)."
```

### Q3 — Env-var-only integrations (one question per uncertain signal, multi-choice)

For each integration where you saw the env var but not the SDK import (e.g., `STRIPE_SECRET_KEY` in `.env.example` but no `stripe` package in any service):

```
Question: "I see `<ENV_VAR>` in `.env.example` but no matching SDK import in the source. Is this integration:"

Options:
  - "Active — confirm it's used (I'll add it to the doc)"
  - "Planned but not implemented yet (drop from the doc)"
  - "Used via a different SDK or HTTP client (I'll add it with a note)"
  - "Legacy — should be removed from .env.example"
```

Cap this question loop at 5 uncertain integrations; if more, ask the user to scan the list themselves.

### Q4 — Non-code architecture facts (free-form)

```
Question: "Anything about the architecture that's true but not visible from the code? Examples:
- 'Deployed to three regions (us-east, eu-west, ap-south)'
- 'Critical path depends on Stripe — outage = full degradation'
- 'Database is shared with a separate analytics team'
- 'We run blue-green deployments via the ingress controller'

Free-form text. Skip if there's nothing material to add."
```

### Q5 — Topology cardinality (multi-choice, per ambiguous relationship)

Only ask if the scan revealed components with ambiguous relationships (e.g., two services both connecting to the same Redis but unclear whether they share data).

```
Question: "Relationship between [Component A] and [Component B] — what's the cardinality?"

Options:
  - "1:1 — direct one-to-one (e.g., each instance of A pairs with one B)"
  - "1:N — A has many B"
  - "N:N — many-to-many (often via a queue or shared store)"
  - "Not a direct relationship — they touch the same infra but don't communicate"
```

## Step 4: Draft & Show to User

Synthesize the draft using:
- Scan findings (layout, build, entry points, topology, stores, integrations)
- Confirmed grouping from Q1
- Accepted Q1.5 suggestions (rendered as new sections / new component entries with provenance markers — see Step 6)
- Out-of-scope from Q2
- Confirmed/dropped integrations from Q3
- Non-code facts from Q4
- Cardinality from Q5

Use the canonical template (see Output Template section). Show the full draft, then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip this file"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture user's free-form notes; apply; re-show; re-ask Step 4. Cap at **3 iterations**:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip architecture for now, or
> (c) supply the file yourself — you write the markdown, I'll save it?"

**On Start over:** restart Step 3 from Q1 (scan findings carry over; user answers reset).

**On Abort:** report `skipped (declined mid-skill)` to the coordinator and exit.

## Step 6: Atomic Write & Report Outcome

```bash
cat > "$FILE_PATH.tmp" <<EOF
<draft content>
EOF
mv "$FILE_PATH.tmp" "$FILE_PATH"
```

For **extend** mode: merge `EXISTING_CONTENT` + the new sections / refinements into a single document, then write atomically. Preserve existing accurate sections; replace or add only what changed.

Report to the coordinator one of:

- `created` (mode = create, full draft written)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a regular section in the artifact (e.g., a new "Boundaries" subsection, a new "Components" entry, or a new top-level recommendation block). Append a provenance line at the end of the section using this exact format:

```markdown
> _Added via bootstrap suggestion pass (YYYY-MM-DD)._ _Evidence: <evidence
> summary from the Q1.5 candidate>. Not currently enforced — declared here as
> an aspirational architectural rule._
```

Replace `YYYY-MM-DD` with today's date. The audit skill reads this marker on re-runs to ask whether the aspiration has been realized in code.

## Output Template

Canonical six-section structure (omit sections only when truly nothing material applies — e.g., "External integrations" section can be removed for a self-contained library):

```markdown
# Architecture Overview

## System summary

<One paragraph. What is this system? Who does it serve? Where does it run?
Keep it accessible — someone new to the project should leave this paragraph
with the right mental model.>

## Components

<List of major components/modules with one-line responsibility each.>

- **<Name>** — <responsibility>
- **<Name>** — <responsibility>

## Runtime topology

<What processes run? Where (container, serverless, host)? How do they
communicate? Include the local dev topology if it differs meaningfully
from production.>

## Data stores

<Each store with one-line purpose. Note the access pattern if relevant
(read-heavy, write-heavy, ephemeral, etc.).>

- **<Store>** — <purpose>

## External integrations

<Each third-party service with one-line purpose. Note the criticality
(hard dependency vs nice-to-have).>

- **<Service>** — <purpose>

## Boundaries

### In scope
<What this codebase owns.>

### Out of scope
<What lives elsewhere — other repos, upstream services, vendored code,
generated code.>
```

**Drafting guidelines:**

- One paragraph for the system summary, not a wall of text
- Component list capped at ~10 entries; if you have more, the components are too granular — group
- Use real component names from the codebase, not generic terms
- For runtime topology: describe what's there, not what should be there. If it's a monolith, say "monolith" — don't dress it up
- For data stores: write the access pattern only if you observed it (read-heavy DB query, ephemeral redis cache). Don't infer.
- For external integrations: only list confirmed integrations (env-var + SDK import OR user confirmation in Q3)
- Boundaries section is often the most useful — be explicit about what's NOT in this repo, even if the user said "nothing material is out of scope" (write that explicitly)

## Common Mistakes

| Mistake | Fix |
|---|---|
| Adding a Mermaid/PlantUML/C4 diagram | Text only — no diagram syntax of any kind |
| Inventing topology not visible in code or stated by the user | If it's not in `Dockerfile`/k8s/etc., ask the user before claiming it exists |
| Restating package.json contents | Architecture overview ≠ dependency list |
| Lengthy component list (15+ entries) | Group; the goal is "main moving parts" not exhaustive enumeration |
| Code snippets in the architecture file | Almost never appropriate; if used, ≤3 lines |
| Vague "uses cloud services for storage" | Name the service: "S3 for object storage" |
| Aspirational architecture ("we're moving to ...") | Document the current state; transitions belong in ADRs |
| Skipping the Boundaries section because "everything is in scope" | If everything is in scope, say so explicitly with examples of what would be out |
| Bundling multiple questions in one ask | One question per turn |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize aspirational entries; without it, drift detection breaks |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off; do not run-but-suppress |

## Red Flags

- About to write a Mermaid diagram → STOP; no diagrams
- About to ask the user a question without using the question tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to start writing the file before showing a draft → STOP; show first, write second
- About to dispatch a subagent → STOP; you're inline, you do the work
- About to claim a service exists when only its env var is set → STOP; ask the user (Q3) before adding it
- About to inflate findings to look thorough → STOP; terse beats thorough here
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing architecture doc in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

Architecture has a code half (layout, Dockerfiles, k8s, dependencies, env vars) and a user half (what's deliberately out of scope, which integrations are critical-path, deployment topology not visible in repo, cardinality of relationships that touch shared infra). A subagent could extract the first half from one read pass but couldn't have the back-and-forth needed for the second. Routing the conversation through the coordinator (subagent returns findings → coordinator paraphrases → user replies → coordinator re-dispatches) wastes turns and risks every paraphrase drifting from intent.

So this skill stays inline. It scans the code itself, then asks the user about the things only they know. The four sibling skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-glossary`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`) follow the same pattern for the same reason.
