#!/bin/bash

# Idempotent: (re)generates the ggshield global pre-commit hook script at
# ~/.local/share/ggshield/git-hooks/pre-commit. The matching core.hooksPath
# in ~/.gitconfig is set by dot_gitconfig.tmpl — no git config mutation here.

set -euo pipefail

prefix="ggshield-hook"

ggshield_bin=""

# Non-interactive chezmoi runs may not have ~/.local/bin on PATH (pipx's default
# bin dir), so fall back to a direct file check before giving up.
if command -v ggshield &>/dev/null; then
    ggshield_bin="$(command -v ggshield)"
elif [[ -x "$HOME/.local/bin/ggshield" ]]; then
    ggshield_bin="$HOME/.local/bin/ggshield"
else
    echo "[$prefix] WARN: ggshield not found on PATH or at ~/.local/bin/ggshield, skipping" >&2
    exit 0
fi

# --mode global writes the hook script into the shared git-hooks dir.
# It also *attempts* to set core.hooksPath globally, but since we already
# own that setting via dot_gitconfig.tmpl the net result is unchanged.
"$ggshield_bin" install --mode global --force >&2 || {
    echo "[$prefix] ERROR: failed to install ggshield global hook" >&2
    exit 1
}

echo "[$prefix] global pre-commit hook ready" >&2
