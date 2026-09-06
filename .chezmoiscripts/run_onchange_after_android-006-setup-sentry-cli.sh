#!/data/data/com.termux/files/usr/bin/bash

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
# SHELL is pinned to zsh so the result does not depend on the shell `chezmoi apply` was
# started from. The agent skill goes to ~/.claude/skills/sentry-cli/; ~/.claude always exists
# here because chezmoi manages it on Android. npm's prefix on Termux is $PREFIX, which is on
# PATH in every shell, so no NVM lookup is needed (and NVM refuses to run while PREFIX is set).

set -euo pipefail

prefix="sentry-setup"

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
