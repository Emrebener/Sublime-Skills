---
name: ss-agile-advancing-milestones
description: >-
  Use when advancing GitHub milestone progress — auto-selects the current milestone
  (the open milestone with the lowest number, i.e. the earliest sprint with work
  remaining), picks the next logical issue from it, and drives that issue end-to-end
  through implementation, optional polish (only when the issue is gnarly), and local merge by dispatching subagents. Designed
  to be invoked repeatedly (e.g. from a ralph-loop wrapper) until all milestones are
  closed. Sister skills (loaded by subagents): `ss-agile-implementing-an-issue`,
  `ss-agile-polishing-an-issue`. For `gh` syntax, lean on `ss-agile-managing-issues`.
---

# Advancing Milestones

You are the **coordinator** for one cycle of milestone progress. Your job is to find the *current* milestone (the earliest open one), pick one issue from it, and drive that issue through implementation, optional polish, and local merge via subagents — not to do the implementation or polish yourself. You orchestrate.

**Session scope: one issue per invocation.** The flow is linear: find current milestone → pick issue → implementer → (optional polisher) → merge. There is no verdict, no iteration loop, no reviewer-as-gatekeeper. **Polish is opt-in per issue** — skip by default; run only when the issue is gnarly enough that a second-pass sanity check is worth the token cost (decision rules in Step 7). When the polisher does run, it improves the diff and flags possibly-unmet acceptance criteria as info, but never blocks the merge. After the merge, this session ends.

**Designed for ralph-loop re-invocation.** Each invocation is self-contained: it queries live GitHub state, picks one issue, completes it, and exits. The skill can be invoked over and over by an outer wrapper until everything is done. Two clean exit signals tell the outer loop to terminate:

- **All milestones closed** → "nothing to advance, all done." Wrapper should stop the loop.
- **Current milestone is stuck** (all its open issues are blocked or assigned to others) → "stuck, here's why." Wrapper should stop the loop and surface the diagnostic to the user — this usually means the dependency graph is wrong and needs human attention.

Both exit signals are explicit, structured, and easy to detect from the skill's final output.

## Autonomy contract — never ask questions

This skill runs as part of a fully autonomous pipeline. **NEVER ask the user a question. NEVER pause for input.** A ralph-loop wrapper may be invoking the pipeline with no human at the keyboard; any question you ask will hang the loop indefinitely.

When you're tempted to ask, do one of these instead:

- **Information missing or ambiguous?** STOP with a clean exit signal naming exactly what's missing. The wrapper terminates, the user fixes it offline, then re-invokes.
- **Multiple valid options?** Apply this skill's stated policy. If the policy is silent on the choice, pick the most conservative option and explain the choice in your output.
- **State looks unexpected?** STOP with a clean exit signal. Do not auto-correct (could destroy work); do not ask (breaks the loop).

| Tempted to ask... | Do this instead |
|---|---|
| "Should I proceed?" | Proceed. Or STOP with exit signal if unsafe. |
| "Which option do you want?" | Apply policy. If silent, choose conservatively. |
| "Is this OK?" | If you need to ask, STOP and surface — don't wait. |
| "Can you clarify X?" | STOP with exit signal naming the ambiguity. |
| "I noticed Y — should I do Z?" | Report Y in your final output. Don't do Z without instruction. |

**Violating the spirit violates the letter.** "Just making sure", "this is important", "the user might want to know," "I'll just confirm quickly" — none of those justify a question. Either STOP cleanly or proceed cleanly. Never wait.

## Terminal exit markers (machine-readable contract)

Every termination of this session — successful merge, all-done, stuck, or any failure — MUST end its final user-facing output with a single line in this exact format:

```
RALPH_EXIT: <state>
```

This marker is what the ralph-loop wrapper greps for to decide whether to re-invoke. The marker must be the **last line** of your final output (trailing whitespace is fine, additional content after is not).

| `<state>` | When to emit | Wrapper does |
|---|---|---|
| `continue` | One issue successfully merged this iteration. The session completed step 8 normally. | Re-invoke immediately. |
| `all-done` | Step 1 found no open milestones in the repo. | Stop the loop; work is complete. |
| `stuck` | Step 3 found that the current milestone has no implementable issues (all blocked or assigned to others). | Stop the loop; human attention needed to fix the dependency graph. |
| `error` | Any pre-flight failure, merge conflict, test failure, auth failure, missing git remote, or any other unexpected STOP. | Stop the loop; human attention needed. |

