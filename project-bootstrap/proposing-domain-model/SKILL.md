---
name: proposing-domain-model
description: Use as a dispatched subagent to deeply analyze a project's models, schemas, and tests, and propose a domain model (3-15 entities with attributes, relationships, lifecycles). Read-only. Returns findings + proposed markdown to the dispatching coordinator.
---

# Proposing Domain Model

## Overview

You were dispatched by `bootstrapping-project` to analyze a project's data layer, type definitions, and test fixtures, then propose content for `docs/DOMAIN.md` — a conceptual model of 3-15 core entities, each with attributes, relationships, and lifecycle states.

**Core principle:** The domain model captures the **conceptual shape** of the data, not the database schema. Attributes are conceptual ("amount", "customer", "lifecycle state"), not implementation ("INT NOT NULL DEFAULT 0", "FK references customers(id)"). The audience is someone reasoning about how the business logic fits together, not someone designing a DB migration.

**Operating mode:** STRICTLY READ-ONLY. You do NOT write files; you do NOT modify config; you do NOT interact with the user; you do NOT dispatch sub-subagents.

**Announce at start:** "I'm using the proposing-domain-model skill to analyze this project."

## Hard Gates

- Do NOT write any file — return content to the controller; the controller writes
- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.
- Do NOT include DB-specific details (column types, indexes, FKs as such) — conceptual only
- Do NOT use ER-diagram syntax, Mermaid, or any diagram syntax — text only
- Do NOT exceed 15 entities — fewer load-bearing entities beat a long list
- Do NOT include every enum value — only lifecycle states that matter

## Inputs from the Dispatcher

- `REPO_ROOT` — absolute path to the repository root
- `MODE` — one of `create`, `extend`, `replace`
- `EXISTING_CONTENT` — verbatim current content of `docs/DOMAIN.md` (only for `extend`/`replace`; empty otherwise)
- `FILE_PATH` — where the file will be written

## Checklist

1. Read database schemas / migrations to inventory tables
2. Read ORM model / type-definition files for the same entities
3. Read test fixtures and factory definitions — they often reveal "what does a realistic entity look like"
4. Identify lifecycle states from enums and state-machine code
5. Identify relationships (associations, foreign keys) — translate to conceptual cardinality
6. Filter to 3-15 core entities (drop join tables, audit logs, system-level entities)
7. For `extend` mode: read EXISTING_CONTENT and identify gaps
8. Draft per-entity sections
9. Return findings + proposed_content to the controller

## Step 1: Database Schema Discovery

Look for:
- `migrations/`, `db/migrations/`, `prisma/schema.prisma`, `schema.rb`, `schema.sql`
- ORM definitions: `models/*.{ts,py,rb,go}`, `entities/*.{ts,java,cs}`, `prisma/schema.prisma`
- TypeORM/Sequelize decorators in source
- SQLAlchemy / Django ORM model classes

Inventory: every table or model class. For each, capture:
- Name (canonical, singular)
- Attribute list (conceptual — strip type implementation details)
- Indicators of lifecycle (a `status` field, `state` enum, etc.)
- Foreign-key columns (sources for relationship inference)

## Step 2: Type Definitions

For typed languages: read the type definitions that mirror the DB models. These often reveal:
- Optional vs required attributes (`?` in TS, `Optional[]` in Python, `Option<>` in Rust)
- Derived / computed properties (sometimes implemented as getters)
- Domain-specific types (`Money`, `Email`, `UUID`) — note these; they're worth mentioning in attribute descriptions

## Step 3: Test Fixtures

Look at `tests/fixtures/`, `factories/`, `seeds/`, `tests/factories.ts`, etc. Factories show what a typical instance looks like:
- Default attribute values reveal the "happy path" shape
- Trait definitions (FactoryBot, factory_bot, factory_boy) reveal common variants
- Test setup code reveals which attributes matter in practice vs which are vestigial

