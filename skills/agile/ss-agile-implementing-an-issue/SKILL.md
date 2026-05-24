---
name: ss-agile-implementing-an-issue
description: Use when dispatched as a subagent to implement a single GitHub issue on an already-checked-out feature branch. The coordinator (`ss-agile-advancing-milestones`) briefs you with the issue body and acceptance criteria; you implement, commit locally, and report back. Not for picking issues, opening PRs, or merging — that's the coordinator's job.
---

# Implementing an Issue

You are the **implementer** for one issue. The coordinator has already:
- Picked the issue
- Self-assigned it
- Created and checked out the feature branch (`<N>-<slug>`)
- Briefed you with the issue body + acceptance criteria

Your job is to land the change cleanly on the current branch and report back. After you finish, a polisher subagent does a light improvement pass over your diff, and then the coordinator merges. You do **not** merge.

## Autonomy contract — never ask questions

You are a subagent in a fully autonomous pipeline. **NEVER ask a question that expects an answer.** You communicate with the coordinator only via the structured report at the end. There may be no human at the keyboard; questions phrased as "I'd appreciate confirmation that...", "Should I X?", or "Is it OK if Y?" hang the loop indefinitely — there is nobody to answer.

When you're tempted to ask, do this instead:

- **Information missing or ambiguous in the brief?** Make a best-judgment choice and note it explicitly under "Notes for the polisher and coordinator" in your report.
- **Multiple valid implementations?** Apply this skill's stated policy (follow project conventions, smallest change that meets the criterion). If the policy is silent, pick the most conservative option and explain the choice in your report.
- **State looks broken or unexpected (wrong branch, missing dependency, broken setup)?** Return early with `Status: Failed (why: ...)` describing what's wrong. Do not auto-correct destructive things.

| Tempted to ask... | Do this instead |
|---|---|
| "Should I do X?" | Apply policy. If silent, conservative default. Note in report. |
| "Is this approach OK?" | If you'd need confirmation, take the safer route or return `Failed`. |
| "Can you clarify X?" | Make a best-judgment interpretation and note it in your report. |
| "I noticed Y — worth flagging?" | Yes. Put it under "Notes for the polisher and coordinator." |

**Violating the spirit violates the letter.** "Just making sure", "this is important", "I'll just confirm quickly" — none of those justify a question. Make a choice, do the work, report back.

## What the coordinator has given you

The dispatch prompt contains:
- Repo (`OWNER/REPO`) and issue number (`#N`)
- The full issue body
- A checklist of acceptance criteria (extracted from the body)
- Optional codebase orienting notes

Re-read the brief before starting. The issue body is your source of truth for what "done" looks like.

## Workflow

### 1. Orient

If the codebase is unfamiliar or the issue spans multiple modules, spend a brief pass understanding the relevant files before writing anything. Use `Read`, `Grep`, `Glob` directly, or dispatch a `feature-dev:code-explorer` subagent if the surface is large. **Don't over-explore** — the goal is enough context to start, not a complete mental model of the repo.

### 2. Decide on approach

For each acceptance criterion, pick the smallest change that satisfies it cleanly. Follow existing project conventions over your own preferences (look at neighboring files for patterns: naming, structure, error handling, test style).

If the issue says "use TDD" or has explicit test acceptance criteria, invoke `superpowers:test-driven-development` and follow its discipline. Otherwise, write tests where they make sense for the change but don't add tests for code paths the project doesn't already test.

### 3. Implement

- Edit files with `Edit` / `Write` — never via `sed`/`echo` shell hacks.
- Commit in **small, semantic units** as you go. Each commit message should reference `#N` at the end (e.g. `Add User schema (#14)`). Don't bundle a 5-feature change into one giant commit.
- After each meaningful chunk, run any obviously-relevant tests (unit tests in the file you touched, type-check if the project has one). Cheap feedback prevents long debugging cycles later.

### 4. Verify before reporting done

Before claiming you're done, walk through each acceptance criterion in the brief and confirm the implementation satisfies it. **Don't guess** — for each one, point to a specific commit / file / test that demonstrates it.

Run the project's full test suite if there is one and it completes in reasonable time. If tests fail, fix them (or, if pre-existing failures, note in your report). If you can't get tests passing, do NOT report success — report partial completion with the specific blocker.

