---
name: ss-bs-discovering-domain-model
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the domain slot. Inventories tables, ORM models, type defs, test fixtures, and state-machine code; then asks the user to pick the ≤15 load-bearing entities, confirm lifecycles, resolve relationship cardinality, and capture workflow exceptions the schema doesn't show. Writes docs/DOMAIN.md (or the configured path) atomically.
---

# Discovering Domain Model

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). A domain model captures the **conceptual shape** of the data — what each entity represents, how they relate, what lifecycles they go through. The schema reveals tables, columns, and FKs; the code reveals state-machine transitions and business operations; but only the user can confirm which entities are load-bearing for newcomers vs. infrastructure noise, resolve ambiguous cardinality, and surface workflow exceptions the schema doesn't show (e.g., "an Order can be returned even after fulfilled"). A subagent could surface candidates from one read pass but couldn't have the back-and-forth needed to settle the cut list and the rules. So this skill stays in the coordinator's context.

**Core principle:** Attributes are conceptual ("amount", "expiry", "owner"), not implementation ("INT NOT NULL", "FK references customers(id)"). The audience is someone reasoning about how the business logic fits together, not someone designing a DB migration.

**Announce at start:** "I'm using the ss-bs-discovering-domain-model skill to build docs/DOMAIN.md with you."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for domain model. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, `replace`, or `audit`. Audit invokes the drift-check path (Step 1.6) and the drift-resolution Q0 in Step 3.
- `EXISTING_CONTENT` — verbatim current `docs/DOMAIN.md` content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/DOMAIN.md`; honors `context.domain_path` config override if non-default)
- **`SUGGEST`** — `on` or `off`. When `on`, run Step 1.5 (silent diagnose) and surface Q1.5 in Step 3. When `off`, skip both — identical to pre-suggestion-pass behaviour. Defaulted by the coordinator from `suggest.default` in config and the opt-in question at bootstrap start. Always `on` in audit mode.

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text only for genuinely open prompts (workflow exceptions, custom lifecycle additions).
- Do NOT use Mermaid, C4, PlantUML, ER-diagram syntax, or any other diagram syntax in the proposed domain model — text only.
- Do NOT dispatch subagents. You're inline — you do the work.
- Do NOT include DB-specific details (column types, indexes, FKs as such) — conceptual only.
- Do NOT exceed 15 entities in the final draft — fewer load-bearing entities beat a long list.
- Do NOT include every enum value as a lifecycle state — only states with meaningful transitions.
- Do NOT overwrite an existing domain model in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT invent lifecycles, attributes, or relationships not visible in the code OR explicitly stated by the user.
- Do NOT loop past 3 tweak iterations without surfacing bail options to the user.
- In audit mode, do NOT skip Step 1.6 (drift check). It's the third operation alongside observe and diagnose; without it, audit is just "extend mode with SUGGEST=on".
- In audit mode, ask Q0 questions ONE drift item per question — do NOT bundle. Drift resolutions are nuanced individually.
- In audit mode, SUGGEST is always treated as `on` (regardless of input). This is documented in the Inputs section.
- Do NOT exceed the diagnose budget: Step 1.5 (when run) takes at most ~2 minutes of agent work and reads at most 10 additional files beyond what Step 1 read. If you need more reads, surface fewer suggestions instead of widening the budget.
- Do NOT surface diagnose candidates without specific file-path or count evidence. Abstract "best practice" suggestions are forbidden.
- Do NOT pad the Q1.5 list to fill a quota. If diagnose finds 0 strong candidates, Q1.5 is skipped silently — this is the correct outcome, not a bug.
- Do NOT use severity MUST for a diagnose candidate unless there is observable harm (broken tests, security risk, observed bug pattern). Weaker evidence defaults to SHOULD or INFO.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (schemas, models,      │
│             fixtures, state machines, relationships)│
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
├─────────────────────────────────────────────────────┤
│ MODE = audit                                        │
│   → Step 1: silent code scan                        │
│   → Step 1.5: silent diagnose (always on for audit) │
│   → Step 1.6: drift check vs EXISTING_CONTENT       │
│   → Step 2: announce findings + drift + diagnoses   │
│   → Step 3: Q0 (drift resolution) → Q1 → Q1.5 → ...│
│   → Step 4-6: as usual                              │
└─────────────────────────────────────────────────────┘
```

