#!/bin/bash
#
# Version Manager Utilities (pyenv workarounds only)
# Version detection and switching migrated to devforge: `dev project use`
#

# Clean up stale pyenv shim locks (fixes rehash lock issues)
_vm_cleanup_pyenv_locks() {
    local shims_dir="${PYENV_ROOT:-$HOME/.pyenv}/shims"
    local lock_file="$shims_dir/.pyenv-shim"

    # Remove stale lock file if it exists and is older than 60 seconds
    if [[ -f "$lock_file" ]]; then
        local file_age
        if [[ "$(uname)" == "Darwin" ]]; then
            file_age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || echo 0) ))
        else
            file_age=$(( $(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
        fi

        if (( file_age > 60 )); then
            rm -f "$lock_file" 2>/dev/null
        fi
    fi
}

# Safe pyenv wrapper that handles noclobber issues
# The "cannot overwrite existing file" error during rehash is caused by noclobber shell option
# This wrapper temporarily disables noclobber for all pyenv operations
pyenv() {
    # Temporarily disable noclobber if it's set (fixes rehash lock issues)
    local noclobber_was_set=false
    if [[ -o noclobber ]]; then
        noclobber_was_set=true
        set +o noclobber
    fi

    # Clean up any stale locks before running pyenv
    _vm_cleanup_pyenv_locks

    # Run the actual pyenv command
    command pyenv "$@"
    local exit_code=$?

    # Restore noclobber if it was set
    if [[ "$noclobber_was_set" == "true" ]]; then
        set -o noclobber
    fi

    return $exit_code
}

# Shell wrapper for devforge version switching
# Detects required SDK version from project files and switches to it
# Usage: dev-use [path]
dev-use() { eval "$(dev project use "${1:-.}" 2>/dev/null)"; }
