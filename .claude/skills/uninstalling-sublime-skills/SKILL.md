---
name: uninstalling-sublime-skills
description: Use when the user wants to uninstall, remove, or wipe this repo's Sublime-Skills symlinks from ~/.claude/{skills,commands}/ and ~/.codex/skills/ — leaves the repo, the SUBLIME_SKILLS_HOME env var, and any non-Sublime symlinks or real directories alone.
---

# Uninstalling Sublime-Skills

Remove every symlink pointing into this repo from the Claude Code and
Codex skill/command directories.

## What the script does

`scripts/uninstall.fish` walks `~/.claude/skills/`, `~/.claude/commands/`,
and `~/.codex/skills/`, and removes any symlink whose target resolves
under `$SUBLIME_SKILLS_HOME`.

Unlike a "remove what the current repo defines" approach, the target-scan
catches **orphans** — symlinks left over from past renames or deletions
whose basenames no longer match anything in the repo. Anything else is
left alone: non-Sublime symlinks, real directories (like an
independently-installed `technical-writing/`), the repo itself, and the
`SUBLIME_SKILLS_HOME` env var line in `~/.config/fish/config.fish`.

## How to run it

```fish
"$SUBLIME_SKILLS_HOME/scripts/uninstall.fish"
```

Expected output (counts vary with what was installed):

```
Claude Code: removed 40 skill symlink(s), 2 command symlink(s).
Codex:       removed 40 skill symlink(s).

Note: the env var line in ~/.config/fish/config.fish is unchanged — remove it manually if uninstalling fully.
```

If `SUBLIME_SKILLS_HOME` isn't set, the script exits with a hint — it
needs the var to know which symlinks belong to Sublime-Skills.

## When to suggest running this

- The user wants to remove Sublime-Skills from a machine
- The user wants a clean slate before reinstalling
- The user explicitly says "uninstall", "remove the symlinks", "wipe", etc.

For a full uninstall, also remind the user to remove the
`set -gx SUBLIME_SKILLS_HOME ...` line from `~/.config/fish/config.fish`
manually.

## Sister skill

`installing-sublime-skills` — installs / refreshes the symlinks. Use that
one for drift caused by renames or new skills (install handles those on
its own — uninstall is only for removal).
