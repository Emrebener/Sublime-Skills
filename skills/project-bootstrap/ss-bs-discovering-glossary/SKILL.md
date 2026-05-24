---
name: ss-bs-discovering-glossary
description: Use as an INLINE skill (NOT a dispatched subagent) loaded by ss-bs-bootstrapping-project at the glossary slot. Scans READMEs, identifiers, DB schemas, route paths, and comments to surface candidate terms; then asks the user to pick the ≤30 that matter, note aliases, and refine definitions. Writes docs/GLOSSARY.md (or the configured path) atomically.
---

# Discovering Glossary

## Overview

You are loaded **inline** by `ss-bs-bootstrapping-project` (NOT dispatched as a subagent). A glossary captures the project's canonical vocabulary — domain words that recur across the codebase and have a project-flavored meaning. The code reveals which terms exist and where they appear, but only the user can confirm which ones are load-bearing for a newcomer, whether two names refer to the same thing, and whether a definition lifted from inline comments matches current intent. A subagent could surface candidates from one read pass but couldn't have the back-and-forth needed to settle the cut list. So this skill stays in the coordinator's context.

**Core principle:** The bar for inclusion is — would someone new to the project misuse this term without a definition? Generic programming terms (function, variable, class) belong in textbooks, not here.

**Announce at start:** "I'm using the ss-bs-discovering-glossary skill to build docs/GLOSSARY.md with you."

## When This Skill Runs

You're invoked when the user picked **Create / Extend / Replace** for glossary. The coordinator passes you:

- `REPO_ROOT` — absolute path to the repo root
- `MODE` — `create`, `extend`, or `replace`
- `EXISTING_CONTENT` — verbatim current `docs/GLOSSARY.md` content (only for `extend` / `replace`; empty otherwise)
- `FILE_PATH` — target write path (typically `docs/GLOSSARY.md`; honors `context.glossary_path` config override if non-default)

## Hard Gates

- ALWAYS use the harness's interactive question tool for every yes/no or multi-choice question. Do NOT default to plain-text prompts that force the user to type a free-form answer when a structured choice exists.
- Ask ONE question per turn. Never bundle multiple unrelated questions in a single ask.
- Lead with multi-choice + a recommended option whenever the choice has clear alternatives. Free-form text only for genuinely open prompts (aliases, definition refinements).
- Do NOT use Mermaid, C4, PlantUML, or any other diagram syntax in the proposed glossary — text only.
- Do NOT dispatch subagents. You're inline — you do the work.
- Do NOT propose generic programming terms (function, class, database, API) — domain-specific only.
- Do NOT exceed 30 terms in the final draft — quality over quantity.
- Do NOT write definitions longer than 2 sentences each.
- Do NOT overwrite an existing glossary in `extend` mode. Extend merges; only `replace` overwrites.
- Do NOT loop past 3 tweak iterations without surfacing bail options to the user.

## Top-Level Flow

```
┌─────────────────────────────────────────────────────┐
│ MODE = create or replace                            │
│   → Step 1: silent code scan (READMEs, identifiers, │
│             schemas, routes, comments)              │
│   → Step 2: announce findings                       │
│   → Step 3: targeted questions (term selection,     │
│             aliases)                                │
│   → Step 4: synthesize draft → show to user         │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write                            │
├─────────────────────────────────────────────────────┤
│ MODE = extend                                       │
│   → Step 1: silent code scan + read EXISTING_CONTENT│
│   → Step 2: announce findings + gaps                │
│   → Step 3: targeted questions on gaps only         │
│   → Step 4: synthesize additions → show diff        │
│   → Step 5: refine via tweak loop (cap 3)           │
│   → Step 6: atomic write of merged content          │
└─────────────────────────────────────────────────────┘
```

## Step 1: Code Scan (Silent — No User Narration Yet)

Read all of the following that exist. Don't narrate progress to the user — this happens silently, then you announce findings once in Step 2.

### 1a. Top-level docs pass

Read these if they exist:
- `README.md` — the project introduces its vocabulary here, usually with capitalization signals (PascalCase or backticked terms)
- `CONTRIBUTING.md`
- `docs/` — skim the table of contents or README; note any "Concepts" or "Terminology" sections