**This marker is non-negotiable.** Every terminating code path MUST emit it. If you STOP for any reason that isn't `all-done` or `stuck`, the marker is `error`. If you complete normally, the marker is `continue`. No silent exits.

## Progress markers (verbose-mode visibility)

The ralph-loop wrapper runs this skill headlessly, so long silent periods (especially during subagent dispatches) leave the user with no sense of what's happening. To fix that:

**At the start of each numbered workflow step, emit a single-line progress marker to your output before doing any tool calls:**

```
▶ Step <N>: <short description of what's about to happen>
```

Examples:

```
▶ Step 1: Finding current milestone...
▶ Step 5: Pre-flight checks...
▶ Step 6: Dispatching implementer subagent for issue #14...
▶ Step 7: Polish decision: skip (small diff, all criteria met)
▶ Step 8: Merging issue #14 into main...
```

…or, when polish runs:

```
▶ Step 7: Polish decision: run (complex label, implementer flagged a TODO)
▶ Step 7: Dispatching polisher subagent...
```

These markers cost almost nothing and dramatically improve visibility. Emit them eagerly — before the model starts a long tool call (like an `Agent` dispatch) is the most valuable place, since otherwise the user sees nothing for the duration of the subagent's work.

Within a step, additional `▶` lines for sub-phases are welcome but optional. The required minimum is one marker per step.

The `▶` prefix is distinct from `RALPH_EXIT:` so the wrapper's grep is unaffected.

## Required sister skills

You MUST be familiar with `ss-agile-managing-issues` for every `gh` command. Invoke it if you haven't already.

The two subagents you dispatch each rely on their own skill:
- Implementer → `ss-agile-implementing-an-issue`
- Polisher → `ss-agile-polishing-an-issue`

## Inputs

This skill takes **no arguments** from the slash command. It always queries GitHub for the current milestone and picks the next issue from there.

Repo inference comes from the current working directory's git remote:

```bash
gh repo view --json owner,name --jq '.owner.login + "/" + .name'
```

If the cwd is not a git repo with a GitHub remote, STOP and tell the user to invoke from inside the target repo's working tree. End with `RALPH_EXIT: error`.

Always pass `-R OWNER/REPO` to every `gh` call so behavior is explicit and reproducible.

Authentication is assumed configured locally. If `gh auth status` fails, stop and tell the user. End with `RALPH_EXIT: error`.

## Workflow

### 1. Find the current milestone

The "current" milestone is the open milestone with the lowest GitHub `number`. Because the populate flow creates milestones in Sprint K order via a single serial bash invocation, milestone numbers are monotonic in Sprint K — so the lowest-numbered open milestone is the earliest sprint with work remaining.

```bash
gh api "repos/OWNER/REPO/milestones?state=open" \
  --jq 'sort_by(.number) | .[0] | {number, title, open_issues, closed_issues}'
```

**If the result is `null` (no open milestones), STOP with a clean exit signal.** Print:

> "All milestones in `OWNER/REPO` are closed. Nothing to advance. If you have more work to plan, use `/ss-agile-populate-issues` or create milestones manually first."

Then on a final line, emit the terminal marker:

```
RALPH_EXIT: all-done
```

**END THE SESSION.**

Otherwise, capture the milestone's `number` and `title` — you'll use both throughout the rest of the workflow (substep 8.9 also needs `MILESTONE_NUMBER` for the milestone-close API call). Briefly tell the user which milestone the session selected:

> "Current milestone: **Sprint 2: Core data model** (#7) — 4 open issues, 2 already closed."

Then proceed to step 2.

### 2. Survey the milestone's issues

```bash
gh issue list -R OWNER/REPO --milestone "<title>" --state open \
  --json number,title,body,labels,assignees,createdAt \
  --limit 200
```

For each open issue, parse its body for:
- A `Depends on: #N` line (or list) → these are blockers
- Acceptance criteria section (any heading like `## Acceptance` / `## Done when`)
- An estimated effort/size if present

Also load the milestone's closed issues so you know which `#N` references are already resolved:

```bash
gh issue list -R OWNER/REPO --milestone "<title>" --state closed \
  --json number,title --limit 200
```

### 3. Pick the next issue (this is the judgment call)

Apply these rules in order:

