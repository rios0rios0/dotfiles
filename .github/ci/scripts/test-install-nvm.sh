#!/bin/bash
set -euo pipefail

# Tests `install_nvm` in the shared install library without the network or a real nvm: the
# function and `carry_npm_globals` are lifted out of `.chezmoitemplates/lib-install-deps.sh`, and
# `nvm`, `npm` and `corepack` are stubs that record their calls. Covers npm's upgrade after the
# LTS, whether the LTS was already installed or not -- Node ships the npm current at its release,
# and every `npm install -g` after it printed "New major version of npm available!" -- that it
# comes before the first global install, and the carry-over of the global packages to a new LTS:
# one `npm install -g` per package, what is never carried, a failure that fails the run once and is
# retried by the next one, a retry that fails too only warning -- so that a package which can never
# install does not re-run the whole installer on every apply -- and the old version named once it
# is done.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIBRARY="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
EXIT_CODE=0
# The LTS a machine already runs in these cases, and the one that replaces it.
CURRENT_LTS="v24.22.1"
NEW_LTS="v26.13.0"
MARKER_NAME=".dotfiles-lts-switch"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-install-nvm] testing the Node.js LTS and npm install..." >&2

pass() { echo "[test-install-nvm] PASS: $1" >&2; }
fail() { echo "[test-install-nvm] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTIONS="$(sed -n '/^carry_npm_globals() {$/,/^}$/p; /^lts_switch_failed() {$/,/^}$/p; /^install_nvm() {$/,/^}$/p' "$LIBRARY")"
if [[ "$FUNCTIONS" != *"install_nvm() {"* || "$FUNCTIONS" != *"carry_npm_globals() {"* ||
    "$FUNCTIONS" != *"lts_switch_failed() {"* ]]; then
    fail "install_nvm, carry_npm_globals or lts_switch_failed was not found in the install library"
    exit 1
fi
# shellcheck source=/dev/null
source <(printf '%s\n' "$FUNCTIONS")

command_exists() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1
}
run_remote_installer() { echo "run_remote_installer $*" >>"$CALLS"; }

# `nvm version-remote --lts` answers $LTS, `nvm current` $CURRENT, and `nvm version default`
# $DEFAULT_VERSION when set, else $CURRENT. `nvm install --lts` fails when $FAIL_NVM_INSTALL is
# set and otherwise makes $LTS current, as the real one does in the shell that runs it.
nvm() {
    case "$1" in
        version-remote) echo "$LTS" ;;
        current) echo "$CURRENT" ;;
        version) echo "${DEFAULT_VERSION:-$CURRENT}" ;;
        install)
            echo "nvm $*" >>"$CALLS"
            if [[ -n "${FAIL_NVM_INSTALL:-}" ]]; then
                return 1
            fi
            if [[ "${2:-}" == --lts ]]; then
                CURRENT="$LTS"
            fi
            ;;
        *) echo "nvm $*" >>"$CALLS" ;;
    esac
}
# `npm root -g` answers the current Node's tree; `npm install -g` records its call, fails for the
# package named in $FAIL_NPM, and otherwise puts the package into that tree.
npm() {
    local root="$HOME/.nvm/versions/node/$CURRENT/lib/node_modules"
    if [[ "$1" == root ]]; then
        echo "$root"
        return
    fi
    echo "npm $*" >>"$CALLS"
    if [[ "$1" != install ]]; then
        return
    fi
    local spec="${!#}" name version
    if [[ "$spec" == ?*@* ]]; then
        name="${spec%@*}"
        version="${spec##*@}"
    else
        name="$spec"
        version="0.0.0"
    fi
    if [[ -n "${FAIL_NPM:-}" && "$name" == "$FAIL_NPM" ]]; then
        return 1
    fi
    mkdir -p "$root/$name"
    printf '{"name": "%s", "version": "%s"}\n' "$name" "$version" >"$root/$name/package.json"
}
corepack() { echo "corepack $*" >>"$CALLS"; }

# new_case <name>: a fresh HOME with an existing NVM, so nothing is downloaded and nothing is
# sourced, and an empty call log.
new_case() {
    export HOME="$TMP/$1"
    CALLS="$TMP/$1.calls"
    ERR="$TMP/$1.stderr"
    mkdir -p "$HOME/.nvm" "$HOME/.local/bin"
    : >"$CALLS"
}

