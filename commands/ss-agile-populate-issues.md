---
description: Plan and pre-populate N sprints (milestones) of GitHub issues from a goals document
argument-hint: <repo-url> <num-sprints> <path-to-goals-file>
---

You are pre-populating a GitHub repository with a coherent set of issues organized across N sprints. Each sprint is represented by a GitHub **milestone** (GitHub has no native "sprint" entity; milestones are the standard substitute). Issues are distributed across these milestones in a logical order so that the work makes sense as a progression.

You MUST use the `ss-agile-managing-issues` skill for all GitHub interaction. Invoke it now via the `Skill` tool before doing anything else.

## Arguments

Three positional, whitespace-separated arguments:

1. **`$1` — repo URL** (e.g. `https://github.com/owner/repo` or `git@github.com:owner/repo.git`). Extract `OWNER/REPO` from this. The directory you're running in is **not** assumed to be that repo — always pass `-R OWNER/REPO` to every `gh` call.
2. **`$2` — number of sprints** (a positive integer, the count of milestones to create).
3. **`$3` — path to a goals document** (a local file containing free-form text — typically markdown — describing what is to be built). May be absolute or relative to the current working directory. The file is the single source of truth for what gets planned; do not also accept goals from chat unless the user explicitly amends.

If any of the three is missing or malformed, stop and ask the user to re-invoke.

Authentication is assumed to already be configured locally (via `~/.config/gh/hosts.yml`, `GH_TOKEN`, or a credential helper). This command does **not** accept a token argument; do not prompt for one.

## Workflow

### 0. Read the goals document

Resolve `$3` to an absolute path (if relative, against the current working directory — find it with `pwd` if needed). Then read the file with the `Read` tool. If the file does not exist, is empty, is not text, or contains under ~3 sentences of concrete intent, STOP and tell the user what's wrong with their input. Do not attempt to proceed with thin or missing goals.

Keep the full contents in working context — you'll use them to design milestones and issues in steps 3–4.

### 1. Verify auth and repo access

```bash
gh auth status                          # confirm gh is authenticated
gh repo view OWNER/REPO --json name,owner,visibility,defaultBranchRef \
  --jq '{repo: (.owner.login + "/" + .name), default: .defaultBranchRef.name, visibility}'
```

If `gh auth status` reports no logged-in account, stop and tell the user to run `gh auth login` (or set `GH_TOKEN`) before re-invoking this command — do not attempt to authenticate on their behalf.

If `gh repo view` fails (404, permission denied), stop and report the error. Do **not** proceed to issue creation.

### 2. Survey existing state

Before planning anything new, check what's already there so you don't duplicate or collide:

```bash
gh api "repos/OWNER/REPO/milestones?state=all" --jq '.[] | {number, title, state}'
gh label list -R OWNER/REPO
gh issue list -R OWNER/REPO --state all --limit 200 --json number,title,state,milestone
```

If milestones with names that would collide with your planned sprint titles already exist, propose alternative names (e.g. add a suffix). Never silently overwrite.

### 3. Plan (do NOT execute writes yet)

Read the goals carefully. Then design:

