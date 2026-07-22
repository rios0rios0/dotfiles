# shellcheck shell=bash
# Shared dependency-removal library included by platform-specific wrappers.
#
# Deleting an `install_*()` function from a dependency installer only stops NEW
# machines from getting the tool -- machines that already ran it keep the tool
# forever. chezmoi has no concept of packages (it only knows about scripts), so
# uninstallation has to be explicit. See `.docs/dependency-lifecycle.md`.
#
# Callers declare a tombstone list and pass it to `apply_tombstones`. Every
# handler is idempotent and quiet, so a clean machine produces no output.

prefix="remove-deps"
removed=0

# =========================================================================================================
# Removal strategies. Each handler takes the target as $1, returns 0 when the
# target is already absent, and logs only when it actually removes something.
#
# Every mutating command is followed by `|| return 1` so a failed removal is
# reported by `apply_tombstones` instead of being swallowed. `set -e` does NOT
# help here: handlers are invoked from an `if !` condition, which disables
# errexit for the whole call, so without the explicit guard a failing command
# would fall through, still bump `removed`, and return success.

# Uninstall a globally installed npm package.
remove_npm_global() {
    local package="$1"
    command -v npm &>/dev/null || return 0
    npm ls -g --depth=0 "$package" &>/dev/null || return 0

    echo "[$prefix] removing npm global package: $package" >&2
    npm uninstall -g "$package" >&2 || return 1
    removed=$((removed + 1))
}

# Delete a file, symlink, or directory left behind by an upstream installer.
remove_path() {
    local target="$1"
    [[ -e "$target" || -L "$target" ]] || return 0

    # Safety rail: this runs unattended on every tombstone change, so it must
    # never delete outside the home directory. Two independent checks are needed.
    #
    # 1. The target must sit under $HOME. The `?*` guard also rejects a bare
    #    "$HOME" and "$HOME/".
    case "$target" in
        "$HOME"/?*) ;;
        *)
            echo "[$prefix] WARN: refusing to remove '$target' (outside \$HOME)" >&2
            return 0
            ;;
    esac

    # 2. No `..` component, which would satisfy the prefix check above yet still
    #    escape $HOME (e.g. "$HOME/../outside"). Wrapping the target in slashes
    #    means a real component always shows up as "/../", so a legitimate name
    #    like "foo..bar" is not caught.
    case "/$target/" in
        */../*)
            echo "[$prefix] WARN: refusing to remove '$target' (contains a '..' component)" >&2
            return 0
            ;;
    esac

    echo "[$prefix] removing path: $target" >&2
    rm -rf -- "$target" || return 1
    removed=$((removed + 1))
}

# Remove a `gh` CLI extension.
remove_gh_extension() {
    local extension="$1"
    local gh_bin=""

    # Android installs `gh` into ~/.local/bin via a wrapper, which is not always
    # on PATH during a non-interactive chezmoi run.
    if command -v gh &>/dev/null; then
        gh_bin="$(command -v gh)"
    elif [[ -x "$HOME/.local/bin/gh" ]]; then
        gh_bin="$HOME/.local/bin/gh"
    else
        return 0
    fi

    "$gh_bin" extension list 2>/dev/null | grep -qF "$extension" || return 0

    echo "[$prefix] removing gh extension: $extension" >&2
    "$gh_bin" extension remove "$extension" >&2 || return 1
    removed=$((removed + 1))
}

# Uninstall a pipx-managed application.
remove_pipx() {
    local app="$1"
    command -v pipx &>/dev/null || return 0
    pipx list --short 2>/dev/null | grep -qE "^${app} " || return 0

    echo "[$prefix] removing pipx application: $app" >&2
    pipx uninstall "$app" >&2 || return 1
    removed=$((removed + 1))
}

# Uninstall a dpkg/apt package.
#
# On Termux, apt runs unprivileged inside the app sandbox. On Linux/WSL it needs
# root, and because chezmoi runs unattended the removal is skipped with an
# actionable warning when passwordless sudo is unavailable -- blocking
# `chezmoi apply` on a password prompt would be worse than leaving the package.
remove_apt() {
    local package="$1"
    command -v dpkg-query &>/dev/null || return 0
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
        grep -q '^install ok installed$' || return 0

    local -a apt_cmd
    if [[ "$(id -u)" -eq 0 ]]; then
        apt_cmd=(apt-get)
    elif [[ -n "${PREFIX:-}" && -d "${PREFIX:-}/var/lib/dpkg" ]]; then
        apt_cmd=(apt-get)
    elif sudo -n true 2>/dev/null; then
        apt_cmd=(sudo -n apt-get)
    else
        echo "[$prefix] WARN: '$package' is still installed but passwordless sudo is unavailable" >&2
        echo "[$prefix] WARN: remove it manually with: sudo apt-get remove -y $package" >&2
        return 0
    fi

    echo "[$prefix] removing apt package: $package" >&2
    "${apt_cmd[@]}" remove -y "$package" >&2 || return 1
    removed=$((removed + 1))
}

# Strategy name -> handler function.
declare -A REMOVAL_HANDLERS=(
    ["apt"]=remove_apt
    ["gh_extension"]=remove_gh_extension
    ["npm_global"]=remove_npm_global
    ["path"]=remove_path
    ["pipx"]=remove_pipx
)

# =========================================================================================================
# Run every "<strategy>:<target>" tombstone passed as an argument.
apply_tombstones() {
    local tombstone strategy target handler

    for tombstone in "$@"; do
        strategy="${tombstone%%:*}"
        target="${tombstone#*:}"

        handler="${REMOVAL_HANDLERS[$strategy]:-}"
        if [[ -z "$handler" ]]; then
            echo "[$prefix] WARN: unknown removal strategy '$strategy' for '$target', skipping" >&2
            continue
        fi

        # A single failed removal must never abort `chezmoi apply`.
        if ! "$handler" "$target"; then
            echo "[$prefix] WARN: failed to remove '$target' via '$strategy'" >&2
        fi
    done

    if [[ "$removed" -gt 0 ]]; then
        echo "[$prefix] removed $removed leftover dependency entries" >&2
    fi
}
