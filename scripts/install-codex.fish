#!/usr/bin/env fish
# Install / refresh Sublime-Skills symlinks into ~/.codex/skills/.
#
# Idempotent: re-run any time (after a git pull, after adding a skill).
# Existing symlinks are updated in place via `ln -sfn`; new ones are created;
# dead symlinks (target removed upstream) get pruned at the end.
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

mkdir -p ~/.codex/skills

set skill_count 0
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set dir (dirname $skill)
    set name (basename $dir)
    ln -sfn $dir ~/.codex/skills/$name
    set skill_count (math $skill_count + 1)
end

set pruned (find ~/.codex/skills -maxdepth 1 -xtype l -print -delete 2>/dev/null | count)

echo "Linked $skill_count skills."
if test $pruned -gt 0
    echo "Pruned $pruned dead symlink(s)."
end