# run_install <lts> <current>: runs install_nvm, leaving its status in $STATUS and its stderr in
# $ERR.
run_install() {
    LTS="$1"
    CURRENT="$2"
    install_nvm >/dev/null 2>"$ERR" && STATUS=0 || STATUS=$?
}

# global <node version> <package> <package version> [bin JSON]: a package in that Node's tree.
global() {
    local dir="$HOME/.nvm/versions/node/$1/lib/node_modules/$2"
    mkdir -p "$dir"
    printf '{"name": "%s", "version": "%s", "bin": %s}\n' "$2" "$3" "${4:-null}" >"$dir/package.json"
}

# The line number of the first call matching $1, or nothing.
line_of() {
    local call="$1"
    grep -n -m 1 -F -- "$call" "$CALLS" | cut -d: -f1
}

upgraded_before_globals() {
    local upgrade corepack
    upgrade="$(line_of "nvm install-latest-npm")"
    corepack="$(line_of "npm install -g --ignore-scripts corepack")"
    [[ -n "$upgrade" && -n "$corepack" && "$upgrade" -lt "$corepack" ]]
}

calls() { tr '\n' ';' <"$CALLS"; }

# --- the LTS already installed ------------------------------------------------------------------
new_case installed
run_install "$CURRENT_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -eq 0 ]] && ! grep -q "^nvm install --lts" "$CALLS"; then
    pass "installs no Node.js when the LTS is already current"
else
    fail "installs no Node.js when the LTS is already current ($(calls))"
fi
if upgraded_before_globals; then
    pass "upgrades npm on an LTS that was already installed, before the first global install"
else
    fail "upgrades npm on an LTS that was already installed, before the first global install ($(calls))"
fi

# --- a new LTS, carrying the global packages over -----------------------------------------------
new_case bump
global "$CURRENT_LTS" sentry 1.2.0 '"dist/bin.cjs"'
global "$CURRENT_LTS" neon 2.3.0 '{"neon": "dist/cli.js"}'
global "$CURRENT_LTS" @scope/tool 3.0.0 '{"scope-tool": "index.js"}'
global "$CURRENT_LTS" @anthropic-ai/claude-code 2.1.0 '{"claude": "cli.js"}'
global "$CURRENT_LTS" npm 10.9.9 '{"npm": "bin/npm-cli.js"}'
global "$CURRENT_LTS" corepack 0.34.0 '{"corepack": "dist/corepack.js"}'
mkdir -p "$HOME/src/mylib"
printf '{"name": "mylib", "version": "0.1.0"}\n' >"$HOME/src/mylib/package.json"
ln -s "$HOME/src/mylib" "$HOME/.nvm/versions/node/$CURRENT_LTS/lib/node_modules/mylib"
# Claude Code's native build, which this repository puts in ~/.local/bin
: >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
run_install "$NEW_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -eq 0 ]] && grep -q -x "nvm install --lts" "$CALLS"; then
    pass "installs a new LTS without nvm's --reinstall-packages-from"
else
    fail "installs a new LTS without nvm's --reinstall-packages-from (status $STATUS: $(calls))"
fi
if upgraded_before_globals; then
    pass "upgrades npm after installing a new LTS"
else
    fail "upgrades npm after installing a new LTS ($(calls))"
fi
first_carry="$(line_of "npm install -g --ignore-scripts sentry@" || true)"
if grep -q -x "npm install -g --ignore-scripts sentry@1.2.0" "$CALLS" &&
    grep -q -x "npm install -g --ignore-scripts neon@2.3.0" "$CALLS" &&
    grep -q -x "npm install -g --ignore-scripts @scope/tool@3.0.0" "$CALLS" &&
    [[ -n "$first_carry" && "$(line_of "nvm install-latest-npm")" -lt "$first_carry" ]]; then
    pass "carries each global package on its own, at its version, with no install scripts, after npm's upgrade"
else
    fail "did not carry each global package on its own after npm's upgrade ($(calls))"
fi
if ! grep -q -E "npm install .*(claude-code|npm@|corepack@|mylib)" "$CALLS" &&
    grep -q -F "not carrying @anthropic-ai/claude-code from Node.js $CURRENT_LTS: ~/.local/bin/claude already answers for it" "$ERR" &&
    grep -q -F "not carrying mylib from Node.js $CURRENT_LTS: it is linked from $HOME/src/mylib" "$ERR"; then
    pass "never carries npm, corepack, a linked package or one whose command ~/.local/bin already has, and names the last two"
