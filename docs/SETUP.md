# Setup (personal, fish + Linux)

Repo lives at `~/Projeler/Sublime-Skills/` (version-controlled). Skills are
symlinked from there into Claude Code's `~/.claude/skills/` and Codex's
`~/.codex/skills/` so both harnesses pick them up globally. Slash commands
are Claude Code-specific and symlink into `~/.claude/commands/`. The
framework scripts stay at their real location; skills address them via
`$SUBLIME_SKILLS_HOME`.

Three orthogonal pieces:

1. **Claude Code skill + slash command discovery** — symlinks into `~/.claude/skills/` and `~/.claude/commands/`
2. **Codex skill discovery** — symlinks into `~/.codex/skills/`
3. **Script + scaffold resolution** — `$SUBLIME_SKILLS_HOME` env var pointing at the real repo (manual, one-time)

Both harnesses are handled by a single script (`scripts/install.fish`).

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

## 2. Install skills and commands

```fish
$SUBLIME_SKILLS_HOME/scripts/install.fish
# Claude Code: linked 40 skills, 2 commands.
# Codex:       linked 40 skills.
```

The script installs for both Claude Code and Codex unconditionally — the
target dirs are cheap, and whichever harness you actually use will pick
them up. It is **idempotent** — re-run any time:

- After a `git pull` that brings in new skills or commands
- After adding or renaming a skill locally
- Whenever a symlink might have drifted

Existing symlinks are updated in place via `ln -sfn`; new ones are created;
dead symlinks (target removed or renamed upstream) are pruned at the end.
This is the right tool for fixing drift — after a rename, the old
basename's symlink becomes dangling and gets swept by the prune step on
the next install run.

## 3. Verify end-to-end

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
# Claude Code: removed 40 skill symlink(s), 2 command symlink(s).
# Codex:       removed 40 skill symlink(s).
```

The uninstall script scans `~/.claude/skills/`, `~/.claude/commands/`,
and `~/.codex/skills/`, and removes every symlink whose target resolves
under `$SUBLIME_SKILLS_HOME`. Unlike a naive "remove what the current
repo defines" approach, this also catches orphans left over from
past renames or deletions. Real directories and non-Sublime symlinks
are left alone.

To fully uninstall, also remove the `set -gx SUBLIME_SKILLS_HOME ...` line
from `~/.config/fish/config.fish` manually.

## Why this layout

- Repo stays at `~/Projeler/Sublime-Skills/` → normal git workflow, no special handling
- Skills surface globally via `~/.claude/skills/` symlinks → Claude Code finds them in every project
- Skills surface globally via `~/.codex/skills/` symlinks → Codex finds them in every project
- Slash commands surface globally via `~/.claude/commands/` symlinks → same idea, flat namespace
- Framework + skill-private scripts addressed via `$SUBLIME_SKILLS_HOME` → no cwd assumptions, no symlinks to maintain for any script tree
- Scaffold (`skills/project-bootstrap/scaffolds/config.yml`) addressed the same way → bootstrap copies it from the real repo regardless of where you invoke it from

## Appendix: what `install.fish` actually does

If you want to inspect or run the loops manually instead of via the script,
they're roughly:

```fish
# Claude Code: skills — one symlink per leaf skill dir
mkdir -p ~/.claude/skills
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    ln -sfn $dir ~/.claude/skills/(basename $dir)
end

# Claude Code: slash commands — one symlink per .md file (flat namespace)
mkdir -p ~/.claude/commands
for cmd in $SUBLIME_SKILLS_HOME/commands/*.md
    ln -sfn $cmd ~/.claude/commands/(basename $cmd)
end

# Codex: skills only
mkdir -p ~/.codex/skills
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    ln -sfn $dir ~/.codex/skills/(basename $dir)
end

# Prune any symlinks whose targets no longer exist
find ~/.claude/skills ~/.claude/commands ~/.codex/skills -maxdepth 1 -xtype l -delete
```

The script wraps these with input validation (env var is set, points at a
real Sublime-Skills checkout) and a per-harness count report.
