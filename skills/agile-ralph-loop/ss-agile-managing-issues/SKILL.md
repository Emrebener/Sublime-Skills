---
name: ss-agile-managing-issues
description: Use when creating, reading, listing, searching, editing, commenting on, closing/reopening, or managing the labels, milestones, assignees, pins, locks, transfers, or linked branches of GitHub issues via the `gh` CLI. Also covers creating and managing milestones (which `gh` only exposes through `gh api`).
---

# Managing GitHub Issues

Reference for managing GitHub issues from the command line using the `gh` CLI. Covers the full `gh issue` surface, milestone management (which `gh` does not expose directly), plus patterns that aren't obvious from `--help`.

**Autonomy note:** This is a pure reference skill — look up the command and proceed. When invoked by an autonomous skill (`ss-agile-*`), do NOT introduce confirmations or interactive prompts beyond what `gh` itself requires. Prefer non-interactive flags everywhere (`--title`, `--body`, `--body-file -`, `--yes`); never use `--web`.

## Prerequisites

- `gh` is installed and authenticated (`gh auth status` shows a logged-in account).
- The working directory is inside a git repo with a GitHub remote, OR every command passes `-R OWNER/REPO`.
- Some operations need extra scopes: adding/removing projects requires the `project` scope (`gh auth refresh -s project`).

## Issue identifiers

Every command that targets an issue accepts either:
- a number: `123`
- a full URL: `https://github.com/OWNER/REPO/issues/123`

`gh issue edit` is the only command that accepts **multiple** issue numbers in one invocation.

## Quick reference

### Core CRUD

| Action | Command |
|---|---|
| Create (interactive) | `gh issue create` |
| Create (non-interactive) | `gh issue create --title "T" --body "B"` |
| Create from file body | `gh issue create --title "T" --body-file path.md` |
| Create with metadata | `gh issue create --title "T" --body "B" --label bug --label "help wanted" --assignee @me --milestone "v1.0"` |
| View | `gh issue view 123` |
| View with comments | `gh issue view 123 --comments` |
| View in browser | `gh issue view 123 --web` |
| List (open) | `gh issue list` |
| List (all states) | `gh issue list --state all` |
| List (closed) | `gh issue list --state closed` |
| Edit title/body | `gh issue edit 123 --title "T" --body "B"` |
| Edit multiple | `gh issue edit 23 34 --add-label "help wanted"` |
| Close | `gh issue close 123` |
| Close with reason | `gh issue close 123 --reason "not planned"` |
| Close as duplicate | `gh issue close 123 --duplicate-of 456` |
| Reopen | `gh issue reopen 123 --comment "re-checking"` |
| Delete | `gh issue delete 123 --yes` |
| Cross-repo (any command) | append `-R owner/repo` |

### Comments

| Action | Command |
|---|---|
| Add comment | `gh issue comment 123 --body "text"` |
| Add from file | `gh issue comment 123 --body-file notes.md` |
| Add from stdin | `echo "hi" \| gh issue comment 123 --body-file -` |
| Edit last comment (by you) | `gh issue comment 123 --edit-last --body "new text"` |
| Edit-or-create last | `gh issue comment 123 --edit-last --create-if-none --body "text"` |
| Delete last comment (by you) | `gh issue comment 123 --delete-last --yes` |
| View all comments | `gh issue view 123 --comments` |

`--edit-last` and `--delete-last` only act on **your own** most recent comment on the issue.

### Labels, milestones, assignees, projects

| Action | Command |
|---|---|
| Add label(s) | `gh issue edit 123 --add-label bug --add-label "help wanted"` |
| Remove label(s) | `gh issue edit 123 --remove-label stale` |
| Swap labels in one call | `gh issue edit 123 --add-label bug --remove-label triage` |
| Set milestone | `gh issue edit 123 --milestone "v1.0"` |
| Clear milestone | `gh issue edit 123 --remove-milestone` |
| Assign yourself | `gh issue edit 123 --add-assignee @me` |
| Unassign yourself | `gh issue edit 123 --remove-assignee @me` |
| Assign Copilot | `gh issue edit 123 --add-assignee @copilot` |
| Assign by login | `gh issue edit 123 --add-assignee monalisa,hubot` |
| Add to project | `gh issue edit 123 --add-project "Roadmap"` |
| Remove from project | `gh issue edit 123 --remove-project v1` |

Labels and milestones must already exist on the repo — `gh` does **not** create them on the fly. To create them first:
- Labels: `gh label create NAME --color RRGGBB --description "..."`
- Milestones: `gh` has no `gh milestone` subcommand; use `gh api` (see "Managing milestones" below).