else
    fail "carried a package it must not, or did not say why it left one ($(calls) $(cat "$ERR"))"
fi
if [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]] &&
    grep -q -F "Node.js $CURRENT_LTS is still installed beside $NEW_LTS; once no project needs it, \`nvm uninstall $CURRENT_LTS\` removes it" "$ERR"; then
    pass "a complete carry-over clears the marker and names the old version with the command that removes it"
else
    fail "a complete carry-over left the marker or did not name the old version ($(cat "$ERR"))"
fi

# --- a package that does not come across, and the run after -----------------------------------
new_case retry
global "$CURRENT_LTS" sentry 1.2.0 '"dist/bin.cjs"'
global "$CURRENT_LTS" neon 2.3.0 '{"neon": "dist/cli.js"}'
FAIL_NPM=neon run_install "$NEW_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -ne 0 ]] && grep -q -x "npm install -g --ignore-scripts sentry@1.2.0" "$CALLS" &&
    grep -q -F "could not carry from Node.js $CURRENT_LTS: neon@2.3.0" "$ERR" &&
    grep -q -F "npm install -g --ignore-scripts neon@2.3.0" "$ERR" &&
    grep -q -F "the next apply retries once" "$ERR" &&
    [[ "$(cat "$HOME/.nvm/$MARKER_NAME" 2>/dev/null)" == "from=$CURRENT_LTS"$'\n'"failed=1" ]] &&
    ! grep -q -F "nvm uninstall" "$ERR"; then
    pass "a package that failed fails the run once, is named with the command to install it, and is recorded for the retry"
else
    fail "a failed package did not fail the run or keep the marker (status $STATUS: $(calls) $(cat "$ERR"))"
fi
: >"$CALLS"
run_install "$NEW_LTS" "$NEW_LTS"
if [[ "$STATUS" -eq 0 ]] && ! grep -q "^nvm install --lts" "$CALLS" &&
    grep -q -x "npm install -g --ignore-scripts neon@2.3.0" "$CALLS" &&
    ! grep -q -F "sentry@" "$CALLS" && [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]]; then
    pass "the next run, with the new LTS current, carries only what is still missing and clears the marker"
else
    fail "the next run did not finish the carry-over (status $STATUS: $(calls) $(cat "$ERR"))"
fi

# --- a package that can never install, such as a version since unpublished ----------------------
new_case stuck
global "$CURRENT_LTS" neon 2.3.0 '{"neon": "dist/cli.js"}'
FAIL_NPM=neon run_install "$NEW_LTS" "$CURRENT_LTS"
first_status="$STATUS"
: >"$CALLS"
FAIL_NPM=neon run_install "$NEW_LTS" "$NEW_LTS"
if [[ "$first_status" -ne 0 && "$STATUS" -eq 0 ]] && [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]] &&
    grep -q -F "on the retry too; giving up" "$ERR" &&
    grep -q -F "npm install -g --ignore-scripts neon@2.3.0" "$ERR"; then
    pass "a package that fails the retry too only warns, with the command, and clears the marker"
else
    fail "a package failing its retry failed the run again or kept the marker (status $first_status then $STATUS: $(cat "$ERR"))"
fi
: >"$CALLS"
FAIL_NPM=neon run_install "$NEW_LTS" "$NEW_LTS"
if [[ "$STATUS" -eq 0 ]] && ! grep -q -F "neon@" "$CALLS"; then
    pass "after giving up, later runs no longer try the package, so the installer is not re-run for it"
else
    fail "a run after giving up tried the package again (status $STATUS: $(calls))"
fi

# --- a newer LTS arriving while a carry-over is still pending ----------------------------------
new_case overtaken
global "$CURRENT_LTS" neon 2.3.0 '{"neon": "dist/cli.js"}'
global "$NEW_LTS" sentry 1.2.0 '"dist/bin.cjs"'
printf 'from=%s\nfailed=1\n' "$CURRENT_LTS" >"$HOME/.nvm/$MARKER_NAME"
run_install "v28.0.0" "$NEW_LTS"
if [[ "$STATUS" -eq 0 ]] && grep -q -x "npm install -g --ignore-scripts sentry@1.2.0" "$CALLS" &&
    ! grep -q -F "neon@" "$CALLS" && [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]] &&
    grep -q -F "Node.js $CURRENT_LTS never all came across; carrying from $NEW_LTS instead" "$ERR"; then
    pass "a newer LTS carries from the version it leaves, naming the carry-over it overtook"