## Step 1: Code Scan (Silent — No User Narration Yet)

Read all of the following that exist. Don't narrate progress to the user — this happens silently, then you announce findings once in Step 2.

### 1a. Database schema discovery

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

### 1b. Type definitions

For typed languages: read the type definitions that mirror the DB models. These often reveal:
- Optional vs required attributes (`?` in TS, `Optional[]` in Python, `Option<>` in Rust)
- Derived / computed properties (sometimes implemented as getters)
- Domain-specific types (`Money`, `Email`, `UUID`) — note these; they're worth mentioning in attribute descriptions

### 1c. Test fixtures

Look at `tests/fixtures/`, `factories/`, `seeds/`, `tests/factories.ts`, etc. Factories show what a typical instance looks like:
- Default attribute values reveal the "happy path" shape
- Trait definitions (FactoryBot, factory_bot, factory_boy) reveal common variants
- Test setup code reveals which attributes matter in practice vs which are vestigial

Example signal: a User factory only ever sets `email`, `name`, `tenant_id`. That suggests the User's load-bearing conceptual attributes are those three, even if the table has 20 columns.

### 1d. Lifecycle states

Search for state-machine code:
- `status` or `state` columns/fields
- Enum definitions: `enum OrderStatus { Pending, Settled, Refunded }`
- State-machine libraries: `xstate`, `statesman`, `aasm`, `transitions`
- Transition code: `if (status === 'pending')`, `order.transition_to('settled')`, etc.

For each entity with lifecycle states:
- List the states
- Identify the typical transitions (from → to)
- Note any "terminal" states (states with no outgoing transitions)
- Flag ambiguous transitions (states that could be reached from multiple sources) for Q2

### 1e. Relationships

For each entity, read its FK declarations / associations:
- `has_many`, `belongs_to`, `has_one` (Ruby/Rails)
- `@OneToMany`, `@ManyToOne` (TypeORM, JPA)
- `relations: { customer: { ... } }` (Prisma)
- `models.ForeignKey(...)` (Django)

Translate to conceptual cardinality:
- "An Order belongs to one Customer; a Customer has many Orders."
- "A Quote has exactly one Settlement (once settled); a Settlement belongs to exactly one Quote."

**Drop join tables and pure-association tables.** Don't list `OrderItem` as a top-level entity unless it carries its own meaningful attributes beyond linking Order ↔ Item.

Flag ambiguous cardinality (e.g., two FKs that could be 1:1 or 1:N depending on uniqueness constraints) for Q3.

### 1f. Pre-filter to candidate entities

Your inventory from Step 1a may have 30+ tables. Pre-filter to a candidate list (the user makes the final cut in Q1):