Note every term that:
- Is capitalized when used as a noun (suggests it's a defined concept)
- Is backticked inline (suggests it's a project-specific term)
- Is introduced with a definition ("a **Foo** is a ...")

### 1b. Source code identifiers

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

### 1c. Inline comments and docstrings

Search the codebase for comments that explain terms. Patterns:
- `// A <Foo> represents ...`
- `/** <Foo>: <description> */`
- `# <Foo> means ...`

These are gold — the author has already done the work of defining the term. You can lift the definition (rephrased to fit the glossary format).

### 1d. Cross-reference scoring

A term that appears across **multiple layers** is a strong glossary candidate:
- Term appears in DB schema + a model class + a route + the README → almost certainly canonical, include
- Term appears only in a single source file's local variable → probably not glossary-worthy
- Term appears in source code + docs but with **different meanings** in each → this is exactly what a glossary clarifies; flag it for the user in Q1

For each candidate, score informally: how many distinct layers (DB / model / source / route / docs / config / README) does this term appear in?

### 1e. Mode-specific reads

- **`create` mode:** ignore `EXISTING_CONTENT` (it's empty). Build candidate list from scratch.
- **`extend` mode:** read `EXISTING_CONTENT` carefully. Note which terms are already defined. Candidate additions focus on net-new terms; also flag definitions in `EXISTING_CONTENT` that contradict current code behavior.
- **`replace` mode:** ignore `EXISTING_CONTENT`. Build candidates fresh.

### 1f. Compile candidate list in memory

You'll likely have 50+ raw candidates after Steps 1a–1d. Pre-filter to ≤40 before showing to the user:

- Drop generic programming terms (function, variable, class, API, endpoint, database)
- Drop terms whose meaning is fully captured by their name (`UserCreatedEvent` doesn't need a glossary entry; "Event" might)
- Drop terms that are vendor names without project-specific meaning (Stripe, AWS, Sentry — unless used in a specific role like "the Stripe Adapter")
- Drop terms appearing in only one file
- Keep synonyms separate for now — the user resolves these in Q2

For each surviving candidate, hold:
- The term (preferred spelling — most-used in code)
- A draft 1-sentence definition (lifted from inline comments where possible; otherwise from what you observed about its use)
- The evidence (where it appeared, layer count)

## Step 2: Announce Findings

One short message (3-6 sentences). State what you scanned and the headline finding. Example:

> "Here's what I picked up: 38 candidate terms after filtering generic ones. The strongest signals are `Quote`, `RFQ`, `Settlement`, `Reconciliation`, `Idempotency Key`, `Workspace` (each appears in ≥3 layers: DB schema, models, routes, docs). I'll ask you which ≤30 should land in the glossary, then refine the definitions."

If `create` mode and the scan found very little:
> "I didn't find much domain-specific vocabulary — mostly generic terms (User, Item, Status). Either the project is early or the domain is genuinely lean. Want to continue building from what I found, or skip the glossary for now?"

If `extend` mode:
> "Your existing glossary covers [N] terms. I scanned the codebase and found [M] additional candidates not covered (and [K] existing definitions that look inconsistent with current code). I'll ask about those, then propose additions/refinements."

## Step 3: Targeted Questions

Ask in this order, one question per turn. Skip a question if the scan and (for extend mode) the existing file already answered it.

### Q1 — Term selection (multi-select)

The most important question. Present the pre-filtered candidate list with a one-line draft definition each, grouped by signal strength.

```
Question: "I scanned identifiers, comments, schemas, and docs. Here are the candidate terms ranked by how many layers they appear in. Which should land in the glossary? (Cap is 30.)"

Multi-select. Group options as:
- High-confidence (3+ layers): [list with draft definitions]
- Medium-confidence (2 layers): [list with draft definitions]
- Edge cases (1 layer but appeared notable): [list]

Recommended option:
- "Top 30 from the list (high + medium confidence, in order)"

If the candidate list is already ≤30 after filtering:
- "All of the above (Recommended)"
```

If the user selects >30, immediately follow up with a single trim question:

```
Question: "That's more than 30. Which should I drop?"
Multi-select from the over-cap list.
```

### Q2 — Aliases / multi-naming (free-form)

```
Question: "Are there terms in the code that have multiple names for the same thing? Examples:
- 'Customer' and 'Account' are interchangeable
- 'Order' in the DB but 'Transaction' in the API
- 'SKU' and 'ProductCode' refer to the same identifier
- 'Reconcile' (verb) and 'Reconciliation' (noun)

Free-form text. List each pair/group on its own line, or skip if there are none."
```

Apply user-supplied aliases by:
- Picking the preferred spelling as the primary entry
- Noting alternates inline in the definition: "Also called `<alternate>`."

### Q3 (extend mode only) — Resolve definition conflicts

If Step 1e flagged any contradiction between existing definitions and current code behavior, ask the user how to resolve each:

```
Question: "Your existing glossary defines '<term>' as '<existing definition>', but the code currently behaves like '<observed>'. What's the right resolution?"

Options:
  - "Update the definition to match current behavior"
  - "Keep the existing definition — the code is in violation"
  - "Drop the term — it no longer applies"
  - "Keep both perspectives — I'll clarify in the definition" (free-form follow-up)
```

### Q4 — Definition refinements (tweak loop in Step 5)

Definition refinements are handled during the Step 5 tweak loop — the user can call out specific entries to rewrite when reviewing the full draft.

## Step 4: Draft & Show to User

Synthesize the draft using:
- Selected terms from Q1 (≤30)
- Alias notes from Q2
- Conflict resolutions from Q3 (extend mode)

Use the canonical alphabetical template (see Output Template section). Show the full draft to the user, then ask:

```
Question: "How does this look?"

Options:
  - "Approve — write it as-is" (Recommended)
  - "Tweak — I'll tell you what to change"
  - "Start over — wrong direction"
  - "Abort — skip this file"
```

## Step 5: Refine (Tweak Loop, cap 3)

**On Tweak:** capture the user's free-form notes (often "rewrite the Settlement definition to mention refund transitions" or "drop Backfill, add Snapshot"); apply; re-show; re-ask Step 4. Cap at **3 iterations**:

> "We've done three rounds and the draft still isn't matching what you want. Want to:
> (a) keep the current draft anyway,
> (b) skip the glossary for now, or
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

For **extend** mode: merge `EXISTING_CONTENT` + the new entries / refinements into a single alphabetically-sorted document, then write atomically. Preserve existing accurate entries; replace only the ones flagged in Q3.

Report to the coordinator one of:

- `created` (mode = create, full draft written)
- `extended` (mode = extend, merged content written)
- `replaced` (mode = replace, full draft written)
- `skipped (declined mid-skill)` (user aborted partway)

## Output Template

Canonical alphabetical structure (only include letter headings that have entries):

```markdown
# Glossary

## A

### <Term>
<Definition (≤2 sentences). If the term has alternate spellings or synonyms,
note them: "Also called `<alternate>`.">

## B

### <Term>
<Definition.>

(... alphabetically grouped by first letter)
```

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

## Common Mistakes

| Mistake | Fix |
|---|---|
| Defining generic programming terms (function, class, API) | Domain-specific only |
| Definitions longer than 2 sentences | Trim to ≤2; if longer is needed, the term belongs in its own doc, not a glossary |
| Proposing >30 terms | Trim with the user; never silently |
| Circular definitions (`X is a kind of X-thing`) | Define by what it represents in the domain, not by its name |
| Lifting marketing copy from README without confirming code matches | Definitions must reflect what the code does, not what the README says it does |
| Listing every enum value as a glossary term | Only include lifecycle states with non-obvious semantics |
| Skipping the alphabetical grouping | Always alphabetical; helps lookup |
| Bundling multiple questions in one ask | One question per turn |
| Looping past 3 tweak iterations | Surface to user with bail options |
| Overwriting in extend mode | Extend merges; only replace overwrites |

## Red Flags

- About to ask the user a question without using the question tool → STOP; use the structured ask
- About to ask two questions in one turn → STOP; split them
- About to start writing the file before showing a draft → STOP; show first, write second
- About to dispatch a subagent → STOP; you're inline, you do the work
- About to define `Database` or `API` → STOP; generic terms are out of scope
- About to write a 4-sentence definition → STOP; trim to ≤2
- About to include 40+ entries → STOP; trim with the user (cap is 30)
- About to loop into a 4th tweak round → STOP; surface bail options
- About to overwrite an existing glossary in extend mode → STOP; merge

## Why This Skill Is Inline (Not a Subagent)

A glossary draws from two sources — what the code calls things (identifiers, schema columns, route paths, comments) and what the user *means* by those things. The first half a subagent could extract; the second half requires conversation. Picking the ≤30 terms that actually matter from a 50-candidate list is a judgment call only the user can make. Resolving aliases (does "Customer" and "Account" mean the same thing here?) requires asking. Confirming that an inline-comment definition still matches reality requires asking. Routing all that through a coordinator (subagent returns 50 candidates → coordinator paraphrases to user → user replies → coordinator re-dispatches with trim instructions) wastes turns and drifts intent.

So this skill stays inline. It scans the code itself, then talks to the user about which terms are load-bearing and what they really mean. The four sibling skills (`ss-bs-discovering-constitution`, `ss-bs-discovering-architecture`, `ss-bs-discovering-domain-model`, `ss-bs-discovering-design`) follow the same pattern for the same reason.
