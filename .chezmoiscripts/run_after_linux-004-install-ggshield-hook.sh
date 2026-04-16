#!/bin/bash

# Idempotent: (re)generates the ggshield global pre-commit hook script at
# ~/.local/share/ggshield/git-hooks/pre-commit. The matching core.hooksPath
# in ~/.gitconfig is set by dot_gitconfig.tmpl — no git config mutation here.

set -euo pipefail

prefix="ggshield-hook"

if ! command -v ggshield &>/dev/null; then
    echo "[$prefix] WARN: ggshield not found on PATH, skipping" >&2
    exit 0
fi

# --mode global writes the hook script into the shared git-hooks dir.
# It also *attempts* to set core.hooksPath globally, but since we already
# own that setting via dot_gitconfig.tmpl the net result is unchanged.
ggshield install --mode global --force >&2 || {
    echo "[$prefix] ERROR: failed to install ggshield global hook" >&2
    exit 1
}

echo "[$prefix] global pre-commit hook ready" >&2