### Filtering & search

| Action | Command |
|---|---|
| By label | `gh issue list --label bug --label "help wanted"` |
| By author | `gh issue list --author monalisa` |
| By assignee | `gh issue list --assignee @me` |
| By milestone | `gh issue list --milestone "v1.0"` |
| By mention | `gh issue list --mention @me` |
| Raise limit (default 30) | `gh issue list --limit 200` |
| Free-form search | `gh issue list --search "error no:assignee sort:created-asc"` |
| Your relevant issues (assigned/authored/mentioned) | `gh issue status` |

`--search` uses GitHub's issue/PR search syntax (`is:open`, `no:label`, `created:>2026-01-01`, etc.). Full reference: https://docs.github.com/search-github/searching-on-github/searching-issues-and-pull-requests

When `--search` is used, the other filter flags are still honored and AND-ed together.

### State, pinning, locking, transfer

| Action | Command |
|---|---|
| Pin | `gh issue pin 123` |
| Unpin | `gh issue unpin 123` |
| Lock conversation | `gh issue lock 123 --reason resolved` |
| Unlock conversation | `gh issue unlock 123` |
| Transfer to another repo | `gh issue transfer 123 owner/other-repo` |

`--reason` for `lock` accepts: `off_topic`, `resolved`, `spam`, `too_heated`.

### Linked development branches

| Action | Command |
|---|---|
| Create branch linked to issue | `gh issue develop 123 --checkout` |
| Branch from a base branch | `gh issue develop 123 --base main --checkout` |
| Custom branch name | `gh issue develop 123 --name feat/123-thing --checkout` |
| List linked branches | `gh issue develop 123 --list` |
| Branch in a fork | `gh issue develop 123 --branch-repo myuser/repo` |

The branch is registered on the issue and a PR opened from it will auto-link.

### JSON output & scripting

Any read command (`view`, `list`, `status`) supports `--json FIELDS [--jq EXPR | --template TPL]`.

| Action | Command |
|---|---|
| List as JSON | `gh issue list --json number,title,state,labels` |
| Filter with jq | `gh issue list --json number,title --jq '.[] \| "#\(.number) \(.title)"'` |
| Limit fields, raise count | `gh issue list --limit 500 --json number,title,labels --jq '.[] \| select(.labels[].name == "bug")'` |
| Single issue body | `gh issue view 123 --json body --jq .body` |
| Just numbers, newline-separated | `gh issue list --json number --jq '.[].number'` |

Available JSON fields (same on `view`, `list`, `status`):
`assignees, author, body, closed, closedAt, closedByPullRequestsReferences, comments, createdAt, id, isPinned, labels, milestone, number, projectCards, projectItems, reactionGroups, state, stateReason, title, updatedAt, url`

## Managing milestones

`gh` has no `gh milestone` subcommand. All milestone operations go through `gh api` against the REST endpoint `repos/:owner/:repo/milestones`. Path placeholders `:owner` and `:repo` are auto-substituted when running inside a repo; pass `-R owner/repo` or expand them manually when targeting another repo.

| Action | Command |
|---|---|
| List open milestones | `gh api repos/:owner/:repo/milestones` |
| List all milestones | `gh api "repos/:owner/:repo/milestones?state=all"` |
| Create milestone | `gh api repos/:owner/:repo/milestones -f title="Sprint 1" -f description="Foundation work" -f due_on="2026-06-01T00:00:00Z"` |
| Create without due date | `gh api repos/:owner/:repo/milestones -f title="Sprint 1" -f description="..."` |
| Get milestone by number | `gh api repos/:owner/:repo/milestones/3` |
| Update milestone | `gh api -X PATCH repos/:owner/:repo/milestones/3 -f title="Sprint 1 (revised)" -f state=open` |
| Close milestone | `gh api -X PATCH repos/:owner/:repo/milestones/3 -f state=closed` |
| Delete milestone | `gh api -X DELETE repos/:owner/:repo/milestones/3` |

Key fields when creating:
- `title` (required, string)
- `state` (`open` / `closed`, default `open`)
- `description` (string)
- `due_on` (ISO 8601 timestamp, e.g. `2026-06-01T00:00:00Z`)

To capture the number of a freshly created milestone:

```bash
MS_NUM=$(gh api repos/:owner/:repo/milestones \
  -f title="Sprint 1" -f description="..." \
  --jq .number)
gh issue create --title "First task" --milestone "Sprint 1" --body "..."
# or assign by name later:
gh issue edit 123 --milestone "Sprint 1"
```