Example signal: a User factory only ever sets `email`, `name`, `tenant_id`. That suggests the User's load-bearing conceptual attributes are those three, even if the table has 20 columns.

## Step 4: Lifecycle States

Search for state-machine code:
- `status` or `state` columns/fields
- Enum definitions: `enum OrderStatus { Pending, Settled, Refunded }`
- State-machine libraries: `xstate`, `statesman`, `aasm`, `transitions`
- Transition code: `if (status === 'pending')`, `order.transition_to('settled')`, etc.

For each entity with lifecycle states:
- List the states
- Identify the typical transitions (from → to)
- Note any "terminal" states (states with no outgoing transitions)

## Step 5: Relationships

For each entity, read its FK declarations / associations:
- `has_many`, `belongs_to`, `has_one` (Ruby/Rails)
- `@OneToMany`, `@ManyToOne` (TypeORM, JPA)
- `relations: { customer: { ... } }` (Prisma)
- `models.ForeignKey(...)` (Django)

Translate to conceptual cardinality:
- "An Order belongs to one Customer; a Customer has many Orders."
- "A Quote has exactly one Settlement (once settled); a Settlement belongs to exactly one Quote."

**Drop join tables and pure-association tables.** Don't list `OrderItem` as a top-level entity unless it carries its own meaningful attributes beyond linking Order ↔ Item.

## Step 6: Filter to 3-15 Core Entities

Your inventory from Step 1 may have 30+ tables. Cut hard:

