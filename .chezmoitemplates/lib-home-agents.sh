# shellcheck shell=bash
#
# write_home_agents: writes the agent guide it reads on stdin -- .chezmoitemplates/home-agents.md,
# rendered for this machine -- to ~/AGENTS.md. run_onchange_after_linux-019-write-home-agents.sh.tmpl
# and run_onchange_after_android-011-write-home-agents.sh.tmpl both pull this in; Windows has its
# own copy in run_onchange_after_windows-006-write-home-agents.ps1.tmpl. OpenCode and Claude Code
# both read it there, Claude Code through the Project instructions setting that
# dot_claude/modify_settings.json merges, so no ~/CLAUDE.md is written: one there would also stop
# Claude Code reading the AGENTS.md of a repository that has no CLAUDE.md of its own.
#
# A script writes the file because chezmoi cannot manage it: the repository's own AGENTS.md, which
# is for agents working on the dotfiles, maps to the same target, and .chezmoiignore matches
# targets, so ignoring that file ignores every other source of ~/AGENTS.md as well. "The Home
# AGENTS.md" in AGENTS.md has the rest.
#
# The guide is staged beside the target and renamed over it, so nothing ever reads half a file, and
# a guide already in place is left untouched. `mv -T` fails on a directory at ~/AGENTS.md instead of
# moving the guide into it.

write_home_agents() {
    local target="$HOME/AGENTS.md" staged
    staged="$(mktemp "$HOME/.AGENTS.md.XXXXXX")"
    if ! cat >"$staged"; then
        rm -f "$staged"
        echo "[home-agents] ERROR: could not stage the agent guide beside $target" >&2
        return 1
    fi
    if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
        return 0
    fi
    chmod 0644 "$staged"
    if ! command mv -fT "$staged" "$target"; then
        rm -f "$staged"
        echo "[home-agents] ERROR: could not move the agent guide into place at $target" >&2
        return 1
    fi
    echo "[home-agents] wrote the agent guide for this machine to $target" >&2
}
