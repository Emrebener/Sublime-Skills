# Artifact Formats

The SDD pipeline produces five categories of artifacts, each with a strict format. This document is the canonical reference for what each artifact contains, where it lives, and how it's structured.

## Artifact summary

| Artifact | Path | Producer | Schema validator |
|---|---|---|---|
| Spec | `docs/specs/NNN-<short-name>/spec.md` | `writing-specs` (Stage 2), updated by `grilling-specs` (Stage 4) | `validate-spec.sh` |
| Plan | `docs/specs/NNN-<short-name>/plan.md` | `writing-plans` (Stage 8) | `validate-plan.sh` |
| ADR | `docs/adr/NNNN-<kebab-title>.md` | `maintaining-adrs` (Stage 6) | (no automated validator) |
| Handoff | `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<kebab-title>.md` | `generating-handoff` (Stage 15) | `validate-handoff.sh` |
| State | `.sublime-skills/state.json` | `writing-specs` initializes; coordinator + other skills update | (schema at `framework/state-schema.md` / `.json`) |

For state file schema details, see [state-and-config.md](state-and-config.md).

---

## 1. Spec

### Path and naming

- Path: `docs/specs/NNN-<short-name>/spec.md`
- `NNN`: 3-digit zero-padded sequential number; allocated by scanning `docs/specs/` and picking the highest + 1
- `<short-name>`: 2-4 kebab-case words derived from the feature description (e.g., `user-auth`, `export-csv`, `fix-payment-timeout`)

### Structure (required sections in order)

```markdown
# Spec: <Title>

**Feature ID:** NNN-<short-name>
**Created:** YYYY-MM-DD
**Status:** Draft
**Branch:** <branch-name>

## Goal

<One paragraph. What problem this solves and for whom. Uses domain vocabulary from the glossary if present.>

## User Stories

### Story 1 — <Brief title> (P1)

<Plain-language journey: who, what, why.>

**Why this priority:** <Reason — usually impact or dependency.>

**Independent test:** <How can this story alone be tested as an MVP increment?>

**Acceptance scenarios:**

1. **Given** <state>, **When** <action>, **Then** <outcome>
2. **Given** <state>, **When** <action>, **Then** <outcome>

---

### Story 2 — <Brief title> (P2)

<… same shape as Story 1 …>

---

### Story 3 — <Brief title> (P3)

<… same shape as Story 1 …>

## Functional Requirements

- **FR-001:** System MUST <capability>. _Stories: US1, US2_
- **FR-002:** Users MUST be able to <action>. _Stories: US1_
- **FR-003:** System MUST <data/behavior>. _Stories: US3_

(Each FR is testable. Each references the stories it supports.)

## Success Criteria

- **SC-001:** <Measurable outcome — time/percent/count/rate.>
- **SC-002:** <Measurable outcome.>
- **SC-003:** <User-experience or business metric.>

(All technology-agnostic, all measurable.)

## Edge Cases

- <What happens when [boundary condition]?>
- <How does the system handle [error scenario]?>
- <Behavior under [unusual load / network / data condition]?>

## Assumptions

- <Things we're treating as given that we should be explicit about.>
- <Defaults adopted from industry standards or project conventions.>

## Out-of-Scope

- <Adjacent feature explicitly deferred.>
- <Capability someone might reasonably expect but isn't included.>
```

### Optional sections