**Drop:**
- Join tables / association tables with no own attributes
- Audit log / event log tables (mention as "audit logs are kept separately" in the intro, don't list)
- Session / token / cache tables (system-level, not domain)
- Generated tables (search indices, materialized views)
- Settings / config tables (unless they're first-class domain concepts)

**Keep:**
- Entities that have lifecycle states
- Entities that participate in business rules (have functions named after them, e.g., `settle_quote`, `reconcile_payment`)
- Entities that show up in test fixtures consistently
- Entities mentioned in the README or top-level docs

Aim for 3-15. If you're below 3, the domain is too small for a separate domain model — flag in findings. If you're above 15, group / drop the less central ones.

## Step 7: Mode Handling

**For `create` mode:** ignore EXISTING_CONTENT. Build the full proposal.

**For `extend` mode:** read EXISTING_CONTENT and identify which entities are already documented, which are missing, and which have stale information. Propose additions / refinements.

**For `replace` mode:** ignore EXISTING_CONTENT. Build a fresh proposal.

## Step 8: Synthesize Findings

```
## Findings

### Inventoried tables (from schema)
- 27 tables total in prisma/schema.prisma
- 9 are audit/event log tables (omitted)
- 4 are association-only join tables (omitted)
- Remaining 14 are candidate entities

### High-confidence core entities (in models, tests, business logic)
- Customer — models/Customer.ts, factories.ts, /api/customers
- Quote — models/Quote.ts, factories.ts (3 trait variants), state machine in jobs/quote-lifecycle.ts
- RFQ — models/RFQ.ts, /api/rfqs, has lifecycle Pending → Quoted → Closed
- Order — models/Order.ts, factories.ts, /api/orders, has lifecycle Open → Settled → Refunded
- Settlement — models/Settlement.ts, jobs/settle-quotes.ts, has FK to Quote and to PaymentMethod
- PaymentMethod — models/PaymentMethod.ts, /api/payment-methods, no lifecycle

### Candidate entities (less central)
- DiscountCode — has its own table; only used in 2 places; might be worth including
- Webhook — system-level; suggest dropping

### Existing domain model (extend mode only)
- Covers: Customer, Quote, Order
- Missing: RFQ, Settlement, PaymentMethod
- Inaccurate: Order lifecycle says only Open → Settled; code has Open → Settled → Refunded
```

## Step 9: Draft Proposed Content

For `create` and `replace` modes:

```markdown
# Domain Model

<Optional one-paragraph intro describing the domain at a high level —
what kind of system this is, what the entities collectively represent.
Helps orient readers before they dive into the per-entity sections.>

## <Entity Name>

<One paragraph: what this entity represents in the domain. Plain language,
not technical.>

**Key attributes:**
- <attribute-name> — <one-line meaning>
- <attribute-name> — <one-line meaning>
(3-10 attributes; conceptual, not DB columns)

**Relationships:**
- <One per line, with cardinality. E.g., "Has many `<OtherEntity>`s — each
  `<OtherEntity>` belongs to exactly one `<EntityName>`.">

**Lifecycle:** (only if this entity has meaningful states)
- States: `Pending` → `Settled` → `Refunded`; or `Pending` → `Expired`
- Notes: <one or two short lines about non-obvious transitions or terminal states>

## <Next Entity>

...
```

For `extend` mode: the proposed_content is the new entity sections plus any refinements to existing ones (clearly marked as "REFINE: Order lifecycle" or similar).

**Drafting guidelines:**

- "What it represents" paragraph: write as if explaining to a new team member, not a DBA
- Attributes: name + ≤1-line meaning. NO data types (`int`, `string`, `DateTime`). NO nullability annotations. NO column-level constraints.
- Relationships: include cardinality (`has many`, `belongs to`, `has exactly one`). State the direction both ways if non-obvious.
- Lifecycle: only include for entities that have state machines. Don't invent lifecycles where none exist.
- Length per entity: aim for 8-15 lines. Concise.
- Order entities thoughtfully: usually start with the most central / most-referenced (e.g., Customer or Account first), then dependents.

**Example entry:**

```markdown
## Quote

A price commitment given to a customer in response to an RFQ, valid until
its expiry timestamp. Once accepted, it can be settled via the configured
payment method.

**Key attributes:**
- ID — opaque identifier
- Amount — total committed price (in customer's currency)
- Currency — ISO 4217 currency code
- Expiry — timestamp after which the quote is no longer honorable
- Owner — the customer the quote was issued to

**Relationships:**
- Belongs to one Customer (the recipient)
- Belongs to one RFQ (the request that produced it)
- Has at most one Settlement (created on acceptance; never replaced)

**Lifecycle:** Pending → Accepted → Settled (terminal), OR
Pending → Expired (terminal, automatic after Expiry timestamp).
```

## Step 10: Return to the Controller

```
## Findings

<from Step 8>

## Proposed content

<for create/replace: the full domain model markdown>
<for extend: new entity sections plus marked refinements>

## Notes for the controller

<caveats: borderline entities you dropped, lifecycle ambiguities, places
where the model in code doesn't match the model implied by the README>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Including DB column types (`VARCHAR(255)`, `INT NOT NULL`) | Conceptual attributes only — no implementation details |
| Adding a Mermaid/ER diagram | Text only — no diagram syntax of any kind |
| Listing every table including join/audit/session tables | Filter to core domain — drop infrastructure-level tables |
| Listing every enum value as a lifecycle state | Only include lifecycle states with meaningful transitions |
| Lengthy entity descriptions (full-paragraph attributes) | One-line meaning per attribute; ≤2 sentences for "what it represents" |
| 20+ entities | Filter — the goal is the load-bearing ones, not an exhaustive table dump |
| Restating schema layout | Schema ≠ domain model; describe meaning, not structure |
| Forgetting to state cardinality on relationships | "Has many X" / "belongs to one X" — always state cardinality |

## Red Flags

- About to draw an ER diagram → STOP; no diagrams
- About to write a file → STOP; controller writes
- About to ask the user a question → STOP; controller handles user discussion
- About to dispatch a subagent → STOP; you are a leaf
- About to list `VARCHAR`/`INT`/`UUID` as types → STOP; conceptual only
- About to include the `audit_logs` or `sessions` table → STOP; system-level, not domain
- About to invent a lifecycle the code doesn't have → STOP; observe, don't speculate
