#!/bin/bash
set -euo pipefail

# Tests `install_nvm` in the shared install library without the network or a real nvm: the
# function is lifted out of `.chezmoitemplates/lib-install-deps.sh`, and `nvm`, `npm` and
# `corepack` are stubs that record their calls. Covers npm's upgrade after the LTS, whether the LTS
# was already installed or not -- Node ships the npm current at its release, and every
# `npm install -g` after it printed "New major version of npm available!" -- that it comes before
# the first global install, and `--reinstall-packages-from`, passed only when there is a version to
# copy the global CLIs from.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIBRARY="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-install-nvm] testing the Node.js LTS and npm install..." >&2

pass() { echo "[test-install-nvm] PASS: $1" >&2; }
fail() { echo "[test-install-nvm] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_nvm() {$/,/^}$/p' "$LIBRARY")"
if [[ -z "$FUNCTION" ]]; then
    fail "install_nvm was not found in the install library"
    exit 1
fi
# shellcheck source=/dev/null
source <(printf '%s\n' "$FUNCTION")

command_exists() { command -v "$1" >/dev/null 2>&1; }
run_remote_installer() { echo "run_remote_installer $*" >>"$CALLS"; }

# `nvm version-remote --lts` answers $LTS and `nvm current` answers $CURRENT; everything else is
# recorded.
nvm() {
    case "$1" in
        version-remote) echo "$LTS" ;;
        current) echo "$CURRENT" ;;
        *) echo "nvm $*" >>"$CALLS" ;;
    esac
}
npm() { echo "npm $*" >>"$CALLS"; }
corepack() { echo "corepack $*" >>"$CALLS"; }

run_case() {
    LTS="$1"
    CURRENT="$2"
    export HOME="$TMP/$3"
    CALLS="$TMP/$3.calls"
    # an existing NVM, so nothing is downloaded and nothing is sourced
    mkdir -p "$HOME/.nvm"
    : >"$CALLS"
    install_nvm >/dev/null 2>&1 && STATUS=0 || STATUS=$?
}

# The line number of the first call matching $1, or nothing.
line_of() {
    grep -n -m 1 -F -- "$1" "$CALLS" | cut -d: -f1
}

upgraded_before_globals() {
    local upgrade corepack
    upgrade="$(line_of "nvm install-latest-npm")"
    corepack="$(line_of "npm install -g --ignore-scripts corepack")"
    [[ -n "$upgrade" && -n "$corepack" && "$upgrade" -lt "$corepack" ]]
}

# --- the LTS already installed ------------------------------------------------------------------
run_case "v24.22.1" "v24.22.1" installed
if [[ "$STATUS" -eq 0 ]] && ! grep -q "^nvm install --lts" "$CALLS"; then
    pass "installs no Node.js when the LTS is already current"
else
    fail "installs no Node.js when the LTS is already current ($(tr '\n' ';' <"$CALLS"))"
fi
if upgraded_before_globals; then
    pass "upgrades npm on an LTS that was already installed, before the first global install"
else
    fail "upgrades npm on an LTS that was already installed, before the first global install ($(tr '\n' ';' <"$CALLS"))"
fi

# --- a new LTS, carrying the global CLIs over --------------------------------------------------
run_case "v26.1.0" "v24.22.1" bump
if grep -q -x "nvm install --lts --reinstall-packages-from=v24.22.1" "$CALLS"; then
    pass "installs a new LTS with the global CLIs of the current version"
else
    fail "installs a new LTS with the global CLIs of the current version ($(tr '\n' ';' <"$CALLS"))"
fi
if upgraded_before_globals; then
    pass "upgrades npm after installing a new LTS"
else
    fail "upgrades npm after installing a new LTS ($(tr '\n' ';' <"$CALLS"))"
fi

# --- a first install: nothing to copy from ------------------------------------------------------
run_case "v24.22.1" "none" first
if grep -q -x "nvm install --lts" "$CALLS"; then
    pass "passes no --reinstall-packages-from on a first install"
else
    fail "passes no --reinstall-packages-from on a first install ($(tr '\n' ';' <"$CALLS"))"
fi
if upgraded_before_globals; then
    pass "upgrades npm after a first install"
else
    fail "upgrades npm after a first install ($(tr '\n' ';' <"$CALLS"))"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-install-nvm] all Node.js and npm install tests passed" >&2
fi

exit $EXIT_CODE