Add only when relevant; omit entirely if not (don't leave "N/A"):

```markdown
## Key Entities

(Include only if data is involved.)

- **<Entity 1>:** <What it represents, key attributes (conceptual, no DB columns), key relationships.>
- **<Entity 2>:** <…>

## Open Questions

(Include only if some remain after discovery. Each should be answerable later — they're not blockers.)

- <Question 1>
- <Question 2>

## References

(External docs, related ADRs, etc.)

- ADR-NNNN — <title>
- <External doc URL>
```

### Auto-managed section (added by the grill)

If a grill session (Stage 4) ran, this section is auto-managed:

```markdown
## Clarifications

### Session 2026-05-20

- Q: Should we support OAuth2 in addition to JWT? → A: No, JWT only for MVP
- Q: What's the token expiry? → A: 24 hours

(One bullet per accepted answer. Subsequent grill sessions add to this section.)
```

### Acceptance criteria format options

**Default: Given/When/Then.** Compact, readable.

**EARS format** (Easy Approach to Requirements Syntax) is allowed when precision matters:

- `WHEN <event> THEN <system> SHALL <response>` (event-driven)
- `IF <precondition> THEN <system> SHALL <response>` (conditional)
- `WHILE <state>, <system> SHALL <response>` (state-driven)
- `WHERE <feature>, <system> SHALL <response>` (ubiquitous)
- `<system> SHALL <response>` (unconditional)

If using EARS for a story, label its section `**Acceptance criteria (EARS):**` instead of `**Acceptance scenarios:**`. Pick one style per story; don't mix freely.

### Hard rules

- **No diagrams** (Mermaid, C4, PlantUML, ASCII art) — the spec is prose
- **No implementation details** (file paths, code, task lists — those live in the plan)
- **No placeholders** (TBD, TODO, `<your-...>`)
- **Domain vocabulary** — if a glossary exists, use canonical terms; don't introduce synonyms

### Worked example (compact)

```markdown
# Spec: User Authentication

**Feature ID:** 003-user-auth
**Created:** 2026-05-20
**Status:** Draft
**Branch:** feat/user-auth

## Goal

Logged-in users currently rely on a shared service token. We need per-user authentication so we can track user-level actions and apply per-user authorization. Targets the web app's /api endpoints.

## User Stories

### Story 1 — Login with email and password (P1)

A user enters their email and password on the login page and receives an authenticated session.

**Why this priority:** core flow; nothing else makes sense without it.

**Independent test:** can be verified by signing up a user, logging in, and confirming subsequent requests carry an auth identity.

**Acceptance scenarios:**

1. **Given** a registered user, **When** they submit valid credentials at `/login`, **Then** they receive a session token in an HttpOnly cookie and are redirected to `/dashboard`.
2. **Given** an unregistered email, **When** the user submits the login form, **Then** they see "Invalid email or password" without distinguishing email-vs-password.
3. **Given** a correct email and incorrect password, **When** the user submits, **Then** they see the same "Invalid email or password" message.

---

### Story 2 — Logout (P2)

(... etc ...)

## Functional Requirements

- **FR-001:** System MUST issue a session token on successful login. _Stories: US1_
- **FR-002:** System MUST reject invalid credentials with a generic error message. _Stories: US1_
- **FR-003:** System MUST invalidate the session on logout. _Stories: US2_
- **FR-004:** System MUST expire sessions after 24 hours of inactivity. _Stories: US1, US2_

## Success Criteria

- **SC-001:** 95% of login attempts complete in under 500ms (p95).
- **SC-002:** No more than 0.1% of users report being locked out of their account due to auth bugs in the first month.
- **SC-003:** 100% of /api/* endpoints reject unauthenticated requests with HTTP 401.

## Key Entities

- **User:** registered account holder. Has an email (unique), a hashed password, a status (active/suspended), and timestamps for created/last_login.
- **Session:** an authenticated user's active session. Linked to one User. Has an expiry and a creation timestamp.

## Edge Cases

- What happens when a user's password hash algorithm is upgraded? (Re-hash on next successful login.)
- How does the system handle concurrent logins from multiple devices? (Multiple sessions allowed; each independently expires.)
- What about session token theft? (HttpOnly + Secure cookies; out of scope: device fingerprinting.)

## Assumptions

- Sessions are stored server-side (not stateless JWT — that's an ADR decision).
- Password reset flow is out of scope for this spec; will be a separate feature.

## Out-of-Scope

- Password reset
- Two-factor authentication
- Social login (Google, GitHub, etc.)
- Per-device session management UI
```

---

## 2. Plan

### Path and naming

- Path: `docs/specs/NNN-<short-name>/plan.md`
- Lives in the same directory as the spec it implements

### Structure (required sections in order)

```markdown
# Plan: <Title>

**Feature ID:** NNN-<short-name>
**Spec:** [spec.md](./spec.md)
**Created:** YYYY-MM-DD
**Status:** Draft

## Goal

<One sentence — what this builds.>

## Architecture

<2-3 sentences on the approach. Reference ADRs that govern key choices.>

## Tech Stack

<Key technologies/libraries used, in bullet form.>

---

## File Structure

**New:**
- `path/to/file.ext` — one-line responsibility

**Modified:**
- `path/to/existing.ext` — what changes about it

**Dependencies:**
- Add/remove: <package names>

---

## Phases

### Phase 1 — Setup

(Tasks with no `[US#]` label. Project init, dep installs, config.)

### Phase 2 — Foundational

(Tasks blocking multiple stories. No `[US#]` label.)

### Phase 3 — <Story 1 title> (US1)

(Tasks tagged `[US1]`. Completing this phase alone yields a working MVP increment.)

### Phase 4 — <Story 2 title> (US2)

(Tasks tagged `[US2]`.)

### ...

### Final Phase — Polish

(Cross-cutting concerns, integration tests, docs. No `[US#]` label.)
```

### Task structure

Every task header:

```markdown
### Task T012 [P] [US1]: Implement JWT issue/verify

**Files:**
- Create: `src/auth/jwt.ts`
- Test: `tests/auth/jwt.test.ts`

**Requirements:** FR-002, FR-003
```

- `T###` — sequential task ID, 3+ digits
- `[P]` — parallel marker (optional; only when this task is parallelizable with other `[P]` tasks in the same phase)
- `[US#]` — story label (required for Phase 3+ tasks, no label for Setup/Foundational/Polish)
- `[NO-TDD]` — TDD opt-out marker (strict criteria; see [operations.md](operations.md))
- `**Requirements:** FR-..., SC-...` — traceability to spec FRs/SCs

### TDD step format (default)

````markdown
- [ ] **Step 1: Write the failing test**

```ts
// tests/auth/jwt.test.ts
import { issueToken, verifyToken } from '../../src/auth/jwt';

test('issueToken produces a verifiable token', () => {
  const token = issueToken({ userId: 'u1' });
  const claims = verifyToken(token);
  expect(claims.userId).toBe('u1');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/auth/jwt.test.ts`
Expected: FAIL — "Cannot find module '../../src/auth/jwt'"

- [ ] **Step 3: Write minimal implementation**

```ts
// src/auth/jwt.ts
import jwt from 'jsonwebtoken';
const SECRET = process.env.JWT_SECRET || 'dev-secret';

export function issueToken(claims: object): string {
  return jwt.sign(claims, SECRET, { expiresIn: '24h' });
}

export function verifyToken(token: string): any {
  return jwt.verify(token, SECRET);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/auth/jwt.test.ts`
Expected: PASS — 1/1 tests passing

- [ ] **Step 5: Commit**

```bash
git add src/auth/jwt.ts tests/auth/jwt.test.ts
git commit -m "feat(auth): JWT issue/verify (T012)"
```
````

### [NO-TDD] task format

```markdown
### Task T020 [NO-TDD] [Polish]: Update README with auth section

Reason: docs-only.

**Files:**
- Modified: `README.md`

**Requirements:** FR-001, FR-002

- [ ] **Step 1: Add new "Authentication" section to README.md**

(Show the exact markdown to insert, where to insert it.)

- [ ] **Step 2: Verify**

Run: <preview the README in markdown viewer of choice>
Expected: section renders correctly

- [ ] **Step 3: Commit**

git add README.md
git commit -m "docs: add authentication section (T020)"
```

The reason line must match one of the [NO-TDD] allowed categories (see [operations.md](operations.md)).

### Hard rules

- **No placeholders** ("TBD", "fill in", "implement later", "add appropriate error handling", "similar to Task N", "write tests for the above" without code)
- **No diagrams** (Mermaid, C4, PlantUML, ASCII art)
- **Complete code in every code step** — if a step says "write the function", show the function inline
- **Exact commands** — `npx vitest run tests/auth/jwt.test.ts` not "run the tests"
- **Exact expected output** — "Expected: PASS — 1/1 passing" not "Expected: it should pass"
- **No references to undefined symbols** — every function, type, or method referenced must be defined in an earlier task or in the codebase
- **Bite-sized steps** — 2-5 minutes each, one action per step

### Optional sections

```markdown
## Open Questions

(Include only if some remain. Don't block; flag for later.)

- <Question>

## Risk Notes

(Include only if there are non-obvious risks worth documenting.)

- <Risk and mitigation>
```

---

## 3. ADR (Architecture Decision Record)

### Path and naming

- Path: `docs/adr/NNNN-<kebab-title>.md`
- `NNNN`: 4-digit zero-padded sequential number, allocated by scanning existing ADRs and picking highest + 1
- `<kebab-title>`: 2-5 kebab-case words from the ADR title

### Format (locked)

```markdown
# ADR-NNNN: <Title>

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN | Deprecated
- **Date:** YYYY-MM-DD
- **Spec:** [NNN-short-name](../specs/NNN-short-name/spec.md)
- **Supersedes:** ADR-NNNN (optional, only when applicable)

## Context

<2-4 paragraphs: the situation we're in, the forces at play, what's driving the decision now. Use project domain vocabulary. Don't restate the spec — link to it.>

## Decision

<1-2 paragraphs: what we chose, stated clearly enough that someone could implement it from this alone.>

## Consequences

**Positive:**
- <Outcome we gain.>
- <Outcome we gain.>

**Negative:**
- <Cost we accept.>
- <Risk we take on.>

**Trade-offs accepted:**
- <Things we're explicitly giving up vs. alternatives.>

## Alternatives Considered

- **<Alt A>:** <What it was, why rejected (concretely).>
- **<Alt B>:** <What it was, why rejected.>
```

### Status lifecycle

- **Proposed** — default when first written by `maintaining-adrs`. Awaiting user approval.
- **Accepted** — default outcome of Stage 7 (user spec approval). The coordinator flips ADRs to Accepted unless the user explicitly chooses "Approve, keep ADRs as Proposed".
- **Superseded by ADR-NNNN** — automatically set when a new ADR explicitly supersedes this one.
- **Deprecated** — manually set when an ADR is no longer relevant (rare).

### Supersession

When a new ADR overrides an older one:

1. New ADR is written with `Supersedes: ADR-XXXX` in the front matter.
2. Old ADR's status is changed from `Accepted` to `Superseded by ADR-NNNN`.
3. Both files are committed together.

### Numbering rules

- Sequential across all ADRs in the project (don't reset per spec or per year)
- Zero-padded to 4 digits (`0001`, `0002`, …, `0099`, `0100`, …)
- Numbers are immutable once assigned; never renumbered

### What's ADR-worthy

ALL of these must hold for an ADR to be warranted:

- Architectural (touches structure, technology, communication, data flow, security, deployment)
- A reasonable alternative was considered or could have been
- Reasoning isn't self-evident from code or spec — future readers benefit from `why`
- Not already captured by an existing ADR

NOT ADR-worthy:
- Routine implementation details (naming, function organization)
- Spec-level requirements (those live in the spec)
- Choices forced by external constraints with no real alternative
- Stylistic preferences

### Worked example

```markdown
# ADR-0003: Use JWT for Session Tokens

- **Status:** Accepted
- **Date:** 2026-05-20
- **Spec:** [003-user-auth](../specs/003-user-auth/spec.md)

## Context

The auth feature (spec 003-user-auth) introduces per-user authentication. We need to decide how to represent and validate authenticated sessions across API requests. Our backend is horizontally scaled (3 nodes behind a load balancer) and we want to avoid sticky sessions or shared session storage if we can.

Existing ADRs don't cover authentication; this is the first time we're introducing user sessions.

## Decision

Use JSON Web Tokens (JWT) signed with HS256 for session representation. Tokens are stored in HttpOnly, Secure cookies. Token claims include `userId`, `iat` (issued-at), and `exp` (expiry; 24 hours from issuance).

Token verification is stateless: each API request validates the JWT signature server-side using the shared secret. No session lookup against a store is required for normal requests.

Revocation is handled via a blocklist table (`session_blocklist`) with a TTL matching token expiry. The blocklist is read per request (cached in-memory with 30s TTL on each node).

## Consequences

**Positive:**
- Stateless verification scales horizontally without sticky sessions.
- No session store dependency in the request path (only for revocation, which is cached).
- Standard library support for JWT in our stack (jsonwebtoken on Node, PyJWT on Python).

**Negative:**
- Token revocation is delayed by up to 30 seconds (the in-memory cache TTL).
- JWT secret rotation requires careful coordination (we'll document this in ops runbooks).
- Token size is larger than a session ID (~200 bytes vs ~32 bytes), slightly increasing per-request overhead.

**Trade-offs accepted:**
- Up to 30 seconds of revocation delay is acceptable for our threat model.
- The complexity of secret rotation is worth the operational simplicity of statelessness.

## Alternatives Considered

- **Server-side sessions:** Easier revocation, simpler model. Rejected because horizontal scaling requires sticky sessions or a shared session store; both are operational complexity we don't currently have.
- **OAuth2 with an external provider:** Offloads identity entirely. Rejected because our user base doesn't use third-party identity providers consistently, and the external dependency adds login-path latency we want to avoid.
```

---

## 4. Handoff document

### Path and naming

- Path: `~/.sublime-skills/handoffs/<repo-basename>/YYYY-MM-DD-<kebab-title>.md`
- `YYYY-MM-DD` — date of generation (UTC), enables sorting by date
- `<kebab-title>` — 2-5 kebab-case words from the feature's short name or title
- Handoffs live outside the repo by design and are not committed to source control. The absolute path is recorded in `state.json` so the user/tooling can find the doc.
- Same-day re-runs: append `-<N>` (e.g., `2026-05-20-user-auth-2.md`)

### Structure (required sections)

```markdown
# Handoff: <Spec Title>

**Feature ID:** NNN-<short-name>
**Branch:** <branch-name>
**Date generated:** YYYY-MM-DD
**Status:** <Implementation complete | Testing passed | Testing skipped | Testing failed (escalated)>

## Quick context

<2-3 sentences. What was built, for whom, why. Uses domain vocabulary from the glossary if present.>

## Source artifacts

- **Spec:** [<path>](<path>) — <one-line summary>
- **Plan:** [<path>](<path>) — <one-line summary>
- **ADRs created/touched in this run:**
  - [ADR-NNNN](<path>) — <one-line title>
- **Prior relevant ADRs:** (only if the spec or plan explicitly cites them)
  - [ADR-NNNN](<path>) — <one-line title>

## What got built

<2-4 paragraphs. Architecture choice + why (reference ADR), major files/modules added or changed (one-line each), notable patterns followed, anything non-obvious.>

## Build highlights

- **Commits:** <N> commits between `<BASE_SHA>` and `<HEAD_SHA>`
- **Files changed:** <M> files, +<additions> / -<deletions> lines
- **Notable commits:**
  - `<sha>` — <message>

## Test status

<One paragraph: whether feature-level testing ran (Stage 14), result, what was NOT verified that a fresh agent should manually check.>

## Open concerns

<Bulleted list of anything unresolved:
- Open questions that didn't block implementation
- Known limitations or trade-offs
- Tests marked [NO-TDD] that probably should have tests later
- DONE_WITH_CONCERNS observations not fully resolved

Use "None — implementation is clean" if there genuinely are none.>

## If you're continuing this work

<Practical guidance for a fresh agent:
- Where to start reading
- What's in git log vs spec/plan
- If iterating on PR feedback: what's addressed vs what isn't
- In-flight things (e.g., "branch hasn't been merged yet; awaiting PR review")
- Environment setup the next agent needs to know (referenced by name only — no values)>

## Redactions

<If redactions performed:
- "<count> secret-like values redacted across <section names>"
- "<count> env-var values referenced by name only"

If none: "None">
```

### Optional section

```markdown
## Files not to look at (low signal)

(Optional. Only if applicable.)

- `package-lock.json` — generated
- `dist/*` — build output
```

### Redaction rules

The redaction sweep replaces matches with `[REDACTED]`:

| Pattern | Examples |
|---|---|
| OpenAI / Anthropic keys | `sk-...` (40+ chars), `sk-ant-...` |
| AWS access keys | `AKIA...` (20 chars), `ASIA...` |
| GitHub tokens | `ghp_...`, `gho_...`, `ghu_...`, `ghs_...`, `ghr_...` |
| JWT-shaped strings | `eyJ...` 3-part base64 |
| URLs with credentials | `https?://<user>:<pass>@<host>` |
| SSH private keys | `-----BEGIN [A-Z ]+PRIVATE KEY-----` plus content |
| Sensitive env vars | `*_SECRET=...`, `*_PASSWORD=...`, `*_TOKEN=...`, `*_KEY=...` (value 8+ chars) |
| Generic secret literals | `password = "..."`, `secret = "..."`, etc. with literals 10+ chars |

**Rules:**
- When in doubt, redact. The source files still exist; the handoff doc is a shareable summary.
- Note in the doc what was redacted (count and section names).
- Env vars are referenced by name only: `OPENAI_API_KEY (value redacted)`.
- Two-pass scan to catch redactions revealed by other redactions.

### Hard rules

- **Reference, don't duplicate.** ADRs and spec sections get path links + one-line summaries, not pasted content.
- **No placeholders.** The handoff is generated, not drafted. `TBD` should never appear.
- **Schema-validated.** Must pass `validate-handoff.sh` before being committed.

---

## 5. State file

See [state-and-config.md](state-and-config.md) for the full state file schema, field ownership, lifecycle, and resume protocol.

Quick reference:

- **Path:** `.sublime-skills/state.json`
- **Created:** Stage 2 (`writing-specs`)
- **Updated:** at every stage boundary by the coordinator; per-task by `implementing-plans`
- **Deleted:** Stage 17 (`finishing-sdd`) via plain `rm` — no commit anywhere
- **Atomic writes** via `state.json.tmp` + `mv`
- **Permanently gitignored throughout.** The bootstrap creates `.sublime-skills/.gitignore` with `state.json` listed; no SDD stage ever commits the state file. Branch operations (`git checkout`, `git stash -u`) leave it in place.

---

## Where to find templates

The skill files themselves contain authoritative templates. If you're looking for the exact text to copy-paste:

- Spec template: `spec-driven-development/writing-specs/SKILL.md` → "Spec Structure" section
- Plan template: `spec-driven-development/writing-plans/SKILL.md` → "Plan Structure" section
- ADR template: `spec-driven-development/maintaining-adrs/SKILL.md` → "Step 5: Write ADRs"
- Handoff template: `spec-driven-development/generating-handoff/SKILL.md` → "Handoff Structure" section

The templates in this doc and those in the SKILL.md files should always match. If they drift, the SKILL.md is authoritative (skills are the executable spec; docs are the explanation).
