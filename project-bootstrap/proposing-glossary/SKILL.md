---
name: proposing-glossary
description: Use as a dispatched subagent to deeply analyze a project's source code, docs, and identifiers and propose a glossary (10-30 canonical domain terms with ≤2-sentence definitions). Read-only. Returns findings + proposed markdown to the dispatching coordinator.
---

# Proposing Glossary

## Overview

You were dispatched by `bootstrapping-project` to analyze a project's source code, documentation, and identifier names, then propose content for `docs/GLOSSARY.md` — 10-30 canonical domain-specific terms with concise definitions.

**Core principle:** The glossary captures the project's **canonical vocabulary** — domain words that recur across the codebase and have a specific, project-flavored meaning. Generic programming terms (function, variable, class) belong in textbooks, not here. The bar is: would someone new to the project misuse this term without a definition?

**Operating mode:** STRICTLY READ-ONLY. You do NOT write files; you do NOT modify config; you do NOT interact with the user; you do NOT dispatch sub-subagents.

**Announce at start:** "I'm using the proposing-glossary skill to analyze this project."

## Hard Gates

- Do NOT write any file — return content to the controller; the controller writes
- Do NOT use todo/task tools (`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, or any harness equivalent). The todo list is shared with the controller; your entries pollute it.
- Do NOT use user-interaction tools (`AskUserQuestion` or harness equivalent). Return findings to the controller; the controller handles user discussion.
- Do NOT dispatch sub-subagents (`Task` / `Agent` tool). You are a leaf skill.
- Do NOT propose generic programming terms (function, class, database) — domain-specific only
- Do NOT exceed 30 terms — quality over quantity; the load-bearing vocabulary
- Do NOT write definitions longer than 2 sentences each

## Inputs from the Dispatcher

- `REPO_ROOT` — absolute path to the repository root
- `MODE` — one of `create`, `extend`, `replace`
- `EXISTING_CONTENT` — verbatim current content of `docs/GLOSSARY.md` (only for `extend`/`replace`; empty otherwise)
- `FILE_PATH` — where the file will be written

## Checklist

1. Read README and top-level docs for prominent domain vocabulary
2. Sample source code: model names, class names, route paths, database table names, key types
3. Read comments for terms that are explained inline (often a glossary signal)
4. Cross-reference: a term that appears in source AND docs AND DB schema is high-priority for the glossary
5. For `extend` mode: read EXISTING_CONTENT and identify gaps
6. Filter the candidate list down to 10-30 entries
7. Draft alphabetically sorted definitions
8. Return findings + proposed_content to the controller

## Step 1: Top-Level Docs Pass

Read these if they exist:
- `README.md` — the project introduces its vocabulary here, usually with capitalization signals (PascalCase or backticked terms)
- `CONTRIBUTING.md`
- `docs/` — skim the table of contents or README; note any "Concepts" or "Terminology" sections
- `EXISTING_CONTENT` (for extend/replace) — see what's already covered

Note every term that:
- Is capitalized when used as a noun (suggests it's a defined concept)
- Is backticked inline (suggests it's a project-specific term)
- Is introduced with a definition ("a **Foo** is a ...")

## Step 2: Source Code Identifiers

You don't need every file. Sample widely:

**Class / type / interface names** (depending on language):
- Look at file names — many languages use one-class-per-file conventions
- Skim a few source files for top-level type/class declarations

**Database / model names:**
- Migration directories (`migrations/`, `db/migrations/`, `prisma/schema.prisma`)
- Model files (`models/`, `entities/`, ORM-specific)
- Table names in raw SQL or schema files

**Route paths:**
- Look at routing config or route handler files
- API endpoints reveal domain nouns (`/api/orders`, `/api/customers`, `/api/sku/:id`)

**Configuration / env vars:**
- Sometimes env var names reveal domain concepts (`MAX_LOCKED_ORDERS`, `STALE_QUOTE_TTL`)

For each candidate term, note:
- Where you saw it (file path)
- How it's used (variable name, type name, route, table)

## Step 3: Inline Comments and Docstrings

Search the codebase for comments that explain terms. Patterns:
- `// A <Foo> represents ...`
- `/** <Foo>: <description> */`
- `# <Foo> means ...`

These are gold — the author has already done the work of defining the term. You can lift the definition (rephrased to fit the glossary format).

## Step 4: Cross-Reference Scoring

A term that appears across **multiple layers** is a strong glossary candidate:
- Term appears in DB schema + a model class + a route + the README → almost certainly canonical, include
- Term appears only in a single source file's local variable → probably not glossary-worthy
- Term appears in source code + docs but with **different meanings** in each → this is exactly what a glossary clarifies; flag it

For each candidate, score informally: how many distinct layers (DB / model / source / route / docs / config / README) does this term appear in? Prioritize the higher scorers.

## Step 5: Mode Handling

**For `create` mode:** ignore EXISTING_CONTENT. Build the full proposal.

**For `extend` mode:** read EXISTING_CONTENT and identify which terms are already defined. Your proposal is **net-new terms** that weren't covered, OR **refinements** to definitions you observed are inaccurate. Don't restate existing definitions verbatim.

**For `replace` mode:** ignore EXISTING_CONTENT. Build a fresh proposal.

## Step 6: Filter to 10-30 Entries

You'll likely have 50+ candidates after Steps 1-4. Trim ruthlessly:

- Drop generic programming terms (function, variable, class, API, endpoint, database)
- Drop terms whose meaning is fully captured by their name (`UserCreatedEvent` doesn't need a glossary entry; "Event" might)
- Drop terms that are vendor names without project-specific meaning (Stripe, AWS, Sentry — don't define them, unless your project uses them in a specific role like "the Stripe Adapter is...")
- Drop terms that only appear in one place
- Drop synonyms — pick the most-used spelling, and note alternates in the definition if useful

What to KEEP:
- Core domain entities (`Order`, `Quote`, `Inventory`, `Tenant`, `Workspace`, `Pipeline`, `Run`)
- Project-specific abbreviations (`SKU`, `RFQ`, `TTL` if used in a specific sense)
- Concepts that span business + technical (`Reconciliation`, `Settlement`, `Promotion`, `Backfill`)
- Roles / personas (`Admin`, `Operator`, `Customer`) — only if they have a project-specific definition (not "a user who has admin rights" — that's textbook)
- Lifecycle states that appear as enum values (`Pending`, `Settled`, `Disputed`)
- Process names (`Sync`, `Replay`, `Snapshot`) that have project-specific meaning

## Step 7: Synthesize Findings

```
## Findings

### High-confidence candidates (appear across multiple layers)
- `Quote` — in DB (quotes table), models/Quote.ts, /api/quotes route, README intro
- `RFQ` (Request For Quote) — in models/RFQ.ts, /api/rfqs route, code comments
- `Settlement` — in models/Settlement.ts, jobs/settle-quotes.ts, docs/payments.md
- ...

### Medium-confidence (in source but limited spread)
- `Backfill` — used as a function name in scripts/backfill-quotes.ts; might be glossary-worthy if it has project-specific meaning
- ...

### Existing glossary (extend mode only)
- Covers: Quote, RFQ, Settlement, Customer
- Missing: Backfill, Reconciliation, Idempotency Key, Workspace
- Inaccurate: definition of Settlement says "final state" but the code has Settled → Refunded transitions
```

## Step 8: Draft Proposed Content

For `create` and `replace` modes:

```markdown
# Glossary

## A

### <Term>
<Definition (≤2 sentences). If the term has alternate spellings or synonyms,
note them: "Also written as ...".>

## B

### <Term>
<Definition.>

(... alphabetically grouped by first letter; only include letter headings
that have entries.)
```

For `extend` mode: the proposed_content is the new entries to insert, with their letter headings (the controller will merge into the existing alphabetical structure).

**Definition guidelines:**

- ≤2 sentences. Period. Long definitions are signals the term needs a separate doc, not a glossary entry.
- Lead with the noun: "**Quote** — a price commitment given to a customer, valid until its expiry timestamp."
- Avoid circular references ("a Quote is a quotation"). If you must reference another glossary term, capitalize it or backtick it.
- If a term has a domain meaning AND a generic meaning, define the domain meaning: "**Idempotency key** — a client-supplied token attached to each write request, used to deduplicate retries. Generated by clients, validated by the API layer."
- For lifecycle states: define what the state means AND the typical transitions. Example: "**Settled** — a Quote whose payment has been confirmed by the payment provider. Transitions from Pending; can transition to Refunded."

**Examples of good entries (illustrative — adapt to your findings):**

> ### Quote
> A price commitment given to a customer in response to an RFQ, valid until its expiry timestamp. Quotes transition through Pending → Settled, or Pending → Expired if not accepted in time.

> ### RFQ (Request For Quote)
> A customer's inbound request for pricing on a specific configuration. RFQs are short-lived; each generates exactly one Quote.

> ### Idempotency key
> A client-supplied token attached to every write request, used to deduplicate retries server-side. Required for all `POST`/`PUT`/`DELETE` endpoints.

## Step 9: Return to the Controller

```
## Findings

<from Step 7>

## Proposed content

<for create/replace: the full glossary markdown>
<for extend: the new entries to add, with their letter headings>

## Notes for the controller

<caveats: terms you dropped that might still be relevant, terms with
unclear definitions, suggestions for further-research>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Defining generic programming terms (function, class, API) | Domain-specific only |
| Definitions longer than 2 sentences | Trim to ≤2; if longer is needed, the term belongs in its own doc, not a glossary |
| Proposing >30 terms | Trim to load-bearing; the goal isn't completeness, it's clarification |
| Circular definitions (`X is a kind of X-thing`) | Define by what it represents in the domain, not by its name |
| Lifting marketing copy from README without confirming code matches | Definitions must reflect what the code does, not what the README says it does |
| Listing every enum value as a glossary term | Only include lifecycle states with non-obvious semantics |
| Skipping the alphabetical grouping | Always alphabetical; helps lookup |

## Red Flags

- About to write a file → STOP; controller writes
- About to ask the user a question → STOP; controller handles user discussion
- About to dispatch a subagent → STOP; you are a leaf
- About to define `Database` or `API` → STOP; generic terms are out of scope
- About to write a 4-sentence definition → STOP; trim to ≤2
- About to include 40+ entries → STOP; cap at 30
