# shellcheck shell=bash
#
# write_git_identity <alias>: writes the git identity it reads on stdin -- the config
# .chezmoitemplates/lib-git-identities.tmpl renders for one ssh: entry of this device's 1Password
# note -- to ~/.config/git/identities/<alias>, which dot_gitconfig.tmpl includes for every workspace
# named <alias>. prune_git_identities <alias>...: deletes every identity this library wrote that is
# not among <alias>..., so a key taken off the note stops being an identity on the next apply.
# run_after_linux-003-write-git-identities.sh.tmpl and run_after_android-002-write-git-identities.sh.tmpl
# both pull this in. See "Git Identities per Workspace" in AGENTS.md.
#
# Each file starts with GIT_IDENTITY_MARKER, and prune_git_identities deletes nothing else: a file
# without it is somebody's own, which a repository can include as well. A file is staged beside its
# target and renamed over it, so git never reads half of one, and a file already in place is left
# alone, so an apply with nothing to change says nothing. `mv -T` fails on a directory at the
# target instead of moving the file into it.

GIT_IDENTITIES_DIR="$HOME/.config/git/identities"
GIT_IDENTITY_MARKER="# Written by chezmoi from this device's 1Password note; edits here are overwritten."

write_git_identity() {
    local alias="$1" target staged
    target="$GIT_IDENTITIES_DIR/$alias"
    if ! mkdir -p "$GIT_IDENTITIES_DIR" || ! staged="$(mktemp "$GIT_IDENTITIES_DIR/.$alias.XXXXXX")"; then
        echo "[git-identities] ERROR: could not stage the identity \"$alias\" in $GIT_IDENTITIES_DIR" >&2
        return 1
    fi
    if ! { printf '%s\n' "$GIT_IDENTITY_MARKER" && cat; } >"$staged"; then
        rm -f "$staged"
        echo "[git-identities] ERROR: could not stage the identity \"$alias\" beside $target" >&2
        return 1
    fi
    if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
        return 0
    fi
    chmod 0644 "$staged"
    if ! command mv -fT "$staged" "$target"; then
        rm -f "$staged"
        echo "[git-identities] ERROR: could not move the identity \"$alias\" into place at $target" >&2
        return 1
    fi
    echo "[git-identities] wrote the identity \"$alias\" to $target" >&2
}

prune_git_identities() {
    local file name keep first
    [[ -d "$GIT_IDENTITIES_DIR" ]] || return 0
    for file in "$GIT_IDENTITIES_DIR"/*; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        name="${file##*/}"
        for keep in "$@"; do
            [[ "$name" == "$keep" ]] && continue 2
        done
        first=""
        IFS= read -r first <"$file" || true
        [[ "$first" == "$GIT_IDENTITY_MARKER" ]] || continue
        if ! rm -f "$file"; then
            echo "[git-identities] ERROR: could not remove the identity \"$name\" at $file" >&2
            return 1
        fi
        echo "[git-identities] removed the identity \"$name\": the device note no longer has it" >&2
    done
}
