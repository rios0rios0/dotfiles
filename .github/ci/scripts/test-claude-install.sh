#!/bin/bash
set -euo pipefail

# Tests `install_claude_cli` in the Linux dependency installer without the network: the function is
# lifted out of the installer, which renders it unchanged, and `run_remote_installer` is a stub that
# records its call and stands in for Anthropic's install.sh. Covers the native build going ahead
# while an npm `claude` is on PATH (a `command -v claude` check would have skipped it), the skip once
# ~/.local/bin/claude exists, the launcher directory on PATH for the installer, both failures, and
# the wiring that keeps the npm package's removal from leaving no `claude`: the installer verifies
# the call, installs nothing from npm, and the Linux removal script tombstones the npm package.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
LINUX_REMOVAL="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-006-remove-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-claude-install] testing the Claude Code install..." >&2

pass() { echo "[test-claude-install] PASS: $1" >&2; }
fail() { echo "[test-claude-install] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_claude_cli() {$/,/^}$/p' "$LINUX_INSTALLER")"
if [[ -z "$FUNCTION" ]]; then
    fail "install_claude_cli was not found in the Linux installer"
    exit 1
fi
# shellcheck source=/dev/null
source <(printf '%s\n' "$FUNCTION")

# Stands in for the library's `run_remote_installer`: records the call and the first PATH entry
# the installer would see, then leaves the launcher behind as install.sh does, unless
# $INSTALLER_FAIL (a failed download or `claude install`) or $INSTALLER_NO_LAUNCHER (a run that
# exits 0 and installs nothing) is set.
run_remote_installer() {
    echo "$* | PATH starts with ${PATH%%:*}" >>"$CALLS"
    [[ -z "${INSTALLER_FAIL:-}" ]] || return 1
    [[ -z "${INSTALLER_NO_LAUNCHER:-}" ]] || return 0
    # replaced rather than written through, as `claude install` does with a dangling launcher
    mkdir -p "$HOME/.local/bin"
    rm -f "$HOME/.local/bin/claude"
    printf '#!/bin/bash\necho "2.1.312 (Claude Code)"\n' >"$HOME/.local/bin/claude"
    chmod +x "$HOME/.local/bin/claude"
}

CASE=0
new_case() {
    CASE=$((CASE + 1))
    export HOME="$TMP/case-$CASE/home"
    CALLS="$TMP/case-$CASE/calls"
    mkdir -p "$HOME"
    : >"$CALLS"
    unset INSTALLER_FAIL INSTALLER_NO_LAUNCHER
}

run_function() {
    install_claude_cli >"$TMP/out" 2>&1 && STATUS=0 || STATUS=$?
}

# --- an npm `claude` on PATH does not stop the native build ------------------------------------
new_case
mkdir -p "$TMP/case-$CASE/npm-bin"
printf '#!/bin/bash\necho npm\n' >"$TMP/case-$CASE/npm-bin/claude"
chmod +x "$TMP/case-$CASE/npm-bin/claude"
PATH="$TMP/case-$CASE/npm-bin:$PATH" run_function
if [[ "$STATUS" -eq 0 ]] && grep -q -F "Claude Code https://claude.ai/install.sh" "$CALLS" &&
   [[ -x "$HOME/.local/bin/claude" ]]; then
    pass "installs the native build while an npm claude is on PATH"
else
    fail "installs the native build while an npm claude is on PATH (status $STATUS, calls: $(cat "$CALLS"))"
fi
if grep -q -F "PATH starts with $HOME/.local/bin" "$CALLS"; then
    pass "puts the launcher directory first on PATH for the installer"
else
    fail "puts the launcher directory first on PATH for the installer ($(cat "$CALLS"))"
fi

# --- the native build already there -----------------------------------------------------------
new_case
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
run_function
if [[ "$STATUS" -eq 0 && ! -s "$CALLS" ]] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "skips once ~/.local/bin/claude exists"
else
    fail "skips once ~/.local/bin/claude exists (status $STATUS, calls: $(cat "$CALLS"))"
fi

# A launcher whose version was removed is a dangling symlink, which is not a working install.
new_case
mkdir -p "$HOME/.local/bin"
ln -s "$HOME/.local/share/claude/versions/0.0.0" "$HOME/.local/bin/claude"
run_function
if [[ "$STATUS" -eq 0 ]] && grep -q -F "https://claude.ai/install.sh" "$CALLS"; then
    pass "reinstalls when the launcher points at nothing"
else
    fail "reinstalls when the launcher points at nothing (status $STATUS)"
fi

# --- failures --------------------------------------------------------------------------------
new_case
INSTALLER_FAIL=1 run_function
if [[ "$STATUS" -ne 0 && ! -e "$HOME/.local/bin/claude" ]]; then
    pass "fails when the installer fails"
else
    fail "fails when the installer fails (status $STATUS)"
fi

new_case
INSTALLER_NO_LAUNCHER=1 run_function
if [[ "$STATUS" -ne 0 ]] && grep -q "ERROR: the Claude Code installer finished without ~/.local/bin/claude" "$TMP/out"; then
    pass "fails when the installer exits 0 without the launcher"
else
    fail "fails when the installer exits 0 without the launcher (status $STATUS)"
fi

# --- wiring -------------------------------------------------------------------------------------
# Verified, so a failed install fails the apply before the after-scripts, among them the removal
# of the npm package, run.
if grep -q '^verify install_claude_cli$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_claude_cli"
else
    fail "the Linux installer verifies install_claude_cli"
fi

if grep -q -E 'npm (install|i) -g[^#]*@anthropic-ai/claude-code' "$LINUX_INSTALLER"; then
    fail "the Linux installer installs nothing from Claude Code's npm package"
else
    pass "the Linux installer installs nothing from Claude Code's npm package"
fi

if grep -q '^    "npm_global:@anthropic-ai/claude-code"$' "$LINUX_REMOVAL"; then
    pass "the Linux removal script tombstones Claude Code's npm package"
else
    fail "the Linux removal script tombstones Claude Code's npm package"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-claude-install] all Claude Code install tests passed" >&2
fi

exit $EXIT_CODE
