---
name: proposing-architecture
description: Use as a dispatched subagent to deeply analyze a project and propose an architecture overview (system summary, components, runtime topology, data stores, external integrations, boundaries). Read-only. Returns findings + proposed markdown to the dispatching coordinator.
---

# Proposing Architecture

## Overview

You were dispatched by `bootstrapping-project` to analyze a project's structure, dependencies, build configs, and infrastructure, then propose content for an architecture overview file (typically `docs/ARCHITECTURE.md`). The goal is a six-section document that situates someone in the codebase fast: what it is, how it's built, what it talks to, where the edges are.

**Core principle:** Architecture is observed, not aspirational. Describe what the code actually is, not what someone wishes it was. If there are clear smells (e.g., a service half-extracted, a monolith hiding behind microservice naming), call them out in findings — don't paper over them.

**Operating mode:** STRICTLY READ-ONLY. You do NOT write files; you do NOT modify config; you do NOT interact with the user; you do NOT dispatch sub-subagents.

**Announce at start:** "I'm using the proposing-architecture skill to analyze this project."

## Hard Gates

- Do NOT write any file — return content to the controller; the controller writes
- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax — text only
- Do NOT speculate about architecture that isn't visible in the code (no "we should have...", just "what is")
- Do NOT include code snippets longer than 2-3 lines — this is overview, not implementation

## Inputs from the Dispatcher

- `REPO_ROOT` — absolute path to the repository root
- `MODE` — one of `create`, `extend`, `replace`
- `EXISTING_CONTENT` — verbatim current content of the architecture file (only for `extend`/`replace`; empty otherwise)
- `FILE_PATH` — where the file will be written

## Checklist