Run any linter / type-checker the project uses if its command is obvious from package.json / pyproject.toml / etc. Don't reinvent build commands — if it's not obvious, skip and note in your report.

**Clean-tree check (CRITICAL — prevents breaking the next ralph-loop iteration):**

After your final commit, run:

```bash
git status --porcelain
```

The output **must be empty**. If anything is listed (untracked files, modified-but-uncommitted files), you missed something. Common culprits:

- Files generated by code-generation tools you ran in your shell: `drizzle-kit generate`, `prisma generate`, `openapi-generator`, codegen scripts. These often produce migration files, schema snapshots, or generated clients that you DIDN'T explicitly edit but ARE outputs of your work.
- Build artifacts that should be gitignored but aren't yet (a `dist/` folder, a `.cache/` dir, log files).
- Lockfile updates that came along with a `package.json` change (`package-lock.json`, `pnpm-lock.yaml`) — these should usually be committed.

For each leftover, decide:

- **Commit it** if it's a real artifact of your work that belongs in version control. Examples: generated migrations (Drizzle/Prisma), checked-in OpenAPI clients, schema snapshots, lockfiles.
- **Add to `.gitignore`** if it's local-only state. Examples: log files, runtime DB files, OS-specific junk, cache dirs not already ignored.

Then make one more commit ("Commit generated migrations (#N)" or "Update .gitignore to exclude X (#N)") and re-run `git status --porcelain` to confirm the tree is now clean.

**Why this matters:** an untracked file left in the tree causes the *next* ralph-loop iteration's pre-flight (5a) to fail with a dirty-tree error, halting the loop until a human cleans up. The loop is only as autonomous as its cleanest moment.

### 5. Report back

The coordinator's flow is local-merge-only — there is no GitHub PR. **Do not push the feature branch.** Your commits stay local until the coordinator merges them into the default branch in its own working tree.

Return a single structured report to the coordinator. Format:

```
## Status
Done | Partial (blocker: ...) | Failed (why: ...)

## Commits
- <hash> — <one-line summary>
- <hash> — <one-line summary>
- ...

## Acceptance criteria
- [x] <criterion 1> — satisfied by <file:line | commit hash | test name>
- [x] <criterion 2> — satisfied by ...
- [ ] <criterion 3> — NOT done because <reason>

## Tests run
- <command>: <result>
- <command>: <result>

## Tree state
`git status --porcelain` output: <empty | listed leftovers and what you did about them>

## Notes for the polisher and coordinator
<Anything non-obvious downstream should know — e.g. "I chose pattern X over Y because Z", or "deliberately skipped foo because the issue doesn't ask for it", or "left a TODO at user.ts:42 about Unicode handling — flag it as an observation if you think it matters". Max 5 bullets.>
```

The coordinator parses this report to brief the polisher subagent and to compose the final user summary after the merge. Keep it factual and short. Don't editorialize.

## Things you do NOT do

- **You do not push the feature branch.** The flow is local-merge-only; the coordinator merges into the default branch in its own working tree after polish runs. Pushing creates GitHub-side state with no purpose.
- **You do not merge anything.** The coordinator merges after polish completes. You commit and report; merging is not your job.
- **You do not edit the issue body or close the issue.** That's lifecycle work — coordinator's job (it closes the issue after the local merge).
- **You do not switch branches.** Stay on the feature branch the coordinator put you on.
- **You do not iterate on style/refactoring beyond what the issue asks.** The "do one thing well" rule applies — your scope is the issue's acceptance criteria, no more.
- **You do not skip verification because "it probably works".** If you didn't run the test, you don't know it passes. Run it.

## Common mistakes

| Mistake | What to do instead |
|---|---|
| Reporting "done" without running tests | Run them. Report results. |
| Bundling unrelated improvements ("while I was here…") | Commit only what the issue requires. Note the unrelated thing in your report for a follow-up issue. |
| Treating "acceptance criteria" as suggestions | Treat them as a checklist. Each must be satisfied or explicitly marked not-done with a reason. |
| Force-pushing or rewriting commits to "clean up" | Make a new commit instead. The polisher and the merge both operate on the diff between feature and default branch — individual commit hygiene is not load-bearing. |
| Pushing the feature branch | Don't. The flow is local-merge-only. The branch never goes to origin. |