Note: `gh issue edit --milestone NAME` and `gh issue create --milestone NAME` reference milestones by **title**, not number. Pick titles that won't collide.

## Common patterns

### Multi-line body from a heredoc

```bash
gh issue create --title "Crash on startup" --body "$(cat <<'EOF'
## Steps
1. Run `app --serve`
2. Visit localhost:3000

## Expected
Page loads.

## Actual
Crashes with stack trace below.
EOF
)"
```

For longer bodies, write a file and use `--body-file path.md`. Use `--body-file -` to pipe from another command.

### Link a PR to close an issue automatically

Put one of these keywords in the PR body (case-insensitive): `Closes #N`, `Fixes #N`, `Resolves #N`. When the PR merges, GitHub closes the issue. Other variants: `close`, `closed`, `fix`, `fixed`, `resolve`, `resolved`.

For cross-repo: `Closes owner/repo#N`.

### Find linking PRs for an issue

```bash
gh issue view 123 --json closedByPullRequestsReferences --jq '.closedByPullRequestsReferences[]'
```

### Bulk operation: close all issues with a label

```bash
gh issue list --label stale --limit 1000 --json number --jq '.[].number' \
  | xargs -I{} gh issue close {} --reason "not planned" --comment "Closing stale."
```

### "My open issues across the repo" one-liner

```bash
gh issue list --search "is:open assignee:@me" --json number,title,updatedAt
```

### Create and immediately start work

```bash
NUM=$(gh issue create --title "Refactor auth" --body "..." --label refactor \
        --json number --jq .number)
gh issue develop "$NUM" --checkout
```

Note: `gh issue create` itself does not accept `--json`/`--jq` — it prints the issue URL. To capture the number, either parse the URL or `gh issue list --search "..." --json number` after creation. The snippet above works on `gh` 2.79+ where `create` returns the URL on stdout; if older, use:

```bash
URL=$(gh issue create --title "T" --body "B")
NUM=${URL##*/}
gh issue develop "$NUM" --checkout
```

## Gotchas

- **Labels/milestones must exist first.** `--label foo` on a nonexistent label fails. Create labels with `gh label create foo --color "ededed"`.
- **`--state` default is `open`.** To see closed too: `--state all` or `--state closed`.
- **List `--limit` defaults to 30.** Pagination silently truncates if you forget to raise it.
- **Close reasons are exact strings.** Valid: `completed`, `not planned`, `duplicate`. Anything else errors.
- **`--web` opens a browser.** Never use in scripts/CI — it blocks and is non-deterministic.
- **`--edit-last` / `--delete-last` are scoped to *your* comments only**, not the latest comment by anyone.
- **`gh issue edit` accepts multiple numbers** (`gh issue edit 1 2 3 --add-label bug`); most other commands take exactly one.
- **`gh issue delete` is irreversible** and requires `--yes` for non-interactive use. Prefer `close --reason "not planned"` unless the issue is truly garbage (spam, accidental).
- **`@me` / `@copilot` only work for the assignee flags**, not author/mention filters — those need a real login.
- **Cross-repo `-R` flag** can go anywhere on the command line, but commands run on the **current** repo unless you set it. Easy to accidentally edit the wrong repo's issue when working in a clone.
- **Free-form `--search` overrides default state filter.** `gh issue list --search "is:closed"` works even though the default state is `open` — but `--search "anything" --state open` is redundant and `is:` in the query wins.

## When to use `gh api` instead

`gh issue` is convenient for the common 90%. Drop down to `gh api` when you need:

- Reactions: `gh api repos/:owner/:repo/issues/123/reactions`
- Timeline events (closed-by, referenced, cross-references): `gh api repos/:owner/:repo/issues/123/timeline`
- Mutating fields `gh issue edit` doesn't expose (e.g., issue type on GraphQL).
- Pagination beyond `--limit` for very large queries — `gh api --paginate graphql -f query=...`.
- Bulk operations where rate-limit headers matter.

Example: count open issues by label, server-side:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!) {
    repository(owner:$owner, name:$repo) {
      issues(states:OPEN, first:0) { totalCount }
    }
  }' -F owner=OWNER -F repo=REPO
```

## When NOT to use this skill

- The user is asking about pull requests, not issues — those use `gh pr ...` (different subcommand surface).
- The user wants to edit GitHub Discussions, Projects, or Releases — separate `gh` subcommands.
- The user wants a one-off web action (filing a single issue via the UI) — just open the repo in a browser.