1. **Filter out blocked issues.** Any issue with an unresolved `Depends on: #N` is excluded — but check whether `#N` is closed (counts as resolved) before excluding.
2. **Filter out in-progress issues.** If an issue already has an assignee that isn't the current user, skip it (someone else is on it).
3. **Among the remaining**, prefer:
   - Foundational work over polish (look at labels like `infrastructure`, `setup`, `core` vs. `polish`, `docs`)
   - Smaller scope first when other things are equal
   - Earlier issue numbers when tied (they were planned first for a reason)
4. **Tie-break with reasoning**, not coin flips. Pick deliberately and be able to explain why.

If nothing is eligible (all blocked, all assigned to others, milestone empty), STOP with a clean exit signal. Print:

> "Current milestone `<title>` (#<number>) is stuck — no implementable issues available. Diagnosis:
> - Blocked by open dependencies: #X, #Y (depends on still-open #Z)
> - Assigned to other users: #A (assigned to @other-user)
> - <other reasons>
>
> This usually means the dependency graph is wrong. Resolve the blocking issues, reassign issues to yourself, or close issues that no longer apply, then re-invoke."

Then on a final line, emit the terminal marker:

```
RALPH_EXIT: stuck
```

**END THE SESSION.**

### 4. Announce the pick (no approval gate)

Output the pick reasoning so it's visible in the ralph-loop logs, then proceed immediately to step 5. Do **NOT** wait for user approval — this skill runs autonomously.

```
Milestone: Sprint 2 — Core data model (3 open, 5 closed)

Picked: #14 — "Add User schema with email + auth fields"

Reasoning: #14 has no open dependencies. Its sibling #15 ("Add Job schema")
depends on #14. Other open issues (#16, #17) are polish items. Starting here
unblocks the most downstream work.

Approach: TDD on the schema definitions, then a migration, then a smoke test
that creates/reads/updates a User. Estimate: ~1 small-medium session.

Branch will be: 14-add-user-schema-with-email-auth-fields (slugified from the issue title, branched from local main).
```

Proceed to step 5 immediately.

### 5. Pre-flight checks and setup

Before setting up the issue, verify the working tree is in a safe state. Each check has an explicit stop-condition — do not silently work around them. All stops are fail-fast clean exits so a ralph loop wrapper can terminate cleanly.

**5a. Working tree must be clean.**

```bash
git status --porcelain
```

If the output is non-empty, STOP. Tell the user: "Working tree has uncommitted changes — commit, stash, or discard them before I can switch to a new feature branch." Do NOT attempt to stash, discard, or commit on their behalf; that's their decision. End with the terminal marker:

```
RALPH_EXIT: error
```

