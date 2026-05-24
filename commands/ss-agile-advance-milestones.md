---
description: Auto-pick the current milestone, then advance it by one issue end-to-end (implement, polish, local merge). Designed for ralph-loop re-invocation until all milestones close.
---

You are being invoked to advance milestone progress on a GitHub repo. This command takes **no arguments** — the skill auto-selects the current milestone (the open milestone with the lowest number, i.e. the earliest sprint with work remaining), picks the next logical issue from it, announces the pick to the session output, then drives that one issue end-to-end via the implementer and polisher subagents — **autonomously, with no user-approval pauses anywhere**. The session ends when the issue is merged locally and closed (and the milestone is closed too if that was its last open issue).

You MUST invoke the `ss-agile-advancing-milestones` skill via the `Skill` tool before doing anything else, then follow it.

## Repo resolution

Determine the target repo from the current working directory's git remote:

```bash
gh repo view --json owner,name --jq '.owner.login + "/" + .name'
```

If the cwd is not a git repo with a GitHub remote, stop and tell the user to invoke this command from inside the target repo's working tree.

## Authentication

Auth is assumed configured locally. If `gh auth status` fails, stop. Do not accept a token argument; do not prompt for one.

## Ralph-loop usage

This command is designed to be invoked over and over by an outer wrapper until all milestones are closed. Each invocation is self-contained and exits cleanly in one of three terminal states:

1. **Merged one issue** — the wrapper should invoke again to continue.
2. **All milestones closed** — the skill reports "nothing to advance, all done." The wrapper should terminate.
3. **Current milestone is stuck** — the skill reports "stuck, here's why" with a dependency diagnosis. The wrapper should terminate and surface to the user.

The skill itself surfaces which terminal state it ended in; the wrapper just watches for the "all-done" or "stuck" signals to stop looping.

## What this command does NOT do

- Does not run multiple issues per invocation. One issue, then the session ends.
- Does not prompt for confirmation anywhere. The flow runs autonomously start to finish; the only pauses are clean exits when something is wrong or nothing is left to do.
- Does not open a GitHub PR. Merging is local-only; the issue is closed via `gh issue close` after the merge. The milestone is also closed automatically if the just-closed issue was its last open one.
- Does not push the default branch to origin after merging — the user pushes when ready.
