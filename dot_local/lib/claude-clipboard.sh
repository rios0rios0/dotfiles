#!/data/data/com.termux/files/usr/bin/bash
# Shared definitions for the Claude Code clipboard shim on Termux.
#
# Sourced by ~/.local/bin/xclip and ~/.local/bin/clipshot. It is the single
# place the watched folders are declared: the shim decides what Ctrl+V attaches
# and `clipshot -s` reports what the shim would pick, so a second copy of the
# list would let the two answer differently for the same device.
#
# Not executable on its own, and it defines only functions and paths, so
# sourcing it has no side effect beyond the two glob options below (both
# consumers want them, and both build filename lists by globbing).

shopt -s nullglob nocaseglob

CLAUDE_CLIPBOARD_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-clipboard"
CLAUDE_CLIPBOARD_STAGED_FILE="$CLAUDE_CLIPBOARD_CACHE_DIR/staged"
CLAUDE_CLIPBOARD_CONSUMED_FILE="$CLAUDE_CLIPBOARD_CACHE_DIR/consumed"

# Fills CLAUDE_CLIPBOARD_WATCH_DIRS. Returns through a global rather than
# stdout so neither consumer pays for a command substitution: these run on
# Termux, where the phantom-process budget makes avoidable forks expensive.
clipboard_set_watch_dirs() {
    if [ -n "${CLAUDE_CLIPBOARD_DIRS:-}" ]; then
        IFS=: read -r -a CLAUDE_CLIPBOARD_WATCH_DIRS <<<"$CLAUDE_CLIPBOARD_DIRS"
        return 0
    fi
    CLAUDE_CLIPBOARD_WATCH_DIRS=(
        "$HOME/storage/pictures/Screenshots"
        "$HOME/storage/dcim/Screenshots"
        "$HOME/storage/pictures/Screenshot"
        "$HOME/storage/downloads"
    )
}

# Echoes "<mtime> <path>" for the newest image across the watched folders, or
# returns 1 when there is none. One `stat` call covers every candidate, for the
# same fork-budget reason.
clipboard_newest_image() {
    local dir cands=() line
    clipboard_set_watch_dirs
    for dir in "${CLAUDE_CLIPBOARD_WATCH_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        cands+=("$dir"/*.png "$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.webp "$dir"/*.gif)
    done
    [ ${#cands[@]} -eq 0 ] && return 1
    line=$(stat -c '%Y %n' -- "${cands[@]}" 2>/dev/null | sort -rn | head -1)
    [ -z "$line" ] && return 1
    printf '%s\n' "$line"
}