**Drop automatically:**
- Join tables / association tables with no own attributes
- Audit log / event log tables (mention as "audit logs are kept separately" in the intro, don't list)
- Session / token / cache tables (system-level, not domain)
- Generated tables (search indices, materialized views)
- Settings / config tables (unless they're first-class domain concepts)

**Keep as candidates:**
- Entities that have lifecycle states
- Entities that participate in business rules (have functions named after them, e.g., `settle_quote`, `reconcile_payment`)
- Entities that show up in test fixtures consistently
- Entities mentioned in the README or top-level docs

Aim for a candidate list of ≤25 (you'll trim to ≤15 with the user). If you have <3 candidates, the domain may be too small for a separate domain model — flag in the Step 2 announce.

### 1g. Mode-specific reads

- **`create` mode:** ignore `EXISTING_CONTENT` (it's empty). Build candidate list from scratch.
- **`extend` mode:** read `EXISTING_CONTENT` and identify which entities are already documented, which are missing, and which have stale information (e.g., the existing doc says Order lifecycle is Open → Settled but the code has Open → Settled → Refunded). Flag conflicts for Q4.
- **`replace` mode:** ignore `EXISTING_CONTENT`. Build candidates fresh.

### 1h. Compile candidates in memory

For each candidate entity, hold:
- Name + draft "what it represents" paragraph (lifted from comments where possible)
- Load-bearing attributes (from fixtures + type defs)
- Detected lifecycle states (or `null` if no state machine)
- Detected relationships with cardinality
- Open questions: ambiguous lifecycle transitions, ambiguous cardinality, missing context from code

## Step 1.5: Silent Diagnose (only if `SUGGEST=on`)

If `SUGGEST=off`, skip this step entirely and proceed to Step 2.

Diagnose looks for domain-modeling anti-patterns and missing-but-typically-valuable structural decisions. Every diagnose finding must be **evidence-cited** with specific file paths or concrete counts. Abstract "you should do X" findings are not allowed.

### 1.5a. Domain model diagnose categories

For each category below, scan additional files if needed (within the budget — see Hard Gates). Scan each category for candidates. One strong candidate per category is the target; the aggregate cap of 5 is enforced in 1.5b after dropping unsupported candidates.

- **God entities (too many attributes / relationships).** An entity (DB table or class) with >15 attributes or >5 outgoing relationships. Evidence: schema file + attribute count.
- **Anemic models (entities with no behaviour).** An entity used only as a data bag — all logic lives in services that operate on it. Evidence: entity definition + count of service files that mutate it externally.
- **Missing aggregate roots.** Three or more entities with a clear ownership hierarchy (e.g., `Order`, `OrderItem`, `OrderEvent`) all defined as top-level entities with no aggregate-root documentation. Evidence: list the entities + the ownership signal (foreign keys, embedded relationships).
- **Undocumented state machines.** An entity has 4+ distinct status values used in code (case statements, enum values, status string comparisons) with no documented transitions. Evidence: file paths showing the status values.

### 1.5b. Compile candidate suggestions in memory

Each candidate must include:
- `severity`: one of `MUST`, `SHOULD`, `INFO` — see Hard Gates for the matching evidence bar
- `title`: one-line headline (e.g., "Document Order aggregate root boundary")
- `evidence`: specific file paths or counts (e.g., `prisma/schema.prisma:45, src/models/order.ts:12, src/services/order-service.ts:88`)
- `proposed_addition`: exact markdown text to add to the artifact (a new entity section, a lifecycle note, or a relationships clarification)

Drop any candidate that cannot be cited with specific evidence. Drop any candidate where the severity guess cannot be justified from the evidence (no MUST without observable harm).

If more than 5 candidates remain after dropping unsupported ones, rank by:
1. Severity (MUST > SHOULD > INFO)
2. Evidence count (more file paths / higher counts = stronger)
3. Impact (changes that prevent bugs > changes that improve consistency)

Surface the top 5. If 0 candidates remain, the candidate list is empty and Q1.5 in Step 3 is skipped silently.

## Step 1.6: Drift Check (only if `MODE=audit`)

Compare each entry in `EXISTING_CONTENT` against current code state. The goal is to detect entries that have gone stale.

### 1.6a. Drift categories for domain-model

For each domain-model entry, check:

- **Entity removed.** A documented entity has no matching DB table, ORM model, or type definition in current code. Evidence: search results.
- **Entity added (undocumented).** A new DB table or ORM model exists with no corresponding entity in DOMAIN.md. Evidence: schema file paths.
- **Lifecycle states drift.** A documented entity's state list `{Draft, Submitted}` vs current code's enum `{Draft, Submitted, Cancelled, Shipped}`. Evidence: enum file path.
- **Relationship cardinality drift.** Doc says `User 1:N Order`; current FK is unique (1:1) or has been moved to a join table (N:N). Evidence: schema diff.
- **Provenance re-evaluation.** Each suggestion-added entity / lifecycle — does the code now match the documented model?
  - If the original evidence pattern (e.g. "undocumented state machine in src/models/order.ts:44") is STILL present, the suggestion is still aspirational — flag as INFO drift "still not enforced after N days".
  - If the original evidence pattern is GONE (the code has changed to match the aspiration), flag as INFO drift "aspiration met — provenance marker can be removed and entry promoted to normal".

### 1.6b. Compile drift findings in memory

Each finding: `kind` (entity-removed / entity-added / lifecycle-drift / cardinality-drift / aspiration-met / aspiration-still-pending), `entry` (the doc text being challenged), `evidence` (file paths showing the current code state).

No cap on drift findings — every observable drift is surfaced. The user resolves each in Q0.

## Step 2: Announce Findings

One short message (3-6 sentences; 3-7 when SUGGEST=on extends with the diagnose-mention sentence). Example:

> "Here's what I picked up: 27 tables in `prisma/schema.prisma`. After dropping audit logs and join tables, I have 14 candidate entities. Strongest signals: Customer, Quote, RFQ, Order, Settlement (all with lifecycle state machines and consistent test fixtures). A few I want your call on — DiscountCode (only used in 2 places, might be too edge-case), and the cardinality between Order and PaymentMethod (could be 1:1 or 1:N from the schema alone). I'll ask, then show you a draft."

If `SUGGEST=on` AND Step 1.5 produced ≥1 candidate, extend the announcement with: "…and I noticed a few domain-modeling clarifications worth documenting — I'll surface those after we confirm the observed entities."

If `create` mode and the candidate list is <3:
> "I didn't find much domain shape — fewer than 3 candidate entities after filtering. The project may be too early or too thin for a separate domain model. Want to continue with what I found, or skip?"

If `extend` mode:
> "Your existing domain model covers [N] entities. I scanned and found [M] missing candidates (and [K] entities where the existing lifecycle / relationships look stale). I'll ask about those, then propose additions / refinements."

If `MODE=audit`: "Audit mode. Scan + diagnose + drift check complete. Found N drift items (X entity changes, Y lifecycle/cardinality changes, Z provenance re-evaluations) — I'll surface those first in the questions, then walk through observed candidates and suggestions as usual."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan and (for extend mode) the existing file already answered it.

### Q0 — Drift Resolution (only if `MODE=audit` AND Step 1.6 produced ≥1 drift finding)

Ask one question per drift finding (do NOT bundle — drift items often have nuanced individual resolutions):

```
Question: "Drift detected: <entry summary>. Current code state: <evidence>. What's the right resolution?"

Options:
  - "Update the doc to match code"
  - "Keep the doc — code is wrong / will be fixed"
  - "Remove the entry — no longer applies"
  - "Both — clarify scope (split into multiple entries)"
```

For **provenance re-evaluation** findings, the question is different:

```
Question: "Aspirational entry '<title>' was added on <date>. Evidence at that time: <original evidence>. Current code state: <current evidence>. Has this aspiration been realized?"

Options:
  - "Yes — code has caught up. Remove the provenance marker (promote to normal)."
  - "No — code still has the original problem. Keep as aspirational; refresh the marker date."
  - "Drop the entry — we've decided not to pursue this aspiration."
```

Record each resolution. Apply during Step 4 (Draft Synthesis).

### Q1 — Entity selection (multi-select)

The most important question. Present the candidate list with a one-line role description each, grouped by signal strength.

```
Question: "I found these candidate entities in your schemas, models, and fixtures. Which are the load-bearing domain entities? (Cap is 15.)"

Multi-select. Group options as:
- Core (has lifecycle + appears in business logic + fixtures): [list]
- Supporting (has fixtures + relationships but no lifecycle): [list]
- Edge cases (sparse use; you may want to include or drop): [list]

Recommended option:
- "All Core + Supporting (Recommended)" — if combined is ≤15
- Or: "Core only" — if total is otherwise too many
- Or: "All of the above" — if total ≤15 after filtering
```

If the user selects >15, immediately follow up:

```
Question: "That's more than 15. Which should I drop?"
Multi-select from the over-cap list.
```

### Q1.5 — Confirm suggested additions (only if `SUGGEST=on` AND Step 1.5 produced ≥1 candidate)

```
Question: "Here are some things I'd suggest adding even though they're
not currently codified. These are opinionated — pick any you want to
include:"

Options (multi-select, one option per Step 1.5 candidate, plus a "None" escape):
  - [suggestion · <severity> · <evidence-summary>] <title>
    Evidence: <evidence>
    Proposed addition: <one-line summary of proposed_addition>
  - ... (one option per remaining candidate, up to 5)
  - "None of these — keep the domain model descriptive only"

Use the harness's multi-select question tool. Do not present as plain text.
```

If the user picks none, treat as "no suggestions accepted" and proceed to Q2. Accepted suggestions are carried into Step 4 (Draft & Show) and rendered with provenance markers.

### Q2 — Lifecycle confirmation (per entity with detected states, multi-choice)

For each entity with a detected lifecycle, confirm completeness:

```
Question: "[Entity X] has these lifecycle states from the code: [list]. Is that the full set?"

Options:
  - "Yes — complete"
  - "Missing a state (I'll specify which)" → free-form follow-up
  - "Some are redundant (I'll specify which)" → free-form follow-up
  - "No lifecycle for this entity — the state field is vestigial"
```

Cap this loop at the number of selected entities with detected lifecycles. If a user picks "Missing"/"Redundant", capture the free-form text and apply to the draft.

### Q3 — Relationship cardinality (per ambiguous relationship, multi-choice)

For each ambiguous relationship flagged in Step 1e:

```
Question: "[Entity A] ↔ [Entity B] — what's the cardinality?"

Options:
  - "[A] has many [B]"
  - "[A] has one [B]"
  - "Many-to-many (via join table)"
  - "Not a direct relationship — they touch the same parent but don't reference each other"
```

Cap this loop at 5 ambiguous relationships; if more, ask the user to scan and confirm the list themselves.

### Q4 (extend mode only) — Resolve lifecycle/relationship conflicts

If Step 1g flagged contradictions between `EXISTING_CONTENT` and current code, ask the user how to resolve each:

```
Question: "Your existing domain model says '[Entity X]: <existing lifecycle/relationship>', but the code now shows '<observed>'. What's the right resolution?"

Options:
  - "Update to match current code"
  - "Keep existing — the code is in violation"
  - "Drop entirely — it no longer applies"
  - "Document both (I'll clarify why)" → free-form follow-up
```

### Q5 — Workflow exceptions (free-form)

```
Question: "Any non-obvious workflow rules the schema doesn't show? Examples:
- 'An Order can be returned even after Fulfilled — creates a Reversal'
- 'A User can be reactivated within 30 days of deletion'
- 'An Invoice is immutable once sent — corrections create a new Invoice'
- 'A Quote auto-expires after the Expiry timestamp via a cron job'

Free-form text. List each rule on its own line, or skip if there are none."
```

These get woven into the relevant entity's "what it represents" paragraph or lifecycle notes.

## Step 4: Draft & Show to User

Synthesize the draft using:
- Selected entities from Q1
- Accepted Q1.5 suggestions, rendered as new entity sections with provenance markers (format defined in Step 6's provenance subsection). **The provenance markers must appear in the draft shown to the user at this Step 4**, not added silently at Step 6 write time — the user reviews and approves the full content including provenance.
- Confirmed/refined lifecycles from Q2
- Confirmed cardinalities from Q3
- Conflict resolutions from Q4 (extend mode)
- Workflow exceptions from Q5
- Q0 drift resolutions (per drift item: update / keep / remove / clarify)
- Q0 provenance re-evaluations (per aspirational entry: promote / refresh / drop)

Use the canonical template (see Output Template section). Order entities thoughtfully — usually start with the most central / most-referenced (e.g., Customer first), then dependents. Show the full draft to the user, then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip this file"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture user's free-form notes (often "rewrite the Settlement attributes — drop currency, add settlement_provider" or "move RFQ above Quote in ordering"); apply; re-show; re-ask Step 4. Cap at **3 iterations**:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip the domain model for now, or
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

For **extend** mode: merge `EXISTING_CONTENT` + the new entity sections / refinements into a single document, then write atomically. Preserve existing accurate entries; replace only the sections flagged in Q4.

Report to the coordinator one of:

- `created` (mode = create, full draft written)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

### Provenance markers for accepted Q1.5 suggestions

Each accepted Q1.5 suggestion becomes a new entity section in the artifact. Append a provenance block at the end of the Entity section using this exact format:

```markdown
## <Entity Name>

**Attributes:** <list>

**Lifecycle:** <states>

**Relationships:** <list>

> _Added via bootstrap suggestion pass (YYYY-MM-DD)._
> _Evidence: <evidence summary from the Q1.5 candidate>._
> _This entity / lifecycle is observable in code but was previously undocumented._
```

Replace `YYYY-MM-DD` with today's date. The three blockquote lines each carry a self-contained italic span (italic spans never cross blockquote line boundaries). The audit skill reads this marker on re-runs to ask whether the finding has been addressed.

## Output Template

Canonical structure (omit Lifecycle for entities with no state machine):

```markdown
# Domain Model

<Optional one-paragraph intro describing the domain at a high level —
what kind of system this is, what the entities collectively represent.
Helps orient readers before they dive into the per-entity sections.>

## <Entity Name>

<One paragraph: what this entity represents in the domain. Plain language,
not technical. Include any workflow exceptions captured in Q5 here, if
relevant to the entity.>

**Key attributes:**
- <attribute-name> — <one-line meaning>
- <attribute-name> — <one-line meaning>
(3-10 attributes; conceptual, not DB columns)

**Relationships:**
- <One per line, with cardinality. E.g., "Has many `<OtherEntity>`s — each
  `<OtherEntity>` belongs to exactly one `<EntityName>`.">

**Lifecycle:** (only if this entity has meaningful states)
- States: `Pending` → `Settled` → `Refunded`; or `Pending` → `Expired`
- Notes: <one or two short lines about non-obvious transitions or terminal states, including any Q5 workflow exceptions relevant to lifecycle>

## <Next Entity>

...
```

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

## Common Mistakes

| Mistake | Fix |
|---|---|
| Including DB column types (`VARCHAR(255)`, `INT NOT NULL`) | Conceptual attributes only — no implementation details |
| Adding a Mermaid/ER diagram | Text only — no diagram syntax of any kind |
| Listing every table including join/audit/session tables | Filter to core domain — drop infrastructure-level tables |
| Listing every enum value as a lifecycle state | Only include lifecycle states with meaningful transitions |
| Lengthy entity descriptions (full-paragraph attributes) | One-line meaning per attribute; ≤2 sentences for "what it represents" |
| 20+ entities in the final draft | Trim with the user; never silently |
| Restating schema layout | Schema ≠ domain model; describe meaning, not structure |
| Forgetting to state cardinality on relationships | "Has many X" / "belongs to one X" — always state cardinality |
| Inventing lifecycles the code doesn't have | Observe, don't speculate — ask the user (Q5) for non-code-visible rules |
| Bundling multiple questions in one ask | One question per turn |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Overwriting in extend mode | Extend merges; only replace overwrites |
| Surfacing a diagnose candidate without file-path evidence | Drop it; only evidence-cited candidates pass the gate |
| Surfacing >5 diagnose candidates | Hard cap is 5; rank by severity → evidence → impact, drop the rest |
| Forgetting the provenance marker on an accepted Q1.5 suggestion | Audit relies on the marker to recognize aspirational entries; without it, drift detection breaks |
| Running Step 1.5 when SUGGEST=off | Skip Step 1.5 entirely when off; do not run-but-suppress |
| Skipping Step 1.6 in audit mode | Drift detection is the audit's reason for existing |
| Bundling Q0 drift resolutions into one multi-select | Each item gets its own question — resolutions are not collectively decidable |
| Forgetting to refresh the provenance marker date when "Keep aspirational" is chosen | Audit needs the refresh to track time-since-last-evaluation |
| Forgetting to strip the provenance marker when "Promote to normal" is chosen | The marker is the audit's hook; promoting means removing it |

## Red Flags

- About to draw an ER diagram → STOP; no diagrams
- About to ask the user a question without using the question tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to start writing the file before showing a draft → STOP; show first, write second
- About to dispatch a subagent → STOP; you're inline, you do the work
- About to list `VARCHAR`/`INT`/`UUID` as types → STOP; conceptual only
- About to include the `audit_logs` or `sessions` table → STOP; system-level, not domain
- About to invent a lifecycle the code doesn't have → STOP; observe (or ask the user) — don't speculate
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing domain model in extend mode → STOP; merge
- About to surface a diagnose candidate without specific file-path evidence → STOP; drop it
- About to run Step 1.5 when SUGGEST=off → STOP; skip entirely

## Why This Skill Is Inline (Not a Subagent)

A domain model draws from two sources — what the code shows (tables, type defs, state machines, FKs) and what the user knows (which entities are load-bearing vs. infrastructure noise, workflow exceptions the schema can't capture, ambiguous cardinality only the team can resolve). A subagent could surface candidates from one read pass but couldn't have the back-and-forth needed to cut 25 candidates down to 15, confirm half a dozen lifecycle completeness questions, resolve cardinality ambiguities, and capture workflow exceptions. Routing all that through a coordinator (subagent returns 25 candidates → coordinator paraphrases to user → user replies → coordinator re-dispatches) wastes turns and drifts intent.

So this skill stays inline. It scans the code itself, then talks to the user about which entities matter and how they really behave. The four sibling skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-glossary`, `ss-bs-discovering-design`) follow the same pattern for the same reason.