- **N milestones**, one per sprint. For each:
  - `title` MUST follow the form `Sprint K: <Theme>`, where K is a positive integer starting at 1 and incrementing by 1 in the order of planned progression. With 3 sprints, the titles are exactly `Sprint 1: <theme1>`, `Sprint 2: <theme2>`, `Sprint 3: <theme3>`, in that order. K is what humans read; the milestone's GitHub-assigned `number` is a separate database ID, but creation order will keep them aligned with K (see step 5b).
  - `description` (1–3 sentences describing the sprint's theme and what "done" looks like)
  - (Optional) `due_on` — leave blank unless the user has supplied a cadence; do not invent dates
- A list of **issues for each milestone**. For each issue:
  - `title` (imperative, e.g. "Add user authentication" not "User authentication")
  - `body` (2–6 short sections: context, acceptance criteria, suggested approach if non-obvious, dependencies/blocking-issues by placeholder names; written so a future session can act on it)
  - `labels` (a short list, drawn from existing repo labels where possible; if new labels are needed, propose them with rationale and a color)
  - `assignees` (default: empty — let the user decide)

**Ordering principle:** Issues across sprints must form a logical progression. Foundation/scaffolding work first; integration and polish later. Within a sprint, sequence so that earlier issues unblock later ones. Note dependencies in issue bodies using the convention `Depends on: <issue title>` (you'll replace these with real `#N` references after creation in step 5b).

**Sizing principle:** A sprint should contain a coherent, finite chunk of work — typically 4–10 issues for most projects. If the goals don't decompose into N sprints cleanly, say so and propose the count you'd actually recommend; ask the user before proceeding.

### 4. Present the plan and wait for approval

Output the plan as a structured summary the user can scan:

```
SPRINT 1: <title>
  Description: <...>
  Issues:
    1. <title>
       Labels: <l1>, <l2>
       Body preview: <first line>
    2. ...

SPRINT 2: ...
```

Also list:
- **New labels to be created** (with color + description), if any.
- **Total counts:** N milestones, M issues, K new labels.

Then ask explicitly: *"Approve creating the above in `OWNER/REPO`? (yes / changes / cancel)"*

Do NOT proceed until the user says yes (or equivalent affirmation). If they request changes, revise the plan and re-present.

### 5. Execute (only after approval)

Order of operations matters — milestones and labels must exist before issues reference them.

**5a. Create any missing labels:**

```bash
gh label create "name" --color "RRGGBB" --description "..." -R OWNER/REPO
```

**5b. Create milestones — STRICTLY SERIALLY, in planned order.**

GitHub assigns milestone numbers in the order it *receives* create requests. If you issue requests in parallel (multiple Bash tool calls in one message), the assigned numbers come out non-deterministic — `Sprint 2` may end up with a lower milestone number than `Sprint 1`. To prevent that:

**Create ALL milestones inside a SINGLE Bash tool invocation, as sequential commands (or a loop), in the same order as your plan. Do NOT split milestone creation across multiple parallel Bash tool calls.**

```bash
# All in ONE Bash tool call, sequentially:
gh api repos/OWNER/REPO/milestones -f title="Sprint 1: <theme>" -f description="..." --jq '{number, title}'
gh api repos/OWNER/REPO/milestones -f title="Sprint 2: <theme>" -f description="..." --jq '{number, title}'
gh api repos/OWNER/REPO/milestones -f title="Sprint 3: <theme>" -f description="..." --jq '{number, title}'
# ...one line per planned sprint, in order
```

After creation, verify the GitHub numbers came out monotonic relative to the `Sprint K` integer in the title:

```bash
gh api "repos/OWNER/REPO/milestones?state=all" \
  --jq '.[] | select(.title | startswith("Sprint ")) | "\(.number) \(.title)"' \
  | sort -n
```

The output should show GitHub milestone `number`s increasing in the same order as the Sprint K integer (e.g. `4 Sprint 1: ...`, `5 Sprint 2: ...`, `6 Sprint 3: ...`). The absolute numbers don't need to start at 1 (prior milestones in the repo are fine); what matters is that they're monotonic in K's order.

If the verification shows them out of order (a stray parallel request, or a collision with a prior milestone), STOP and surface to the user. Do NOT auto-correct by deleting and recreating — that's destructive and the user should decide.

Remember the titles — `gh issue create --milestone` references milestones by title, not number.

**5c. Create issues, one per planned issue:**

```bash
gh issue create -R OWNER/REPO \
  --title "..." \
  --body-file - \
  --label l1 --label l2 \
  --milestone "Sprint 1: Foundation" <<'EOF'
<body markdown>
EOF
```

Capture the URL/number of each created issue.

**5d. Stitch dependencies:** After all issues exist, walk back through any bodies that contained `Depends on: <title>` placeholders and edit them to use real `#N` references:

```bash
gh issue edit N -R OWNER/REPO --body-file -
```

(Read the current body with `gh issue view N --json body --jq .body`, substitute the placeholders, write back.)

### 6. Summarize

Print a final report:

- For each milestone: title, URL, number of issues attached.
- For each issue: `#N — title — milestone — labels`.
- A short note on the dependency graph (what's blocked by what) if non-trivial.

Then suggest the next action the user typically takes (e.g. "Start with #N — it has no dependencies.").

## Safety constraints

- **No writes before plan approval.** Steps 1–4 must complete and the user must say yes before any create/edit call runs.
- **No issue/milestone deletion**, ever, from this command. If the user wants to undo, they do it manually or invoke the issues skill directly.
- **No `--web` flags** anywhere — this command runs non-interactively.
- **Stop and ask** on any ambiguity: missing args, thin goals, sprint count that doesn't fit the work, name collisions with existing milestones.
