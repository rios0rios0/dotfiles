# shellcheck shell=bash
#
# write_home_agents: writes the agent guide it reads on stdin -- .chezmoitemplates/home-agents.md,
# rendered for this machine -- to ~/AGENTS.md, which OpenCode and other agents read, and to
# ~/CLAUDE.md, the same guide for Claude Code, which reads CLAUDE.md files and never AGENTS.md.
# run_onchange_after_linux-019-write-home-agents.sh.tmpl and
# run_onchange_after_android-011-write-home-agents.sh.tmpl both pull this in; Windows, where Claude
# Code is not installed, has its own copy for ~/AGENTS.md alone in
# run_onchange_after_windows-006-write-home-agents.ps1.tmpl.
#
# A script writes both because chezmoi cannot manage them: the repository's own AGENTS.md and
# CLAUDE.md, which are for agents working on the dotfiles, map to the same targets, and
# .chezmoiignore matches targets, so ignoring those files ignores every other source of the two
# targets as well. "The Home AGENTS.md" in AGENTS.md has the rest.
#
# Each file is staged beside its target and renamed over it, so nothing ever reads half a file, and
# a file that already holds the guide is left untouched. `mv -T` fails on a directory at the target
# instead of moving the guide into it.

write_home_agents() {
    local guide target staged
    guide="$(mktemp "$HOME/.home-agents.XXXXXX")"
    if ! cat >"$guide"; then
        rm -f "$guide"
        echo "[home-agents] ERROR: could not stage the agent guide in $HOME" >&2
        return 1
    fi
    for target in "$HOME/AGENTS.md" "$HOME/CLAUDE.md"; do
        if [[ -f "$target" ]] && cmp -s "$guide" "$target"; then
            continue
        fi
        staged="$(mktemp "$HOME/.${target##*/}.XXXXXX")"
        if ! command cp "$guide" "$staged" || ! chmod 0644 "$staged" || ! command mv -fT "$staged" "$target"; then
            rm -f "$staged" "$guide"
            echo "[home-agents] ERROR: could not move the agent guide into place at $target" >&2
            return 1
        fi
        echo "[home-agents] wrote the agent guide for this machine to $target" >&2
    done
    rm -f "$guide"
}
