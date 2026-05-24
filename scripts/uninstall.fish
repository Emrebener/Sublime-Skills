#!/usr/bin/env fish
# Remove all Sublime-Skills symlinks from ~/.claude/{skills,commands}/.
# Leaves the repo at $SUBLIME_SKILLS_HOME untouched.
#
# Does NOT remove the env var line from config.fish — that's a manual edit.

if not set -q SUBLIME_SKILLS_HOME
    echo "SUBLIME_SKILLS_HOME is not set; nothing to do (or set it temporarily to point at the repo so this script knows what to remove)." >&2
    exit 1
end

set removed_skills 0
for skill in $SUBLIME_SKILLS_HOME/skills/*/*/SKILL.md
    set name (basename (dirname $skill))
    set link ~/.claude/skills/$name
    if test -L $link
        rm -f $link
        set removed_skills (math $removed_skills + 1)
    end
end

set removed_cmds 0
for cmd in $SUBLIME_SKILLS_HOME/commands/*.md
    set link ~/.claude/commands/(basename $cmd)
    if test -L $link
        rm -f $link
        set removed_cmds (math $removed_cmds + 1)
    end
end

echo "Removed $removed_skills skill symlink(s), $removed_cmds command symlink(s)."
echo "Note: the env var line in ~/.config/fish/config.fish is unchanged — remove it manually if uninstalling fully."
