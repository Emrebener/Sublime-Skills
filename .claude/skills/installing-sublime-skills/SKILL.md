---
name: installing-sublime-skills
description: Use when the user wants to install, refresh, re-symlink, or fix drift in this repo's Sublime-Skills symlinks under ~/.claude/{skills,commands}/ and ~/.codex/skills/ — e.g. after adding, renaming, moving, or deleting a skill, after a git pull, or when the harness can't find a skill it should see.
---

# Installing Sublime-Skills

Refresh the symlinks that expose this repo's skills (and slash commands)
to Claude Code and Codex.

## What the script does

`scripts/install.fish` walks `skills/*/*/SKILL.md` and `commands/*.md` in
this repo and creates / refreshes symlinks at:

- `~/.claude/skills/<skill-name>` — for every skill
- `~/.claude/commands/<file>.md` — for every slash command
- `~/.codex/skills/<skill-name>` — for every skill (Codex has no slash commands)

It's idempotent. Existing symlinks are repointed in place via `ln -sfn`;
new ones are created; broken symlinks (e.g. left over from a rename) are
pruned at the end via `find -xtype l -delete`.

## How to run it

```fish
"$SUBLIME_SKILLS_HOME/scripts/install.fish"
```

Expected output (counts vary with current skill set):

```
Claude Code: linked 40 skills, 2 commands.
Codex:       linked 40 skills.
```

If `SUBLIME_SKILLS_HOME` isn't set, the script prints a setup hint and
exits non-zero — point the user at `docs/SETUP.md`.

## When to suggest running this

- The user added, renamed, moved, or deleted a skill or command
- A `git pull` brought in upstream changes to the `skills/` or `commands/` trees
- A harness reports it can't find a skill that's clearly in the repo
- The user explicitly asks to "reinstall", "refresh symlinks", "fix drift", etc.

## Sister skill

`uninstalling-sublime-skills` — removes every Sublime-Skills symlink from
both harnesses. Use that one when the user wants to remove the install,
not when they want to fix drift (install handles drift on its own).