else
    fail "a newer LTS did not carry from the version it leaves (status $STATUS: $(calls) $(cat "$ERR"))"
fi

# --- the old version gone before the retry -----------------------------------------------------
new_case gone
printf 'from=%s\nfailed=0\n' "$CURRENT_LTS" >"$HOME/.nvm/$MARKER_NAME"
run_install "$NEW_LTS" "$NEW_LTS"
if [[ "$STATUS" -eq 0 ]] && [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]] &&
    grep -q -F "Node.js $CURRENT_LTS is no longer installed" "$ERR" && ! grep -q -F "nvm uninstall" "$ERR"; then
    pass "a marker whose version was uninstalled since is cleared, with nothing carried"
else
    fail "a marker naming an uninstalled version was not cleared (status $STATUS: $(cat "$ERR"))"
fi

# --- NVM's default still pointing at the old version ---------------------------------------------
new_case pinned
global "$CURRENT_LTS" sentry 1.2.0 '"dist/bin.cjs"'
DEFAULT_VERSION="$CURRENT_LTS" run_install "$NEW_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -eq 0 ]] && ! grep -q -F "nvm uninstall" "$ERR"; then
    pass "never suggests uninstalling the version NVM's default still resolves to"
else
    fail "suggested uninstalling the version NVM's default resolves to ($(cat "$ERR"))"
fi

# --- the LTS failing to install ------------------------------------------------------------------
new_case nvm-failure
FAIL_NVM_INSTALL=1 run_install "$NEW_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -ne 0 ]] && grep -q -F "could not install the Node.js LTS $NEW_LTS" "$ERR" &&
    ! grep -q "^nvm install-latest-npm" "$CALLS" &&
    [[ "$(cat "$HOME/.nvm/$MARKER_NAME" 2>/dev/null)" == "from=$CURRENT_LTS"$'\n'"failed=1" ]]; then
    pass "a failed LTS install fails the run once, before npm is touched, keeping the version to carry from"
else
    fail "a failed LTS install did not fail the run (status $STATUS: $(calls) $(cat "$ERR"))"
fi
: >"$CALLS"
FAIL_NVM_INSTALL=1 run_install "$NEW_LTS" "$CURRENT_LTS"
if [[ "$STATUS" -eq 0 ]] && grep -q -F "on the retry too; giving up" "$ERR" &&
    [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]] && upgraded_before_globals; then
    pass "an LTS that fails its retry too only warns, and the run goes on with the current Node.js"
else
    fail "an LTS failing its retry failed the run again (status $STATUS: $(calls) $(cat "$ERR"))"
fi

# --- a first install: nothing to copy from ------------------------------------------------------
new_case first
run_install "$CURRENT_LTS" "none"
if [[ "$STATUS" -eq 0 ]] && grep -q -x "nvm install --lts" "$CALLS" && [[ ! -e "$HOME/.nvm/$MARKER_NAME" ]]; then
    pass "a first install carries nothing and leaves no marker"
else
    fail "a first install tried to carry packages (status $STATUS: $(calls))"
fi
if upgraded_before_globals; then
    pass "upgrades npm after a first install"
else
    fail "upgrades npm after a first install ($(calls))"
fi

# --- the wiring: a failure has to reach the Linux installer's exit status -------------------------
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
verify_line="$(grep -n -m 1 -x 'verify() {' "$INSTALLER" | cut -d: -f1 || true)"
nvm_line="$(grep -n -m 1 -x 'verify install_nvm' "$INSTALLER" | cut -d: -f1 || true)"
npm_line="$(grep -n -m 1 -x 'install_sentry_cli' "$INSTALLER" | cut -d: -f1 || true)"
if [[ -n "$verify_line" && -n "$nvm_line" && -n "$npm_line" ]] &&
    (( verify_line < nvm_line && nvm_line < npm_line )) && ! grep -q -x 'install_nvm' "$INSTALLER"; then
    pass "the Linux installer calls install_nvm through verify, before the npm installers"
else
    fail "the Linux installer does not call install_nvm through verify before the npm installers (verify $verify_line, install_nvm $nvm_line, install_sentry_cli $npm_line)"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-install-nvm] all Node.js and npm install tests passed" >&2
fi

exit $EXIT_CODE
