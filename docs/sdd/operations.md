# Operations

This document covers operational mechanics: how subagents are dispatched, what the validation scripts check, the conventions every skill enforces (TDD discipline, `[NO-TDD]` criteria, diagram prohibitions, naming), and how to handle common issues.

## Contents

- [Subagent dispatch](#subagent-dispatch)
- [Status protocols](#status-protocols)
- [Validation scripts](#validation-scripts)
- [Commit Failure Protocol](#commit-failure-protocol)
- [Subagent Failure Protocol](#subagent-failure-protocol)
- [TDD discipline](#tdd-discipline)
- [Diagram prohibitions](#diagram-prohibitions)
- [Naming conventions](#naming-conventions)
- [Troubleshooting](#troubleshooting)

---

## Subagent dispatch

The coordinator dispatches subagents at seven different points in the pipeline (plus the per-task dispatch loop in Stage 13 and the per-failure dispatch loop in Stage 14). Each dispatch is governed by the same general principles:

### Dispatch principles

- **Fresh context per dispatch.** The subagent inherits no conversation history. The coordinator builds the prompt from scratch.
- **Full content inline, not file paths to re-read.** The coordinator pastes the relevant content (e.g., task text from the plan, file paths from the state) into the prompt rather than making the subagent re-read large files.
- **Specify the skill to use.** The dispatch prompt names the skill the subagent should invoke.
- **Specify return format.** The subagent knows what shape of output is expected.
- **Never dispatch in parallel for the same task or artifact.** Sequential only. Especially for implementers — parallel implementers would conflict.

### Dispatch points and prompt templates

| Stage | What's dispatched | Prompt template |
|---|---|---|
| 3, 5 | Spec reviewer | Inline in `ss-sdd-coordinator` (calls `ss-sdd-reviewing-specs`) |
| 6 | ADR maintainer | Inline in `ss-sdd-coordinator` (calls `ss-sdd-maintaining-adrs`) |
| 9, 10 | Plan reviewer | Inline in `ss-sdd-coordinator` (calls `ss-sdd-reviewing-plans`) |
| 13 (per task) | Implementer | `skills/spec-driven-development/ss-sdd-implementing-plans/implementer-prompt.md` (calls `ss-sdd-implementing-task`) |
| 13 (per task) | Spec-compliance reviewer | `skills/spec-driven-development/ss-sdd-implementing-plans/spec-compliance-reviewer-prompt.md` (calls `ss-sdd-reviewing-task-compliance`) |
| 13 (per task) | Code-quality reviewer | `skills/spec-driven-development/ss-sdd-implementing-plans/code-quality-reviewer-prompt.md` (calls `ss-sdd-reviewing-task-quality`) |
| 13 (final) | Final code reviewer | Reuses code-quality reviewer template with `TASK_ID=final` (calls `ss-sdd-reviewing-task-quality`) |
| 14 | Feature tester | `skills/spec-driven-development/ss-sdd-testing-implementation/tester-prompt.md` (calls `ss-sdd-testing-feature`) |
| 14 (fix loop) | Fixer | `skills/spec-driven-development/ss-sdd-testing-implementation/fixer-prompt.md` (calls `ss-sdd-fixing-test-failures`) |
| 15 | Handoff generator | Inline in `ss-sdd-coordinator` (calls `ss-sdd-generating-handoff`) |
| 16 | Memory file maintainer | Inline in `ss-sdd-coordinator` (calls `ss-sdd-maintaining-memory-file`) |

### Standard dispatch shape

```
You are <role> for the SDD pipeline.

Use the `<skill-name>` skill to perform your work.

<INPUTS — filled-in placeholders>

Return the result in the expected format (the skill specifies it).
```

The `<INPUTS>` block is the bulk of the prompt. It includes file paths, content the subagent needs to know, any task-specific context, and the expected output format.

### Why fresh subagents per task

For Stage 13 implementation, every task gets THREE fresh subagent dispatches (implementer + two reviewers):

- **Context isolation:** subagent A working on T003 doesn't have T002's context. Prevents cross-task contamination.
- **Smaller context budgets:** each dispatch has only what it needs.
- **Focused decisions:** the implementer can ask focused questions without trying to balance task-1 considerations against task-3 considerations.
- **Parallel-safe in principle:** even though we run sequentially, the design makes parallel possible if we ever want it.

### Subagent question handling (NEEDS_CONTEXT)

When a subagent (especially an implementer) reports `NEEDS_CONTEXT`, it's asking the coordinator for information that wasn't in the original dispatch. The framework uses the re-dispatch model — portable across all harnesses regardless of interactive-subagent support.

The subagent returns immediately on encountering ambiguity, with a structured response:

```
Status: NEEDS_CONTEXT

What you need: <concrete question>
What you tried: <code/files you read that informed the question>
What you'd do if forced to guess: <your default — for the controller to correct or confirm>
```

The coordinator then:

1. Reads the question carefully
2. Decides if it can answer from the spec / plan / project context, OR if it needs user input
3. If the coordinator can answer: appends the answer to the task description and re-dispatches a fresh implementer subagent
4. If user input is needed: surfaces the question to the user, gets the answer, then re-dispatches
5. **Never** auto-decides on the subagent's "forced guess" without confirming first

Subagents don't have a back-and-forth with the user directly. The coordinator mediates. This protocol works on platforms that don't support interactive subagent continuation (`SendMessage` or equivalent) — the re-dispatch is universal.

---

## Status protocols

Subagents return one of a small set of statuses depending on their role. The coordinator's handling depends on the status.

### Implementer subagent statuses

| Status | Meaning | Coordinator action |
|---|---|---|
| `DONE` | Task complete, tests passing, self-review clean | Proceed to spec-compliance review |
| `DONE_WITH_CONCERNS` | Complete + tests pass, but concerns flagged | If correctness/scope: re-dispatch with concerns appended. If observations: note + proceed. |
| `NEEDS_CONTEXT` | Missing information from original dispatch | Provide context, re-dispatch |
| `BLOCKED` | Cannot complete | Assess: more context / more capable model / smaller pieces / escalate to user |

### Reviewer subagent statuses (spec, plan, per-task)

| Status | Meaning | Coordinator action |
|---|---|---|
| `Approved` | No CRITICAL or HIGH findings | Advance |
| `Issues Found` | At least one CRITICAL or HIGH | Apply fixes per `ss-sdd-receiving-review-findings` protocol |

Per-task code-quality reviewers also distinguish:
- **Critical** findings — must fix
- **Important** findings — must fix
- **Minor** findings — noted but non-blocking

### Tester subagent statuses

| Status | Meaning | Coordinator action |
|---|---|---|
| `PASS` | All tests passed | Advance to Stage 15 |
| `FAIL` | Issues found in feature-level testing | Dispatch fixer, re-test (cap 3 iterations) |
| `MCP_UNAVAILABLE` | Couldn't run real tests | Surface manual test plan + code review to user; **DO NOT test yourself** |

### Critical: coordinator doesn't test itself

The `MCP_UNAVAILABLE` status is the highest-risk rationalization point in the pipeline. The coordinator may have Bash, Playwright access, curl, and database tools available. The temptation to "just check the feature works" is real.

**The coordinator MUST NOT test the feature itself.** It surfaces the result to the user:

> "Couldn't run automated tests for this feature — <tester's reason>. The tester did a code review fallback and produced a manual test plan:
>
> [manual test plan]
>
> [code review findings]
>
> Options:
> 1. Run the manual tests now and tell me the result
> 2. Skip testing and proceed to finishing
> 3. Pause SDD so you can configure the missing MCP and re-run testing later"

The `ss-sdd-testing-implementation` skill repeats this rule in five different places because it's that important.

---

## Validation scripts

Three validators check artifact format before commit:

### `validate-spec.sh`

**Path:** `skills/spec-driven-development/framework/validate-spec.sh`
**Usage:** `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-spec.sh" <path-to-spec.md>`

**Critical checks (exit 1 if any fail):**
- Required sections present: Header (`# Spec:`), Goal, User Stories, Functional Requirements, Success Criteria, Edge Cases, Assumptions, Out-of-Scope
- At least one `FR-###` and one `SC-###`
- **Duplicate FR-### or SC-### IDs** (defined more than once via `**FR-NNN:**` / `**SC-NNN:**`)
- At least one user story priority (`(P1)`, `(P2)`, etc.)
- No placeholder patterns: `TBD`, `TODO`, `TKTK`, `[placeholder]`, `[fill in`, `[your-`, `<your-`, `FIXME`
- No forbidden diagram blocks: ```` ```mermaid ````, ```` ```plantuml ````, ```` ```puml ````, `@startuml`, `C4Container`, `C4Component`

**Warnings (don't fail the exit code):**
- Story count vs acceptance scenarios count mismatch
- Soft length guard at 800 lines

Invoked by `ss-sdd-writing-specs` as the first sub-step of its self-review. The skill must include the validator's PASS line verbatim in its report back to the coordinator. The coordinator re-runs the validator before committing — if the fresh run doesn't agree with the report, the stage halts.

### `validate-plan.sh`

**Path:** `skills/spec-driven-development/framework/validate-plan.sh`
**Usage:** `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-plan.sh" <path-to-plan.md>`

**Critical checks (exit 1 if any fail):**
- Required sections: Header (`# Plan:`), Goal, Architecture, Tech Stack, File Structure
- At least one Phase (`### Phase 1 — …`)
- At least one `T###` task ID
- **Duplicate T### task IDs** (the same `### Task TNNN` defined more than once)
- `[NO-TDD]` markers have a non-blank reason on the immediately following line
- No placeholders: `TBD`, `TODO`, `TKTK`, `FIXME`, `implement later`, `fill in details`, `add appropriate error handling`, `add validation`, `similar to Task`, `<placeholder>`, `[your-`, `<your-`
- No forbidden diagram blocks (same as spec)

**Warnings:**
- Task header count vs Requirements references mismatch
- Soft length guard at 2000 lines

Invoked by `ss-sdd-writing-plans` as first sub-step of self-review; coordinator re-runs before committing (same enforcement pattern as `validate-spec.sh`).

### `validate-handoff.sh`

**Path:** `skills/spec-driven-development/framework/validate-handoff.sh`
**Usage:** `"$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/validate-handoff.sh" <path-to-handoff.md>` (or `<path>.tmp` — the script strips trailing `.tmp` for the filename pattern check)

**Critical checks (exit 1 if any fail):**
- Filename matches `YYYY-MM-DD-<kebab-title>.md` pattern (trailing `.tmp` is stripped before checking, so validation works on the staged file before atomic mv)
- Required sections: Header (`# Handoff:`), Quick context, Source artifacts, What got built, Build highlights, Test status, Open concerns, If you're continuing this work, Redactions
- No unredacted secret patterns (the most important check):
  - OpenAI/Anthropic keys: `sk-...` (20+ chars), `sk-ant-...`
  - AWS keys: `AKIA[0-9A-Z]{16}`, `ASIA[0-9A-Z]{16}`
  - GitHub tokens: `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` followed by 20+ chars
  - JWT pattern: `eyJ...` 3-part base64 with `.` separators
  - URLs with credentials: `https?://<user>:<pass>@<host>`
  - SSH private key markers: `-----BEGIN [A-Z ]+PRIVATE KEY-----`
  - Sensitive env-var assignments: `(_SECRET|_PASSWORD|_TOKEN|_API_KEY|_KEY)\s*[:=]\s*` with 8+ char value
- No placeholders (handoff is generated, not drafted)

**Warnings:**
- ADR section appears to duplicate ADR content (h3+ headings under Source artifacts)
- Soft length guard at 800 lines

Invocation flow inside `ss-sdd-generating-handoff`:
1. Compose and redact content (in memory)
2. Write to `<output-path>.tmp`
3. Run `validate-handoff.sh <output-path>.tmp` — fix issues in the .tmp file and re-validate until PASS
4. Atomic `mv <output-path>.tmp <output-path>`

The coordinator re-runs the validator against the final file before committing (same enforcement pattern as spec/plan validators).

### Interpreting validator output

Output format (all three validators):

```
CRITICAL: <issue 1>
CRITICAL: <issue 2>
WARNING: <issue 3>

----
FAIL — 2 critical issue(s), 1 warning(s)
```

OR

```
WARNING: <issue>

----
PASS — 1 warning(s), 0 critical issues
```

Exit code 0 = pass (warnings OK), 1 = fail (critical issues exist), 2 = usage error (wrong args or file not found).

When a validator fails:
1. Read the CRITICAL issues
2. Fix each one in the artifact
3. Re-run the validator
4. Repeat until PASS

Warnings can be left if they're acceptable (e.g., a deliberately long spec). They're informational, not blocking.

---

## Commit Failure Protocol

Every stage that produces a commit (Stage 12 batch commits, Stage 13 per-task code commits, Stage 16 memory file commit when updated, Stage 17 `--no-ff` merge commit on `main`, plus per-task implementer + fixer commits) must handle commit failures. The canonical protocol lives in `ss-sdd-coordinator/SKILL.md`; this is the human-readable summary.

**Detection:** check `git commit`'s exit code. If non-zero, capture stdout/stderr.

**Common failure modes:**

| Failure | Handling |
|---|---|
| Pre-commit hook rejected the commit (lint/format/test) | If the hook auto-modified files (formatter), re-stage and re-commit ONCE. If the hook flagged real issues, fix the underlying issue if it's in scope; otherwise halt and surface to user. |
| Missing `user.name` or `user.email` | Halt. Surface to user with instructions to run `git config`. Don't attempt to set these yourself. |
| GPG signing failure | Halt. Surface to user with the gpg error. |
| Nothing to commit | Investigate: check `git status` and `git log -1`. If intended files are already committed, treat as success. Otherwise halt. |
| File not found in `git add` | The previous stage's writer may have failed silently. Verify the expected file exists; if not, the prior stage didn't complete properly. |
| Stage 12 partial batch commit (Commit 1 succeeded, Commit 2 failed) | Halt. Surface to user with both commit outputs and the partial state (Commit 1 is already in history). Do NOT auto-revert; the user decides whether to amend, add a follow-up commit, or reset. |
| Stage 17 `git merge --no-ff` failure (conflicts, hook rejection, signing failure on the merge commit) | Halt. Surface git's stdout/stderr verbatim. Leave the working tree as-is (do NOT auto-`git merge --abort`). Do NOT delete the feature branch. Do NOT `rm` the state file. The user resolves manually (complete the merge commit, or `git merge --abort` and investigate) and re-invokes the coordinator. Stage 17 is naturally idempotent — `git merge --no-ff` on an already-merged branch returns 0 with "Already up to date" and the run completes. |
| Stage 17 `git branch -d` failure (branch not fully merged, despite the merge step succeeding) | Halt. Surface the error. Do NOT escalate to `git branch -D`. Do NOT `rm` the state file. This means the branch is in an unexpected state; the user investigates. |

**Hard rules — never violate:**

- **Never use `--no-verify`.** Hooks are telling you something.
- **Never use `--no-gpg-sign`.** If signing is policy, bypassing ships unsigned commits.
- **Never use `--force` on push.** Investigate rejections instead.
- **Never silently retry.** Read the error, act on it; retry at most once when the cause is clear.
- **Never amend a published commit** to fix a hook failure. Create a new commit.

**Subagent commits:** the implementer and fixer subagents follow the same rules. On commit failure they report `BLOCKED` to the controller with the commit error output. The controller surfaces to user.

## Subagent Failure Protocol

Subagent dispatches can fail in ways the dispatch contract doesn't cover — timeout, crash, malformed output, missing required fields. The canonical protocol lives in `ss-sdd-coordinator/SKILL.md`.

**Failure modes:** timeout, crash/error, malformed output (missing structural markers like `Status:`), empty/whitespace result, claimed-completion-but-missing-required-fields.

**Hard rules:**
- **Max one retry per failure mode per dispatch point.** No retry loops.
- **Never silently move on.** A failed dispatch is a stage failure; halt and surface to user.
- **Never substitute coordinator's own work for the subagent's** (e.g., if the spec reviewer crashes, don't review the spec yourself).
- **Never run two retry attempts in parallel.**

**User-facing escalation format:**

```
Subagent failure at <stage> (<role>): <one-line summary>.
Attempted: <what was tried and how many retries>.
Last output (if any): <truncated to 500 chars>.

Options:
1. Retry the dispatch manually
2. Skip the dispatch and proceed (only for non-mandatory stages)
3. Abort the SDD run (state file kept)
4. Provide the result manually
```

Default is option 1; never auto-pick.

## TDD discipline

The pipeline assumes test-driven development for all task implementation by default. The `ss-sdd-writing-plans` skill produces TDD steps for every task; the implementer subagent follows them.

### The TDD cycle (Red-Green-Refactor)

Every implementation task follows:

1. **RED — Write the failing test.** The plan shows the exact test code. Implementer writes it.
2. **Verify the test fails** for the expected reason. The plan specifies the expected failure message.
3. **GREEN — Write the minimal implementation.** Just enough to pass.
4. **Verify the test passes.**
5. **Commit.**

"Minimal" matters. If the test passes with 3 lines, write 3 lines, not 30. Subsequent tasks extend functionality.

### Refactor steps

For most tasks, the plan doesn't include explicit refactor steps — the implementer is in scope only for the task at hand. Refactoring is typically captured as its own task in the plan, with its own tests.

### When NOT to use TDD (`[NO-TDD]` marker)

`[NO-TDD]` is an opt-out marker for tasks that genuinely can't follow Red-Green-Refactor. **Strict criteria** — the task must match one of these allowed categories:

| Allowed category | Examples |
|---|---|
| `docs-only` | README updates, CHANGELOG, ADR text fixes, code comments only |
| `config-only` | JSON/YAML/TOML/INI data changes without runtime behavior changes (e.g., bumping a timeout value, adding a feature flag) |
| `asset-addition` | Images, fonts, static files, fixtures with no consuming code |
| `dependency-bump` | package.json / Cargo.toml / requirements.txt version bumps without API changes |
| `mechanical-rename` | File renames or moves with all callers updated mechanically; no behavior change |
| `lint-only` | Whitespace, import sorting, formatter-driven changes |

`[NO-TDD]` is NOT allowed for:
- Any logic change in code files (`.ts`, `.js`, `.py`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, etc.)
- Bug fixes (always need a failing test first)
- Refactors that change behavior, even subtly
- "Trivial" changes the writer thinks don't need a test

### Format requirements

When using `[NO-TDD]`:

```markdown
### Task T020 [NO-TDD] [Polish]: Update README with auth section

Reason: docs-only.

**Files:**
- Modified: `README.md`

**Requirements:** FR-001, FR-002

- [ ] **Step 1: ...**
- [ ] **Step 2: Verify ...**
- [ ] **Step 3: Commit ...**
```

The reason line is required (validate-plan.sh checks for it) and must match one of the allowed categories (ss-sdd-reviewing-plans checks for that).

### Enforcement

- `ss-sdd-writing-plans` produces TDD steps by default. If the writer marks `[NO-TDD]`, they must include a category-matching reason.
- `validate-plan.sh` checks that `[NO-TDD]` markers have a non-blank reason on the next line.
- `ss-sdd-reviewing-plans` flags `[NO-TDD]` misuse (used on a logic-change task, or reason doesn't match an allowed category) as **CRITICAL**.
- The implementer subagent (via `ss-sdd-implementing-task` skill) is instructed to suspect `[NO-TDD]` if the task actually changes logic.

### Common rationalizations and rebuttals

| Rationalization | Reality |
|---|---|
| "The test would be trivial" | Trivial tests catch trivial bugs. Write it. |
| "It's just a config tweak" | If the config affects runtime behavior, it's not `config-only`. |
| "I'll add tests later" | Later never comes. Add it now or `[NO-TDD]` with a real category. |
| "TDD slows me down" | Slows initial coding; speeds debugging and refactoring later. |

---

## Diagram prohibitions

Specs, plans, and **handoff documents** are all prose only. No diagrams of any kind:

- ❌ Mermaid blocks
- ❌ PlantUML / `@startuml`
- ❌ C4 syntax (`C4Container`, `C4Component`, etc.)
- ❌ ASCII art diagrams
- ❌ Image embeds

All three validators (`validate-spec.sh`, `validate-plan.sh`, `validate-handoff.sh`) catch ` ```mermaid `, ` ```plantuml `, ` ```puml `, `@startuml`, `C4Container`, and `C4Component`. **ASCII art is on honor system** — the validators can't reliably detect it via grep (too many false positives), so writers are explicitly instructed not to sneak it in.

### Why

- Diagrams encode information that's better in prose for LLM consumption.
- Maintaining diagrams (especially Mermaid) is friction; they fall out of sync with the prose around them.
- ASCII art is often a sign that the author should have decomposed the structure into smaller named pieces.
- The "show vs tell" instinct that wants a diagram is usually better satisfied by clearer prose and named entities.

### What about flowcharts in skill files?

Some skill files (e.g., `subagent-driven-development` from Superpowers) use `dot` flowcharts in their own SKILL.md. We deliberately don't — all our SKILL.md files use prose and tables. The Diagram prohibition applies to specs/plans/handoffs (artifacts produced by the pipeline) — it's a hard rule there.

### If you genuinely want a visual

If you really want a diagram, put it in:
- A separate `.md` or `.svg` file outside the spec/plan
- A linked external doc (`See: docs/architecture/auth-flow.svg`)

Just don't put it in the spec or plan.

---

## Naming conventions

### Spec directories

- Pattern: `NNN-<short-name>/`
- `NNN`: zero-padded 3-digit sequential number
- `<short-name>`: 2-4 kebab-case words

Examples: `001-user-auth`, `002-export-csv`, `015-fix-payment-timeout`

Numbers are sequential per repo; never reset. If you delete a feature dir, that number is gone; don't reuse.

### ADR filenames

- Pattern: `NNNN-<kebab-title>.md`
- `NNNN`: zero-padded 4-digit sequential number
- `<kebab-title>`: 2-5 kebab-case words from the ADR title

Examples: `0001-use-jwt-for-sessions.md`, `0023-postgresql-over-mongo.md`

### Handoff filenames

- Pattern: `YYYY-MM-DD-<kebab-title>.md`
- Date in UTC; sortable
- `<kebab-title>`: 2-5 kebab-case words

Examples: `2026-05-20-user-auth.md`, `2026-06-15-export-csv.md`

If two handoffs are generated on the same date with the same short name (rare), append `-<N>`:
`2026-05-20-user-auth-2.md`

### Branch names

- Pattern: `feat/<short-name>` for features, `fix/<short-name>` for bug fixes
- Configurable via `.sublime-skills/config.yml` → `branching.branch_pattern`

The short name matches the spec directory's short name (after the spec is created in Stage 2). At Stage 0 (preflight), the user may give a working name that gets refined later — that's OK.

### Task IDs

- Pattern: `T###` (e.g., `T001`, `T012`, `T123`)
- Sequential within a plan
- 3+ digits; zero-padded if under 100

### Skill names

- All kebab-case, gerund-led where it reads naturally:
  - `ss-sdd-writing-specs`, `ss-sdd-discovering-requirements`, `ss-sdd-maintaining-adrs` — gerunds
  - `ss-sdd-coordinator`, `ss-sdd-preflight-checks` — established role/noun names (allowed exceptions)
- No special characters; just letters, numbers, and hyphens

---

## Troubleshooting

### "Preflight aborted — not_a_git_repo"

**Cause:** the current directory isn't inside a git repository.
**Fix:** initialize one and re-invoke: `git init && git commit --allow-empty -m "Initial commit"`. SDD requires git to commit pipeline artifacts.

### "Preflight aborted — detached_head"

**Cause:** HEAD is detached (no current branch). SDD requires a named branch to commit to.
**Fix:** switch to a branch (`git checkout <branch>`) or create one (`git checkout -b <new>`), then re-invoke.

### "Preflight aborted — user_declined"

**Cause:** you said "no" to the dirty-tree confirmation, or to a feature-branch decision later in Stage 12.
**Fix:** clean up the working tree (or accept it), then re-invoke. SDD can run on top of dirty work; the confirmation is just a heads-up.

### `validate-spec.sh` or `validate-plan.sh` failing

**Cause:** the artifact doesn't match the required structure.
**Fix:** read the CRITICAL output line by line. Common causes:
- Forgot a required section
- Used `TBD` or `TODO` as a placeholder
- Added a Mermaid block (delete it; describe in prose instead)
- `[NO-TDD]` marker without a reason on the next line

Re-run the validator after fixing; it'll either pass or surface the next issue.

### `validate-handoff.sh` failing on "potential unredacted secret"

**Cause:** the handoff doc contains something that looks like an API key, token, JWT, etc.
**Fix:** find the line (the validator gives you the line number), inspect it, and decide:
- If it's actually a secret → redact it (`[REDACTED]`), note the redaction in the Redactions section
- If it's a false positive (e.g., a base64 string that's not a secret) → the validator is too aggressive here; the most reliable fix is to slightly reformat the offending string so it doesn't match the pattern (e.g., insert a space or wrap in single backticks if it was already unwrapped)

The validator errs aggressive on purpose — under-redaction is worse than over-redaction.

### Reviewer flags many findings (>10)

**Cause:** either the artifact is genuinely problematic, or the reviewer subagent is miscalibrated.
**Fix:**
- Read the CRITICAL findings — those should be addressed regardless
- If the HIGH/MEDIUM/LOW count is unusually high, look at whether the reviewer is flagging style preferences as issues
- The `ss-sdd-receiving-review-findings` skill says to approve unless CRITICAL/HIGH findings — most LOW findings should be ignored
- If the reviewer is wrong: document the push-back in state file (`reviewer_pushbacks`), advance anyway

### Spec or plan review hits its 2-iteration fix-loop cap

**Cause:** the artifact has a fundamental gap that needs human input, or the reviewer is miscalibrated, or findings/fixes are oscillating.
**Fix:** the coordinator follows `ss-sdd-receiving-review-findings` Step 8 (escalation protocol):
- Surfaces the fix history and currently-unresolved findings
- Offers four options:
  1. **Iterate with user guidance** — user dictates exact edits, coordinator applies them literally, no further auto-review
  2. **Override the reviewer** — each finding's push-back recorded with the user's technical reason
  3. **Accept current state with known issues** — records `reviewer_pushbacks` with "accepted with known issues"
  4. **Abort the stage** — pause SDD; user investigates manually

The cap is hard — the coordinator does NOT dispatch a 3rd auto-iteration under any circumstances.

### Per-task review loop hits its 3-iteration cap

**Cause:** the implementer can't satisfy the reviewer; the plan or task is likely wrong.
**Fix:** the coordinator escalates to the user. Options:
- Revise the task in the plan and resume
- Override the reviewer (document why in state file)
- Skip the task and address it later as a separate concern

### Tester returns `MCP_UNAVAILABLE`

**Cause:** the tester subagent doesn't have access to the MCPs needed for feature-level testing (browser MCP for UI, DB MCP for backend, etc.).
**Fix:** the coordinator surfaces the manual test plan to you. Options:
- Run the manual tests yourself, report results to the coordinator
- Skip testing entirely (`stages_skipped` gets `testing`)
- Pause SDD, configure the missing MCP, then resume

**The coordinator MUST NOT test the feature itself**, even if it has Bash and Playwright access. Testing is delegated.

### Test fix-loop hits its 3-iteration cap

**Cause:** the same test failures persist after 3 fix attempts. The plan, spec, or implementation may be fundamentally wrong.
**Fix:** coordinator escalates. Options:
- Pause SDD, investigate manually
- Revise plan/spec and re-enter implementation
- Accept the failures and proceed to finishing (records `test_status: failed_escalated`)

### State file malformed after a crash

**Cause:** something killed the session mid-atomic-write (rare but possible).
**Fix:** the coordinator detects this when it reads the state file and shows you the parse error. Options:
- Attempt repair (user-guided): edit the JSON manually until it parses
- Discard state and start fresh (loses pipeline progress; spec/plan/code are still in git)
- Abort coordinator

The atomic write pattern (write to `.tmp` then `mv`) makes this rare — typically you'd see either the old content or the new content, never half-written.

### "I want to revise the spec mid-implementation"

**Cause:** an implementation task revealed a spec gap or wrong assumption.
**Fix:** pause Stage 13 (let the current task finish or BLOCKED it), edit the spec inline (re-run `validate-spec.sh`), edit the plan if needed (re-run `validate-plan.sh`), then resume Stage 13 from where you left off. The `tasks` map is preserved.

There's no clean "loop back to earlier stage" mechanism for this — it's deliberately a judgment call.

### Existing state when starting a fresh feature

**Cause:** an SDD run was abandoned mid-pipeline in a dead prior conversation. `.sublime-skills/state.json` is still on disk. You now want to start a new feature in this conversation.
**Fix:** nothing for you to do — Stage 0 (preflight) silently removes any pre-existing state file and writes a fresh shell before returning ready. SDD treats cross-conversation resume as out of scope; any orphan is unambiguously dead.

If you genuinely need multiple concurrent runs (rare), use git worktrees — each worktree has its own `.sublime-skills/state.json` and they're naturally isolated.

### Resume after a long time

SDD does not support cross-conversation resume. If you want to continue work on a feature whose pipeline ran in a prior conversation, start a new SDD run and reference the existing spec/plan/ADRs that landed on disk (or the handoff doc from Stage 15, if you generated one). Any leftover state file from the prior conversation will be cleared by preflight as an orphan.

### Coordinator wants to do a phase-skill's work inline

**Cause:** the coordinator skill instructs it to load phase-skills and delegate; sometimes it's tempted to "just do it" without loading the skill.
**Fix:** that's a violation of the coordinator's hard gates. Re-read the coordinator's process — it's a thin state machine. All actual work happens in phase-skills or subagents.

If you notice this pattern, file a follow-up to tighten the coordinator's instructions on that stage.

### Pre-commit hook rejects a stage's commit

**Cause:** a pre-commit hook (lint, format, tests, signing) flagged a real issue with the staged files.
**Fix:** follow the Commit Failure Protocol above. Common cases:
- Formatter auto-modified files → re-stage and re-commit once
- Linter flagged a real issue → fix the underlying issue if it's in scope; otherwise halt and surface
- Tests failed in a pre-commit hook → fix the test or the code; halt if it's outside the current task's scope
- Missing git identity (`user.name`/`user.email`) → halt; tell user to configure

**Never use `--no-verify`** as a shortcut. The hook is doing its job.

### Subagent crashed, timed out, or returned malformed output

**Cause:** platform error, model error, timeout, malformed output that doesn't match the expected format.
**Fix:** follow the Subagent Failure Protocol above. The coordinator retries at most once, then surfaces to user with four options (retry manually / skip if non-mandatory / abort SDD / provide result manually).

### Multiple-tier review told me to write content my task didn't list

**Cause:** the spec-compliance reviewer ran but couldn't verify a `**Requirements:** FR-NNN` reference because the FR wasn't present in the spec.
**Fix:** this is a real spec/plan mismatch. Either the plan references an FR that doesn't exist (fix the plan), or the FR was renumbered (re-render the plan), or the FR was deleted (decide whether the task is still needed). Surface to user; don't fabricate the requirement.

---

## Reference: skill file is authoritative

When this document conflicts with the SKILL.md files: **the SKILL.md is authoritative.** Skills are the executable spec that the AI runs. This document is the human-readable explanation. If they drift, prefer the skill.