**5b. Starting branch must be the repo default.**

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
DEFAULT=$(gh repo view -R OWNER/REPO --json defaultBranchRef --jq .defaultBranchRef.name)
echo "current=$CURRENT default=$DEFAULT"
```

If `$CURRENT` ≠ `$DEFAULT`, STOP with a clean exit signal:

> "Working tree is on `<CURRENT>`, not the repo default `<DEFAULT>`. This is unexpected — a successful prior cycle should have ended on `<DEFAULT>`. Switch manually (`git checkout <DEFAULT>`) before re-invoking. Ralph loop should terminate."

Do **NOT** auto-switch — silently moving off a feature branch could hide or discard work that's there for a reason. Fail-fast is the ralph-loop-safe behavior. End with the terminal marker:

```
RALPH_EXIT: error
```

**5c. No prior local branch should exist for this issue.**

```bash
git branch --list "<N>-*"
```

If the output is non-empty, a local branch from a prior attempt that didn't complete still exists. STOP with a clean exit signal:

> "A local branch matching `<N>-*` already exists from a prior attempt. Either resume it manually (`git checkout <name>` and finish the work yourself), or drop it and re-invoke (`git branch -D <name>` — destructive). Ralph loop should terminate so you can decide."

Do **NOT** auto-resume or auto-delete. Both involve judgment about whether the prior work is valuable; that's a human call. Fail-fast is the ralph-loop-safe behavior. End with the terminal marker:

```
RALPH_EXIT: error
```

**5d. Self-assign and announce.**

```bash
gh issue edit <N> -R OWNER/REPO --add-assignee @me
gh issue comment <N> -R OWNER/REPO --body "Starting work on this issue via ss-agile-advancing-milestones."
```

**5e. Create the feature branch locally, from local `$DEFAULT`.**

Do **NOT** use `gh issue develop`. It creates branches server-side based on `origin/<DEFAULT>` HEAD, which may be stale when prior ralph iterations have merged into local `$DEFAULT` without pushing. The new branch would be missing the very code prior iterations produced. It also leaves a stale remote branch behind on every iteration, accumulating cruft. We don't open PRs, so the server-side issue↔branch linkage `gh issue develop` provides has no functional value here — only the cosmetic "Development" sidebar entry on the GitHub issue page.

Instead, create the branch locally with plain git, slugifying the issue title to match the convention `gh issue develop` would have produced:

```bash
# Slugify: lowercase, replace runs of non-alphanumerics with single hyphen, trim hyphens
SLUG=$(echo "<ISSUE_TITLE>" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
BRANCH="<N>-$SLUG"

git checkout -b "$BRANCH" "$DEFAULT"
```

Substitute `<ISSUE_TITLE>` with the actual issue title and `<N>` with the issue number. Example: issue #14 "Add User schema with email + auth fields" → branch `14-add-user-schema-with-email-auth-fields`.

The branch starts at local `$DEFAULT`'s tip, picking up all prior iterations' work. It is **never pushed** in this flow — it lives and dies locally.

Confirm:

```bash
git branch --show-current   # should print $BRANCH
git log -1 --oneline         # should match local $DEFAULT's tip (or be 1 commit ahead if you've already committed in this session)
```

If `git checkout -b` fails (branch already exists despite the 5c check passing, working tree dirty despite 5a), STOP with `RALPH_EXIT: error`.

### 6. Dispatch the implementer

Use the `Agent` tool with `subagent_type: general-purpose`. The prompt must be **self-contained** — the subagent does not see this conversation's history.

Brief template (adapt for the specific issue):

```
Invoke the `ss-agile-implementing-an-issue` skill via the Skill tool before doing anything else, then follow it.

## Issue to implement
- Repo: OWNER/REPO
- Issue number: #N
- Branch (already checked out in the worktree): <branch-name>

## Issue body
<<<paste the full issue body verbatim>>>

## Acceptance criteria (extracted from the issue body)
<<<list them as a checklist>>>

## Codebase notes the coordinator surfaced
<<<any one-time orienting context the implementer should know — file locations, conventions, existing patterns to follow. Keep terse.>>>

## What to report back
When you believe the issue is done, return a structured report:
- Commits made (hashes + one-line summary each)
- Tests run and their results
- Any acceptance-criteria item you couldn't satisfy (and why)
- Anything the polisher should know (e.g. "I left a TODO at user.ts:42 about Unicode; not in scope for this issue")

Do not push the branch — this flow is local-merge-only.
```

Run the agent. When it returns its report, capture it for the polisher's brief.

### 7. Decide whether to polish; dispatch the polisher only if warranted

Polish is **opt-in per issue**. Skip by default. Polish costs real tokens (a full second pass over the diff) for usually-marginal returns, so reserve it for issues where the value floor — the acceptance-criteria sanity check — actually pays off.

**Run polish when ANY of these signals fires:**

- The issue has a `complex`, `gnarly`, `risky`, `refactor`, `core`, or `infrastructure` label.
- The issue body lists more than 3 acceptance criteria (more places for something to slip).
- The implementer's report flagged any criterion as "couldn't satisfy" or "partially done".
- The implementer's report mentions TODOs left in code, scope cuts, or "things the polisher should know".
- The diff is large — rough heuristic: more than ~200 lines changed across all files. Quick check: `git diff --shortstat <DEFAULT>...HEAD`.

**Skip polish when none of those fire.** Typical skip cases: a small, single-purpose issue with ≤ 3 criteria, all reported as met, no implementer notes, modest diff.

**Mixed signals:** favor running polish. The token cost is bounded; the criteria sanity check is the load-bearing value.

Announce the decision in one line for ralph-loop log visibility, e.g.:

```
▶ Step 7: Polish decision: skip (small diff, 2 criteria all met, no implementer notes)
```

or:

```
▶ Step 7: Polish decision: run (issue labeled `complex`; implementer flagged a TODO at user.ts:42)
```

**If skipping**, proceed directly to Step 8. Do **not** dispatch a polisher. The polisher's report fields in the final summary (Step 10) become "skipped" and the issue-comment step (8.7) is also skipped — there's nothing to post.

**If running**, dispatch the polisher subagent below. The polisher is **not a reviewer** — it has no verdict and no veto power. It improves the diff incrementally (naming, comments, structure within scope) and does a lightweight acceptance-criteria sanity check, surfacing any plainly-unmet items as info. The merge happens after polish completes regardless of what the polisher reports.

Use the `Agent` tool with `subagent_type: general-purpose`:

```
Invoke the `ss-agile-polishing-an-issue` skill via the Skill tool before doing anything else, then follow it.

## Scope
- Repo: OWNER/REPO
- Issue: #N
- Feature branch (currently checked out): <branch-name>
- Default branch (compare against): <DEFAULT>
- Diff command: `git diff <DEFAULT>...<branch-name>`

There is no PR — operate on the local diff.

## Issue body (source of truth for acceptance criteria)
<<<paste full issue body verbatim>>>

## Implementer's report
<<<paste the structured report from step 6>>>

## Your job
Polish the implementation within the scope of the existing diff. Improve naming, comments, structure where useful — without changing behavior. Run tests after each meaningful change; revert any polish change that breaks them. Do a lightweight acceptance-criteria sanity check and flag plainly-unmet items as info (no veto).

You do NOT block the merge. "No changes made" is a valid outcome.

## What to report back
- Changes made: list of polish commits with brief descriptions, or explicit "no changes" if nothing worth improving.
- Criteria sanity check: any acceptance criteria that look plainly unmet from the diff (info only).
- Tests run: command + result.
- Any polish changes you reverted because they broke tests.
- Other observations (optional, max 3).
```

Run the agent. Capture its report — you'll use it in the final summary in step 8.

### 8. Merge and close out the issue

The merge happens unconditionally after Step 7 — whether polish ran or was skipped. When polish did run, its report is *informational* — surfaced to the user in the final summary, but never gating the merge. Even if the polisher flagged criteria as possibly unmet, MERGE ANYWAY — the user reviews the heads-up in the post-merge summary and can roll back via `git reset --hard <pre-merge-sha>` if needed. Do **NOT** pause to confirm; that would break ralph-loop autonomy.

1. Switch to the default branch:
   ```bash
   git checkout <DEFAULT>
   ```
2. Ensure the default branch is up-to-date with origin (cheap safety check):
   ```bash
   git pull --ff-only origin <DEFAULT>
   ```
   If this fails due to divergence (local commits on default that aren't on origin, or vice versa), STOP and surface — do not auto-rebase or force. End with `RALPH_EXIT: error`.
3. Merge with `--no-ff` so the issue boundary is preserved in history:
   ```bash
   git merge --no-ff <branch-name> -m "Merge #<N>: <issue-title>"
   ```
   If the merge has conflicts, STOP and surface — do not attempt automatic resolution. End with `RALPH_EXIT: error`.
4. Capture the merge commit hash: `MERGE_SHA=$(git rev-parse HEAD)`.
5. If the project has an obviously-named test command (look for `npm test`, `pytest`, `cargo test`, etc. in `package.json` / `pyproject.toml` / `Makefile`) and it completes in reasonable time, run it on the default branch post-merge. If it fails, STOP and surface to the user — do **NOT** auto-revert. The user decides whether to fix-forward or roll back. End with `RALPH_EXIT: error`.
6. Delete the feature branch locally:
   ```bash
   git branch -d <branch-name>
   ```
   Lowercase `-d` refuses to delete unless the branch is fully merged — a safety net. If it errors, something's wrong; do not escalate to `-D` without investigating.
7. If polish ran in Step 7 and the polisher returned any criteria-sanity-check flags or "other observations" worth recording, post them as a comment on the issue:
   ```bash
   gh issue comment <N> -R OWNER/REPO --body "Polisher notes (info, not blocking):
   - <flag or observation>
   - ..."
   ```
   Skip this substep if polish was skipped in Step 7, or if it ran but had no flags and no observations.
8. Close the issue:
   ```bash
   gh issue close <N> -R OWNER/REPO --reason completed \
     --comment "Implementation complete. Merged locally into <DEFAULT> as $MERGE_SHA."
   ```
9. **Close the milestone if it has no open issues left.** This was the whole point of organizing work into milestones — when the last issue closes, the milestone is done.

   ```bash
   REMAINING=$(gh issue list -R OWNER/REPO --milestone "<milestone-title>" --state open --json number --jq 'length')
   ```

   - If `$REMAINING` is `0`, close the milestone:
     ```bash
     gh api -X PATCH repos/OWNER/REPO/milestones/<MILESTONE_NUMBER> -f state=closed
     ```
     Remember `<MILESTONE_NUMBER>` from step 1 (it was returned alongside the title when you resolved the milestone). Keep this value in working context throughout the session for this step.
   - If `$REMAINING` is `>0`, do nothing — other open issues remain in the milestone.

   Do NOT prompt the user for confirmation before closing the milestone. The trigger (zero open issues) is unambiguous, and milestones can be reopened later if needed.

10. Tell the user. Include polisher highlights so they can decide whether to push or roll back before pushing:
    ```
    Done. #<N> merged into <DEFAULT> (commit <MERGE_SHA>). Feature branch deleted. Issue closed.

    Milestone "<milestone-title>" had no remaining open issues — closed it too.   (omit this line if remaining > 0)

    Polish: <N changes made — brief list>      (or: "No changes — diff was already clean."; or: "Skipped — <reason from Step 7>" if polish was skipped)
    Criteria heads-up: <list of flagged criteria>   (omit this line if no flags, or if polish was skipped)
    Other observations: <list>                       (omit if none, or if polish was skipped)

    Push <DEFAULT> to origin when you're ready:
        git push origin <DEFAULT>

    If anything in the polisher's heads-up concerns you, roll back before pushing:
        git reset --hard <pre-merge SHA>
    ```

    Then on a final line, emit the terminal marker:

    ```
    RALPH_EXIT: continue
    ```
11. **END THE SESSION.**

## Failure modes and how to handle them

Every row that says "STOP" also requires emitting a `RALPH_EXIT:` marker per the contract above. The third column names which.

| Situation | What to do | Marker |
|---|---|---|
| `gh auth status` fails | Stop. Tell user to authenticate. | `error` |
| No open milestones in the repo | Already handled by step 1 — clean "all-done" exit signal. Ralph loop should terminate. | `all-done` |
| Current milestone has no implementable issues (all blocked or assigned to others) | Already handled by step 3 — clean "stuck" exit signal with diagnosis. Ralph loop should terminate. | `stuck` |
| Implementer subagent crashes / returns no report | Stop. Report to user; do not merge with no implementation. | `error` |
| Polisher subagent crashes / returns no report | Skip polish and proceed to merge anyway — polish is non-blocking by design. Note the crash in the final user summary so the user knows polish didn't run. | `continue` (merge still happened) |
| Merge conflict during step 8 | STOP. Surface the conflict to the user; do not attempt automatic resolution. Feature branch is still in place; user resolves manually. | `error` |
| Tests fail on default branch after merge | STOP. Surface the failure to the user. Do NOT auto-revert. User decides: fix-forward, or `git reset --hard <pre-merge-sha>` and re-do. | `error` |
| `git branch -d` refuses to delete | Investigate why (branch isn't fully merged?). Do not escalate to `-D` without confirming the branch is truly safe to drop. | `error` |
| Working tree dirty at startup | Already handled by 5a — STOP, user resolves. Do not stash or discard. | `error` |
| Already on a non-default branch | Already handled by 5b — STOP with a clean exit signal. User resolves manually before re-invoking. | `error` |
| Branch already linked to this issue | Already handled by 5c — STOP with a clean exit signal. User resumes or drops the stale branch manually before re-invoking. | `error` |
| `git checkout -b` fails for an unexpected reason | Report the exact error to the user; do not retry blindly. | `error` |

## What you do NOT do

- **You don't prompt the user for confirmation at any step.** The flow runs autonomously from start to finish. The only pauses are clean exits — when there's no work, when state is unexpected, or when something fails irrecoverably. This is required for ralph-loop autonomy.
- You don't write code. The implementer does.
- You don't polish code. The polisher does.
- You don't gatekeep quality. There is no APPROVE/REJECT verdict; the merge happens after Step 7 (whether polish ran or was skipped) regardless of any polisher report.
- You don't open a GitHub PR. This flow is local-merge-only.
- You don't push the default branch to origin after merging — that's the user's call.
- You don't auto-revert a merge if post-merge tests fail. Surface the failure; user decides.
- You don't auto-resolve unexpected state (dirty tree, wrong branch, stale linked branch). Fail-fast with a clean exit signal so the ralph loop can terminate cleanly.
- You don't take on more than one issue. One issue per session.