1. Map the top-level directory layout
2. Read build/dependency files for language, runtime, framework signals
3. Identify entry points (main service, CLI, workers, scripts)
4. Read infrastructure config (Docker, k8s, terraform, compose) for runtime topology
5. Identify data stores from config and dependency declarations
6. Identify external integrations from env-var examples and SDK imports
7. Look for boundary signals (what's in scope vs out — package boundaries, separate apps, vendored code)
8. For `extend` mode: read EXISTING_CONTENT and identify gaps
9. Synthesize findings (grouped by section)
10. Draft the proposed content
11. Return findings + proposed_content to the controller

## Step 1: Top-Level Layout

Run a tree-like listing of the repo's top 2-3 levels. Note:

- Source dirs (`src/`, `lib/`, `app/`, language-specific layouts)
- Service dirs (`services/`, `apps/`, `packages/`)
- Infra dirs (`infra/`, `terraform/`, `k8s/`, `docker/`, `deploy/`)
- Docs dirs (`docs/`, `documentation/`)
- Test dirs (`tests/`, `test/`, `__tests__/`, `spec/`)
- Generated / vendored (`node_modules/`, `vendor/`, `target/`, `build/`, `dist/` — usually ignore)

If you see multiple service-like subdirs (e.g., `services/billing/`, `services/checkout/`), this is a multi-service repo even if not formally a monorepo. Note that.

## Step 2: Build / Dependency Files

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

## Step 3: Entry Points

Identify them by looking for:
- `main`, `index`, `app`, `server`, `cli` files at common paths (`src/main.*`, `src/index.*`, `cmd/<name>/main.go`, `app/main.py`, etc.)
- Build outputs declared in `package.json`'s `bin` field or `scripts.start` / `scripts.dev`
- Worker / job entry points (look for `worker.*`, `job.*`, `cron.*`, or queue-consumer code patterns)
- CLI entry points (look for `argparse`/`clap`/`commander`/`click` imports)

For each entry point, one-line description: what process does it run? When is it invoked?

## Step 4: Runtime Topology

Read:
- `Dockerfile` and `Dockerfile.*` variants — what runtime is the prod artifact?
- `docker-compose.yml` and `docker-compose.*.yml` — local dev topology
- `k8s/*.yaml`, `manifests/*.yaml` — production topology
- `terraform/*.tf`, `pulumi/*.py`, `cdk/*.ts` — infrastructure-as-code
- `Procfile` — Heroku-style services
- `fly.toml`, `render.yaml`, `vercel.json`, `netlify.toml` — PaaS configs
- `serverless.yml`, `sam.yaml` — serverless

Extract: what processes run? Where? How do they communicate (HTTP, queues, RPC)? Is there a load balancer / API gateway / reverse proxy in front?

## Step 5: Data Stores

Look for:
- DB drivers in dependency lists: `pg`, `mysql2`, `psycopg`, `sqlx`, `gorm`, `prisma`, `mongoose`, `mongodb`, `redis`, etc.
- Connection-string env vars: `DATABASE_URL`, `REDIS_URL`, `KAFKA_BROKERS`, etc.
- Migration directories: `migrations/`, `db/migrations/`, `prisma/migrations/`
- `docker-compose.yml` services like `postgres`, `redis`, `clickhouse`, `kafka`, `rabbitmq`

For each store, one-line purpose: what does this codebase use it for? (Don't guess if not obvious — note "purpose unclear from config alone".)

## Step 6: External Integrations

The fastest signal: `.env.example` / `.env.sample`. List the third-party services hinted at by env-var names:
- `STRIPE_*` → Stripe (payments)
- `SENDGRID_*` / `MAILGUN_*` / `RESEND_*` → email
- `OPENAI_*` / `ANTHROPIC_*` → LLM APIs
- `AWS_*` → AWS (S3, SQS, etc.)
- `SENTRY_*` / `DATADOG_*` → observability
- `AUTH0_*` / `CLERK_*` / `OKTA_*` → identity
- `TWILIO_*` → SMS/voice

Cross-reference with SDK imports in source (`import Stripe from 'stripe'`, etc.) to confirm.

## Step 7: Boundary Signals

What's in scope for this codebase vs out:

- Monorepo with multiple apps → list which apps are part of this overview
- Vendored code in `vendor/` or `third_party/` → out of scope (don't describe it)
- Generated code (e.g., from OpenAPI schemas) → identify but don't describe internals
- External API contracts that this codebase implements vs depends on
- Anything explicitly documented as "this lives in another repo"

## Step 8: Mode Handling

**For `create` mode:** ignore EXISTING_CONTENT. Build the full proposal.

**For `extend` mode:** read EXISTING_CONTENT and identify which of the six sections are missing, outdated, or incomplete. Your proposal is **additions or refinements** — don't restate what's already there accurately.

**For `replace` mode:** ignore EXISTING_CONTENT. Build the full proposal fresh.

## Step 9: Synthesize Findings

Group findings by section. Terse bullets:

```
## Findings

### Layout
- 3 top-level service dirs: services/{billing,catalog,checkout}
- Single `infra/terraform/` for AWS deployment
- Tests live alongside source as `*.test.ts` and `*.spec.ts`

### Build / language
- TypeScript (5.4) across all services
- pnpm workspace at root
- Per-service `package.json` declares Express + Prisma
- Shared `packages/common/` for cross-service utilities

### Entry points
- services/billing/src/server.ts — HTTP API
- services/checkout/src/server.ts — HTTP API
- services/catalog/src/server.ts — HTTP API
- services/billing/src/workers/retry-queue.ts — background worker (BullMQ)

### Topology
- docker-compose.yml: postgres, redis, three service containers, nginx
- k8s/: same shape in production; ingress in front of services

### Data stores
- Postgres (Prisma ORM) — main relational store; per-service schemas
- Redis (ioredis + BullMQ) — queues for billing-retry; session store for checkout

### External integrations
- Stripe (STRIPE_SECRET_KEY in .env.example, `stripe` package in billing/)
- SendGrid (SENDGRID_API_KEY, used in checkout/ for receipts)
- Sentry (SENTRY_DSN across all services)

### Boundaries
- `vendor/` contains a pinned fork of `kafkajs` — treated as external
- Catalog data is read from an upstream service (`UPSTREAM_CATALOG_URL`); this repo owns the cache but not the source

### Existing content (extend mode only)
- Covers: layout, build, entry points
- Missing: topology details, integrations beyond Stripe, boundaries
```

## Step 10: Draft Proposed Content

For `create` and `replace` modes, the six-section template:

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

For `extend` mode: the proposed_content is the diff or the specific sections to add/refine. Mark which sections are new vs which are updates, so the controller can splice intelligently.

**Drafting guidelines:**

- One paragraph for the system summary, not a wall of text
- Component list capped at ~10 entries; if you have more, the components are too granular — group
- Use real component names from the codebase, not generic terms
- For runtime topology: describe what's there, not what should be there. If it's a monolith, say "monolith" — don't dress it up
- For data stores: write the access pattern only if you observed it (read-heavy DB query, ephemeral redis cache). Don't infer.
- For external integrations: only list confirmed integrations (env-var + SDK import), not "potentially uses X"
- Boundaries section is often the most useful — be explicit about what's NOT in this repo

## Step 11: Return to the Controller

```
## Findings

<from Step 9>

## Proposed content

<for create/replace: the full architecture markdown>
<for extend: the specific sections/diffs to add>

## Notes for the controller

<caveats, smells you noticed, low-confidence calls, places where the
architecture is unclear from code alone>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Adding a Mermaid/PlantUML/C4 diagram | Text only — no diagram syntax of any kind |
| Inventing topology not visible in code | If it's not in `Dockerfile`/k8s/etc., don't claim it exists |
| Restating package.json contents | Architecture overview ≠ dependency list |
| Lengthy component list (15+ entries) | Group; the goal is "main moving parts" not exhaustive enumeration |
| Code snippets in the architecture file | Almost never appropriate; if used, ≤3 lines |
| Vague "uses cloud services for storage" | Name the service: "S3 for object storage" |
| Aspirational architecture ("we're moving to ...") | Document the current state; transitions belong in ADRs |
| Skipping the Boundaries section because "everything is in scope" | If everything is in scope, say so explicitly with examples of what would be out |

## Red Flags

- About to write a Mermaid diagram → STOP; no diagrams
- About to write a file → STOP; controller writes
- About to ask the user a question → STOP; controller handles user discussion
- About to dispatch a subagent → STOP; you are a leaf
- About to claim a service exists when only its env var is set → STOP; require SDK import OR docker-compose entry OR k8s manifest
- About to inflate findings to look thorough → STOP; terse beats thorough here
