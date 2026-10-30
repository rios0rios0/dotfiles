#!/bin/bash
set -euo pipefail

# Tests `install_aisync` in the Linux dependency installer without the network: the function is
# lifted out of the installer, which renders it unchanged, `run_remote_installer` is a stub that
# records its call and stands in for aisync's install.sh, and `aisync` is a stub that records its
# arguments. Covers the install when aisync is missing, the skip when it is there, the
# self-update that keeps it current on every run (as install_terra does with terra), a first
# install found in ~/.local/bin before any shell put it on PATH, a failed self-update only
# warning, and a failed install failing before any self-update. The wiring: the Linux installer
# calls it, and the Android one, which builds aisync from source, never self-updates it.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
INSTALL_URL="https://raw.githubusercontent.com/rios0rios0/aisync/main/install.sh"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-aisync-install] testing the aisync install and self-update..." >&2

pass() { echo "[test-aisync-install] PASS: $1" >&2; }
fail() { echo "[test-aisync-install] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_aisync() {$/,/^}$/p' "$LINUX_INSTALLER")"
if [[ -z "$FUNCTION" ]]; then
    fail "install_aisync was not found in the Linux installer"
    exit 1
fi
# shellcheck source=/dev/null
source <(printf '%s\n' "$FUNCTION")

# write_aisync <dir>: an aisync that records where it ran from and its arguments, and whose
# `self-update` exits $UPDATE_STATUS.
write_aisync() {
    local dir="$1"
    mkdir -p "$dir"
    cat >"$dir/aisync" <<'STUB'
#!/bin/bash
echo "$0 $*" >>"$CALLS"
if [[ "${1:-}" == self-update ]]; then
    exit "${UPDATE_STATUS:-0}"
fi
STUB
    chmod +x "$dir/aisync"
}

# Stands in for the library's `run_remote_installer`: records the call, then leaves aisync in
# ~/.local/bin as install.sh does, unless $INSTALLER_FAIL is set.
run_remote_installer() {
    echo "installer $*" >>"$CALLS"
    [[ -z "${INSTALLER_FAIL:-}" ]] || return 1
    write_aisync "$HOME/.local/bin"
}

CASE=0
new_case() {
    CASE=$((CASE + 1))
    export HOME="$TMP/case-$CASE/home"
    export CALLS="$TMP/case-$CASE/calls"
    mkdir -p "$HOME"
    : >"$CALLS"
    unset INSTALLER_FAIL UPDATE_STATUS
}

# run_function [dir]: install_aisync with PATH holding only the system's own directories (and the
# given one first), so the machine's real aisync can never answer.
run_function() {
    local path="/usr/bin:/bin"
    if [[ -n "${1:-}" ]]; then
        path="$1:$path"
    fi
    PATH="$path" install_aisync >"$TMP/out" 2>&1 && STATUS=0 || STATUS=$?
}

# --- aisync already installed ----------------------------------------------------------------
new_case
write_aisync "$TMP/case-$CASE/bin"
run_function "$TMP/case-$CASE/bin"
if [[ "$STATUS" -eq 0 ]] && ! grep -q '^installer ' "$CALLS" && grep -q "already installed, skipping" "$TMP/out"; then
    pass "skips the install when aisync is already on PATH"
else
    fail "skips the install when aisync is already on PATH (status $STATUS, calls: $(cat "$CALLS"))"
fi
if [[ "$(cat "$CALLS")" == "$TMP/case-$CASE/bin/aisync self-update --force" ]]; then
    pass "self-updates an installed aisync on every run, without a prompt"
else
    fail "self-updates an installed aisync on every run, without a prompt (calls: $(cat "$CALLS"))"
fi

# --- aisync missing ----------------------------------------------------------------------------
new_case
run_function
if [[ "$STATUS" -eq 0 && "$(head -1 "$CALLS")" == "installer aisync $INSTALL_URL" ]]; then
    pass "installs a missing aisync through the upstream install.sh"
else
    fail "installs a missing aisync through the upstream install.sh (status $STATUS, calls: $(cat "$CALLS"))"
fi
if [[ "$(sed -n 2p "$CALLS")" == "$HOME/.local/bin/aisync self-update --force" ]]; then
    pass "self-updates the aisync it just put in ~/.local/bin, which PATH lacked"
else
    fail "self-updates the aisync it just put in ~/.local/bin, which PATH lacked (calls: $(cat "$CALLS"))"
fi

# --- failures --------------------------------------------------------------------------------
new_case
write_aisync "$TMP/case-$CASE/bin"
export UPDATE_STATUS=1
run_function "$TMP/case-$CASE/bin"
if [[ "$STATUS" -eq 0 ]] && grep -q "WARN: aisync self-update failed; continuing" "$TMP/out"; then
    pass "a failed self-update only warns"
else
    fail "a failed self-update only warns (status $STATUS, $(cat "$TMP/out"))"
fi

new_case
INSTALLER_FAIL=1 run_function
if [[ "$STATUS" -ne 0 ]] && ! grep -q 'self-update' "$CALLS"; then
    pass "a failed install fails before any self-update"
else
    fail "a failed install fails before any self-update (status $STATUS, calls: $(cat "$CALLS"))"
fi

# --- wiring -------------------------------------------------------------------------------------
if grep -q '^install_aisync$' "$LINUX_INSTALLER"; then
    pass "the Linux installer calls install_aisync"
else
    fail "the Linux installer calls install_aisync"
fi

# Termux builds aisync from source and releases carry no Android binary, so a self-update there
# has nothing to install, as with terra.
ANDROID_FUNCTION="$(sed -n '/^install_aisync() {$/,/^}$/p' "$ANDROID_INSTALLER")"
if [[ -n "$ANDROID_FUNCTION" ]] && ! grep -q 'self-update' <<<"$ANDROID_FUNCTION"; then
    pass "the Android installer builds aisync from source and never self-updates it"
else
    fail "the Android installer builds aisync from source and never self-updates it"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-aisync-install] all aisync install tests passed" >&2
fi
exit "$EXIT_CODE"
