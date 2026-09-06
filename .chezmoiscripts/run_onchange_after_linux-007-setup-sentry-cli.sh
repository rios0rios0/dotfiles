#!/bin/bash

# Installs the Sentry CLI's zsh completion and its agent skill once the managed files are in
# place. `npm install -g sentry` (`install_sentry_cli` in lib-install-deps.sh) ships neither;
# `sentry cli setup` writes both, and the binary re-runs that same setup after every
# `sentry cli upgrade`, so one pass per machine is enough -- hence `run_onchange_`: it runs
# when this file changes and stays quiet otherwise.
#
# This is an after-script rather than a call inside the installer on purpose.
# `--no-modify-path` only skips the PATH edit; the zsh completion step still appends an
# `fpath` line to ~/.zshrc unless the file already names the completion directory as a
# quoted absolute path, which `dot_zshrc.tmpl` renders (`.chezmoi.homeDir`, not `$HOME`).
# Running after the files means the CLI finds the managed ~/.zshrc already configured and
# leaves it alone; from `run_once_before` it would edit the previous ~/.zshrc first, and the
# file application that follows would stop to ask about an externally modified target.
#
# SHELL is pinned to zsh: the CLI installs completions for the shell SHELL names, and the
# very first apply on a new Linux machine runs under bash. zsh is the shell both platforms
# end up with. The agent skill (~/.claude/skills/sentry-cli/) is written only when ~/.claude
# exists, which on Linux is after Claude Code's first run -- the next `sentry cli upgrade`
# adds it then.

set -euo pipefail

prefix="sentry-setup"

# ~/.zshenv puts npm's global bin directory on PATH in every zsh, but this script may run
# from the bash that started the first `chezmoi init --apply`, where NVM was never loaded.
# Look for the binary under the installed Node versions before giving up.
if ! command -v sentry >/dev/null 2>&1; then
    for node_bin in "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin; do
        if [[ -x "$node_bin/sentry" ]]; then
            PATH="$node_bin:$PATH"
        fi
    done
fi

if ! command -v sentry >/dev/null 2>&1; then
    echo "[$prefix] WARN: sentry is not installed; skipping completions and the agent skill" >&2
    exit 0
fi

echo "[$prefix] running sentry cli setup --no-modify-path..." >&2
if ! SHELL=zsh sentry cli setup --no-modify-path >&2; then
    echo "[$prefix] WARN: sentry cli setup failed; completions and the agent skill were not refreshed" >&2
    exit 0
fi

echo "[$prefix] completions and agent skill ready" >&2
