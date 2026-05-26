#!/usr/bin/env fish
# Install / refresh Sublime-Skills symlinks into ~/.claude/{skills,commands}/
# and ~/.codex/skills/.
#
# Idempotent: re-run any time (after a git pull, after adding/renaming a skill).
# Existing symlinks are updated in place via `ln -sfn`; new ones are created;
# dead symlinks (target removed or renamed upstream) are pruned at the end.
#
# Always installs for both harnesses, regardless of whether Claude Code or
# Codex is installed on this machine — the dirs are cheap and the chosen
# harness will pick them up.
#
# Requires $SUBLIME_SKILLS_HOME to be set (see docs/SETUP.md for setup).
# Does NOT set the env var itself — that's a one-time config.fish edit.

if not set -q SUBLIME_SKILLS_HOME
    echo "SUBLIME_SKILLS_HOME is not set." >&2
    echo "Add the following line to ~/.config/fish/config.fish, then re-run:" >&2
    echo "  set -gx SUBLIME_SKILLS_HOME ~/Projeler/Sublime-Skills" >&2
    exit 1
end

if not test -d $SUBLIME_SKILLS_HOME
    echo "SUBLIME_SKILLS_HOME points at a non-existent directory: $SUBLIME_SKILLS_HOME" >&2
    exit 1
end

if not test -f $SUBLIME_SKILLS_HOME/skills/spec-driven-development/framework/discover-context.sh
    echo "SUBLIME_SKILLS_HOME does not look like a Sublime-Skills checkout: $SUBLIME_SKILLS_HOME" >&2
    echo "(expected skills/spec-driven-development/framework/discover-context.sh under it)" >&2
    exit 1
end

# --- Claude Code: skills + slash commands ---------------------------------

mkdir -p ~/.claude/skills ~/.claude/commands

set claude_skill_count 0
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    set name (basename $dir)
    ln -sfn $dir ~/.claude/skills/$name
    set claude_skill_count (math $claude_skill_count + 1)
end

set claude_cmd_count 0
for cmd in $SUBLIME_SKILLS_HOME/commands/*.md
    ln -sfn $cmd ~/.claude/commands/(basename $cmd)
    set claude_cmd_count (math $claude_cmd_count + 1)
end

set claude_pruned (find ~/.claude/skills ~/.claude/commands -maxdepth 1 -xtype l -print -delete 2>/dev/null | count)

# --- Codex: skills only ---------------------------------------------------

mkdir -p ~/.codex/skills

set codex_skill_count 0
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    set name (basename $dir)
    ln -sfn $dir ~/.codex/skills/$name
    set codex_skill_count (math $codex_skill_count + 1)
end

set codex_pruned (find ~/.codex/skills -maxdepth 1 -xtype l -print -delete 2>/dev/null | count)

# --- Report ---------------------------------------------------------------

echo "Claude Code: linked $claude_skill_count skills, $claude_cmd_count commands."
if test $claude_pruned -gt 0
    echo "Claude Code: pruned $claude_pruned dead symlink(s)."
end

echo "Codex:       linked $codex_skill_count skills."
if test $codex_pruned -gt 0
    echo "Codex:       pruned $codex_pruned dead symlink(s)."
end
