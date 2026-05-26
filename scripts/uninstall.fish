#!/usr/bin/env fish
# Remove all Sublime-Skills symlinks from ~/.claude/{skills,commands}/
# and ~/.codex/skills/.
#
# Scans each target directory and removes any symlink whose target points
# under $SUBLIME_SKILLS_HOME. This catches symlinks left behind by past
# skill renames or removals — anything the install script ever created
# gets cleaned up, even orphans no longer matched by the current repo state.
#
# Leaves the repo at $SUBLIME_SKILLS_HOME untouched. Leaves non-Sublime
# symlinks and real directories (e.g. independently-installed skills) alone.
#
# Does NOT remove the env var line from config.fish — that's a manual edit.

if not set -q SUBLIME_SKILLS_HOME
    echo "SUBLIME_SKILLS_HOME is not set; cannot determine which symlinks belong to Sublime-Skills." >&2
    echo "Set it temporarily to point at the repo, then re-run." >&2
    exit 1
end

# Normalize: strip trailing slash so prefix-match below is exact.
set repo_root (string trim --right --chars=/ -- $SUBLIME_SKILLS_HOME)

function remove_sublime_links --argument-names dir repo_root
    set count 0
    if not test -d $dir
        echo $count
        return
    end
    # -type l matches symlinks regardless of whether the target exists.
    for link in (find $dir -maxdepth 1 -type l)
        set target (readlink $link)
        if string match -q "$repo_root/*" -- $target
            rm -f $link
            set count (math $count + 1)
        end
    end
    echo $count
end

set claude_skills_removed (remove_sublime_links ~/.claude/skills $repo_root)
set claude_cmds_removed (remove_sublime_links ~/.claude/commands $repo_root)
set codex_skills_removed (remove_sublime_links ~/.codex/skills $repo_root)

echo "Claude Code: removed $claude_skills_removed skill symlink(s), $claude_cmds_removed command symlink(s)."
echo "Codex:       removed $codex_skills_removed skill symlink(s)."
echo ""
echo "Note: the env var line in ~/.config/fish/config.fish is unchanged — remove it manually if uninstalling fully."
