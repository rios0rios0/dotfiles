#!/bin/bash
set -euo pipefail

# Tests the OpenCode V2 CLI installation and its PATH wiring without opencode, the network or
# a real installer: `install_opencode` is sourced from the shared dependency library with a
# `curl` stub that fabricates the upstream installer, and `dot_zshenv.tmpl` is rendered for
# each platform. Covers the already-installed skip, the installer call carrying
# `--no-modify-path` (the installer must stay out of the rc files chezmoi owns), the failed
# download and the failed installer, the wiring of the call in the Linux installer, and the
# PATH block existing on Linux and macOS but deliberately absent on Android.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
LIB="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
ZSHENV_TMPL="$REPO_ROOT/dot_zshenv.tmpl"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-opencode-cli] testing the OpenCode CLI install and PATH wiring..." >&2

pass() { echo "[test-opencode-cli] PASS: $1" >&2; }
fail() { echo "[test-opencode-cli] FAIL: $1" >&2; EXIT_CODE=1; }

# The library is pure bash and defines functions only, so the test shell can source it and
# call the installer directly under a redirected HOME.
# shellcheck source=/dev/null
source "$LIB"

export HOME="$TMP/home"
mkdir -p "$HOME"

STUB="$TMP/stub"
mkdir -p "$STUB"

# curl stub: records every invocation in $CURL_CALLS and writes $CURL_BODY to the -o target,
# unless $CURL_FAIL is set, standing in for a failed download.
cat >"$STUB/curl" <<'STUB'
#!/bin/bash
echo "$*" >>"${CURL_CALLS:?}"
if [[ -n "${CURL_FAIL:-}" ]]; then
    exit 22
fi
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "${CURL_BODY:?}" "$out"
STUB
chmod +x "$STUB/curl"

# The fabricated upstream installer: records the arguments it is invoked with and exits with
# $INSTALLER_FAIL when set.
cat >"$TMP/upstream-installer.sh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >>"${INSTALLER_CALLS:?}"
exit "${INSTALLER_FAIL:-0}"
FAKE

CURL_BODY="$TMP/upstream-installer.sh"
CURL_CALLS="$TMP/curl-calls"
INSTALLER_CALLS="$TMP/installer-calls"
export CURL_BODY CURL_CALLS INSTALLER_CALLS
: >"$CURL_CALLS"
: >"$INSTALLER_CALLS"

# run_install: runs install_opencode in a subshell with only the stub directory ahead of PATH
# on the environment, recording the output and the exit status.
run_install() {
    local rc=0
    (PATH="$STUB:$PATH"; cd "$TMP"; install_opencode) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
curl_calls() { wc -l <"$CURL_CALLS"; }

# given a machine that already carries the binary
# when install_opencode runs
# then nothing is downloaded and the skip says why
mkdir -p "$HOME/.opencode/bin"
cp "$TMP/upstream-installer.sh" "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"
run_install
[ "$(rc)" -eq 0 ] || fail "the installed skip must exit 0"
[ "$(curl_calls)" -eq 0 ] || fail "the installed skip must not download anything"
grep -q "already installed, skipping" "$TMP/out" || fail "the installed skip must say why"
pass "an installed CLI is skipped"

# given a machine without the binary
# when install_opencode runs
# then the upstream V2 installer is fetched and run with --no-modify-path and nothing else,
# so the rc files chezmoi owns stay untouched
rm -rf "$HOME/.opencode"
run_install
[ "$(rc)" -eq 0 ] || fail "the install must exit 0"
grep -q 'https://opencode.ai/v2/install' "$CURL_CALLS" || fail "the install must fetch the OpenCode V2 installer"
[ "$(cat "$INSTALLER_CALLS")" = "--no-modify-path" ] || fail "the installer must be run with --no-modify-path and nothing else: $(cat "$INSTALLER_CALLS")"
pass "the V2 installer runs with --no-modify-path"

# given a download that fails
# when install_opencode runs
# then it reports the failure and exits non-zero, so the caller's `verify` retries it on the
# next apply
rm -rf "$HOME/.opencode"
export CURL_FAIL=1
run_install
unset CURL_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed download must exit non-zero"
grep -q "failed to download the opencode installer" "$TMP/out" || fail "a failed download must say what failed"
pass "a failed download fails the install"

# given an installer that exits non-zero
# when install_opencode runs
# then it exits non-zero as well and reports the status
rm -rf "$HOME/.opencode"
export INSTALLER_FAIL=7
run_install
unset INSTALLER_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed installer must exit non-zero"
grep -q "exited with status 7" "$TMP/out" || fail "a failed installer must report its status"
pass "a failed installer fails the install"

# given the Linux dependency installer
# when its call list is read
# then install_opencode is wired in with `verify` -- a silent failure would leave a machine
# without the CLI, while `verify` exits non-zero and has chezmoi re-run the script
if grep -q '^verify install_opencode$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_opencode"
else
    fail "the Linux installer no longer verifies install_opencode"
fi

# given the Android dependency installer
# when it is searched for the installer call
# then it has none: the released binary is a glibc build, which bionic cannot start
if grep -q 'install_opencode' "$ANDROID_INSTALLER"; then
    fail "the Android installer must not install the glibc binary"
else
    pass "the Android installer installs nothing"
fi

# given the ZSHENV template
# when it is rendered for each platform
# then the ~/.opencode/bin PATH block sits in the non-Android branch: Linux and macOS get it,
# Android does not
chmod +x "$CI_DIR/fixtures/mock-op.sh" 2>/dev/null || true
cat >"$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

render() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" <"$ZSHENV_TMPL"
}

if ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not on PATH, so dot_zshenv.tmpl cannot be rendered"
else
    if render linux | grep -qF 'export PATH="$HOME/.opencode/bin:$PATH"'; then
        pass "Linux carries the ~/.opencode/bin PATH block"
    else
        fail "Linux lost the ~/.opencode/bin PATH block"
    fi

    if render darwin | grep -qF 'export PATH="$HOME/.opencode/bin:$PATH"'; then
        pass "macOS carries the ~/.opencode/bin PATH block"
    else
        fail "macOS lost the ~/.opencode/bin PATH block"
    fi

    if render android | grep -q '\.opencode'; then
        fail "Android must not carry the ~/.opencode/bin PATH block"
    else
        pass "Android carries no ~/.opencode/bin PATH block"
    fi

    # the flyctl block shares the branch and the template structure with the new block;
    # guard that neither change broke the other
    if render linux | grep -qF 'export PATH="$HOME/.fly/bin:$PATH"'; then
        pass "the flyctl PATH block still renders on Linux"
    else
        fail "the flyctl PATH block disappeared from the Linux render"
    fi
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-opencode-cli] all OpenCode CLI install and PATH tests passed" >&2
fi
exit $EXIT_CODE
