# Setup (personal, fish + Linux)

Repo lives at `~/Projeler/Sublime-Skills/` (version-controlled). Skills can
be symlinked from there into Claude Code's `~/.claude/skills/` or Codex's
`~/.codex/skills/` so the chosen harness picks them up globally. Slash
commands are Claude Code-specific and symlink into `~/.claude/commands/`.
The framework scripts stay at their real location; skills address them via
`$SUBLIME_SKILLS_HOME`.

Three orthogonal pieces:

1. **Claude Code skill discovery** — symlinks into `~/.claude/skills/` (handled by `scripts/install-claude.fish`)
2. **Claude Code slash command discovery** — symlinks into `~/.claude/commands/` (handled by the same script)
3. **Codex skill discovery** — symlinks into `~/.codex/skills/` (handled by `scripts/install-codex.fish`)
4. **Script + scaffold resolution** — `$SUBLIME_SKILLS_HOME` env var pointing at the real repo (manual, one-time)

## 1. Set `SUBLIME_SKILLS_HOME`

Add this line to `~/.config/fish/config.fish`:

```fish
set -gx SUBLIME_SKILLS_HOME ~/Projeler/Sublime-Skills
```

Reload (`exec fish`) or open a new shell. Verify:

```fish
echo $SUBLIME_SKILLS_HOME
# /home/emre/Projeler/Sublime-Skills

test -f $SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/discover-context.sh && echo ok
# ok
```

The var must point at the **real repo root**, not a symlinked location —
the framework scripts at `skills/spec-driven-development/framework/*.sh` are only
present in the real tree, never in `~/.claude/skills/` or `~/.codex/skills/`.

## 2. Install skills and commands for Claude Code

```fish
$SUBLIME_SKILLS_HOME/scripts/install-claude.fish
# Linked 35 skills, 2 commands.
```

The script is idempotent — re-run any time:

- After a `git pull` that brings in new skills or commands
- After adding or renaming a skill locally
- Whenever a symlink might have drifted

Existing symlinks are updated in place via `ln -sfn`; new ones are created;
dead symlinks (target removed upstream) are pruned at the end.

## 3. Install skills for Codex

```fish
$SUBLIME_SKILLS_HOME/scripts/install-codex.fish
# Linked 35 skills.
```

This links every leaf skill directory into `~/.codex/skills/`, which is
Codex's central skill location on this machine. Codex does not use the
Claude Code slash command files under `commands/`, so this script leaves
them alone.

The script is idempotent for the same reasons as the Claude Code installer:
re-run it after pulls, local skill additions, renames, or symlink drift.

## 4. Verify end-to-end

From any directory (not the repo):

```fish
cd /tmp
$SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/discover-context.sh
# Should emit JSON with "repo_root": "/tmp" and most fields null.
```

If you see `SUBLIME_SKILLS_HOME: SUBLIME_SKILLS_HOME is not set; see Sublime-Skills README for setup`,
the env var isn't exported in the current shell — recheck step 1.

Inside a fresh Claude Code session in any project, your skills (e.g.
`ss-bs-bootstrapping-project`, `ss-sdd-coordinator`, `ss-agile-*`) and slash commands
(`/ss-agile-advance-milestones`, `/ss-agile-populate-issues`) should now
be discoverable. Inside a fresh Codex session, the same skills should be
discoverable from `~/.codex/skills/`.

## Uninstall

```fish
$SUBLIME_SKILLS_HOME/scripts/uninstall.fish
# Removes every Sublime-Skills symlink from ~/.claude/{skills,commands}/
# Leaves the repo and the env var line untouched.
```

To fully uninstall, also remove the `set -gx SUBLIME_SKILLS_HOME ...` line
from `~/.config/fish/config.fish` manually.

There is no Codex uninstall wrapper yet; remove this repo's symlinks from
`~/.codex/skills/` if needed.

## Why this layout

- Repo stays at `~/Projeler/Sublime-Skills/` → normal git workflow, no special handling
- Skills surface globally via `~/.claude/skills/` symlinks → Claude Code finds them in every project
- Skills surface globally via `~/.codex/skills/` symlinks → Codex finds them in every project
- Slash commands surface globally via `~/.claude/commands/` symlinks → same idea, flat namespace
- Framework + skill-private scripts addressed via `$SUBLIME_SKILLS_HOME` → no cwd assumptions, no symlinks to maintain for any script tree
- Scaffold (`skills/project-bootstrap/scaffolds/config.yml`) addressed the same way → bootstrap copies it from the real repo regardless of where you invoke it from

## Appendix: what `install-claude.fish` actually does

If you want to inspect or run the loops manually instead of via the script,
they're roughly:

```fish
# Skills — one symlink per leaf skill dir
mkdir -p ~/.claude/skills
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    ln -sfn $dir ~/.claude/skills/(basename $dir)
end

# Commands — one symlink per .md file (flat namespace)
mkdir -p ~/.claude/commands
for cmd in $SUBLIME_SKILLS_HOME/commands/*.md
    ln -sfn $cmd ~/.claude/commands/(basename $cmd)
end

# Prune any symlinks whose targets no longer exist
find ~/.claude/skills ~/.claude/commands -maxdepth 1 -xtype l -delete
```

The script wraps these with input validation (env var is set, points at a
real Sublime-Skills checkout) and a final count report.
