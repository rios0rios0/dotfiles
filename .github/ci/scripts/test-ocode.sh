#!/bin/bash
set -euo pipefail

# Tests the ocode fork-builder and the bun provisioning it depends on, without bun, git, the
# network or a real fork checkout: `git` and `bun` are stubs, the checkout is a fake directory
# whose `.git` exists, the build fabricates the artifact the fork's build would emit, and
# `install_bun` is sourced from the shared dependency library against a `curl` stub that
# fabricates the upstream installer. Covers the skip paths (no checkout, no bun), the first
# build (including the fork channel and release-grade version it must carry), the no-op
# rebuild, the rebuild on a new head, the rebuild that restores a missing binary, the prompt
# for a running ocode and both answers to it, the process started while the build runs, the
# ~/.bun/bin fallback, the installed skip, the installer call (with SHELL empty, so bun's
# script cannot edit an rc file chezmoi owns), both installer failures, the Linux wiring and
# the PATH block rendered on each platform.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_linux-006-build-ocode.sh"
LIB="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
ZSHENV_TMPL="$REPO_ROOT/dot_zshenv.tmpl"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-ocode] testing the ocode fork-builder and its bun provisioning..." >&2

pass() { echo "[test-ocode] PASS: $1" >&2; }
fail() { echo "[test-ocode] FAIL: $1" >&2; EXIT_CODE=1; }

export HOME="$TMP/home"
mkdir -p "$HOME"

export CHECKOUT="$HOME/Development/github.com/opencode/opencode"
STUB="$TMP/stub"
BUN_STUB="$TMP/bun-stub"
mkdir -p "$STUB" "$BUN_STUB" "$CHECKOUT/.git"

# git stub: HEAD comes from the checkout's .git/HEAD file; log echoes a fake subject.
cat >"$STUB/git" <<'STUB'
#!/bin/bash
case "$*" in
    *"rev-parse"*) cat "${CHECKOUT:?}/.git/HEAD" ;;
    *"log"*) echo "fake0123 chore: fake fork commit" ;;
    *) echo "stub git: unexpected args: $*" >&2; exit 1 ;;
esac
STUB

# bun stub: records every invocation and the build identity it was given, and fabricates the
# artifact under --outdir. With BUN_STUB_RACE set it also starts the installed binary mid-build,
# standing in for a person who opens ocode while the build runs -- the build-minutes window the
# installer's rename closes.
cat >"$BUN_STUB/bun" <<'STUB'
#!/bin/bash
echo "$*" >>"${BUN_CALLS:?}"
echo "${OPENCODE_CHANNEL:-unset}/${OPENCODE_VERSION:-unset}" >>"${BUN_ENV:?}"
if [ -n "${BUN_STUB_RACE:-}" ]; then
    "$HOME/.local/bin/ocode" 300 &
    echo "$!" >"${BUN_RACE_PID:?}"
fi
for arg in "$@"; do
    case "$arg" in
        --outdir=*) out="${arg#--outdir=}" ;;
    esac
done
mkdir -p "$out/cli-linux-x64/bin"
printf '#!/bin/bash\necho fake ocode\n' >"$out/cli-linux-x64/bin/opencode"
chmod +x "$out/cli-linux-x64/bin/opencode"
STUB
chmod +x "$STUB/git" "$BUN_STUB/bun"

export BUN_CALLS="$TMP/bun-calls"
export BUN_ENV="$TMP/bun-env"
: >"$BUN_CALLS"
: >"$BUN_ENV"

# stdin is /dev/null unless a file is given, so a case that reaches the kill prompt and answers
# nothing declines it instead of reading the test runner's terminal.
run_script() { (cd "$TMP" && PATH="$BUN_STUB:$STUB:$PATH" bash "$SCRIPT" <"${1:-/dev/null}") >"$TMP/out" 2>&1; echo $? >"$TMP/rc"; }
rc() { cat "$TMP/rc"; }
calls() { wc -l <"$BUN_CALLS"; }

# 1) No checkout: skip, no binary, no marker, and the message says why.
rm -rf "$CHECKOUT"
run_script
[ "$(rc)" -eq 0 ] || fail "skip without checkout must exit 0"
[ ! -e "$HOME/.local/bin/ocode" ] || fail "skip must not install a binary"
grep -q "no fork checkout" "$TMP/out" || fail "skip must say why"
pass "no checkout skips"

# 2) First build installs an executable ocode, records the head, and builds as a release-grade
#    client on the fork's channel -- the Console's free tier refuses client versions below
#    1.18.0, which a bare branch build's preview version would be.
mkdir -p "$CHECKOUT/.git"
printf 'fake0123\n' >"$CHECKOUT/.git/HEAD"
run_script
[ "$(rc)" -eq 0 ] || fail "first build must exit 0"
[ -x "$HOME/.local/bin/ocode" ] || fail "first build must install an executable ocode"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake0123" ] || fail "marker must hold the built head"
[ "$(calls)" -eq 1 ] || fail "first build must invoke bun once"
identity="$(tail -n 1 "$BUN_ENV")"
[ "${identity%%/*}" = "feat-provider-omniroute" ] || fail "the build must carry the fork's channel: $identity"
[[ "${identity##*/}" =~ ^2\.0\.[0-9]+$ ]] || fail "the build must carry a release-grade version, not a preview one: $identity"
pass "first build installs ocode, records the head, and carries the fork's channel and a release-grade version"

# 3) Unchanged head: no rebuild.
run_script
[ "$(rc)" -eq 0 ] || fail "unchanged apply must exit 0"
[ "$(calls)" -eq 1 ] || fail "unchanged head must not rebuild"
pass "unchanged head does not rebuild"

# 4) New head: rebuild and move the marker.
printf 'fake4567\n' >"$CHECKOUT/.git/HEAD"
run_script
[ "$(rc)" -eq 0 ] || fail "rebuild must exit 0"
[ "$(calls)" -eq 2 ] || fail "new head must rebuild"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake4567" ] || fail "marker must move with the head"
pass "new head rebuilds"

# 5) Binary deleted but head unchanged: the rebuild restores it.
rm -f "$HOME/.local/bin/ocode"
run_script
[ "$(rc)" -eq 0 ] || fail "missing binary must rebuild"
[ -x "$HOME/.local/bin/ocode" ] || fail "missing binary must be reinstalled"
pass "missing binary is reinstalled"

# 6) bun off PATH but at ~/.bun/bin: the build runs anyway. This is the first apply after
#    `install_bun`, whose PATH export only reaches shells started after it.
mkdir -p "$HOME/.bun/bin"
cp "$BUN_STUB/bun" "$HOME/.bun/bin/bun"
rm -f "$HOME/.local/bin/ocode"
(cd "$TMP" && PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT") >"$TMP/out" 2>&1
echo $? >"$TMP/rc"
[ "$(rc)" -eq 0 ] || fail "the ~/.bun/bin fallback must build"
[ "$(calls)" -eq 4 ] || fail "the ~/.bun/bin fallback must invoke bun"
[ -x "$HOME/.local/bin/ocode" ] || fail "the ~/.bun/bin fallback must install the binary"
pass "bun at ~/.bun/bin is used when PATH has none"

# 7) No bun anywhere: skip, and the message names both places that were looked at. The
#    restricted PATH keeps any real bun out of the picture.
rm -rf "$HOME/.bun"
(cd "$TMP" && PATH="$STUB" /bin/bash "$SCRIPT") >"$TMP/out" 2>&1
echo $? >"$TMP/rc"
[ "$(rc)" -eq 0 ] || fail "a machine without bun must skip"
grep -q "bun is not installed" "$TMP/out" || fail "a machine without bun must say why"
pass "a machine without bun skips"

# The library is pure bash and defines functions only, so the test shell can source it and
# call install_bun directly under the redirected HOME.
# shellcheck source=/dev/null
source "$LIB"

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

# The fabricated upstream installer: records the SHELL it sees and its arguments, and exits
# with $INSTALLER_FAIL when set.
cat >"$TMP/bun-upstream-installer.sh" <<'FAKE'
#!/bin/bash
printf 'shell=%s\n' "${SHELL-<unset>}" >>"${INSTALLER_CALLS:?}"
printf 'args=%s\n' "$*" >>"${INSTALLER_CALLS:?}"
exit "${INSTALLER_FAIL:-0}"
FAKE

export CURL_BODY="$TMP/bun-upstream-installer.sh"
export CURL_CALLS="$TMP/curl-calls"
export INSTALLER_CALLS="$TMP/installer-calls"
: >"$CURL_CALLS"
: >"$INSTALLER_CALLS"

run_install_bun() {
    local rc=0
    (PATH="$STUB:$PATH"; cd "$TMP"; install_bun) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
curl_calls() { wc -l <"$CURL_CALLS"; }

# 8) An existing ~/.bun/bin/bun is a skip: nothing is downloaded.
mkdir -p "$HOME/.bun/bin"
cp "$BUN_STUB/bun" "$HOME/.bun/bin/bun"
run_install_bun
[ "$(rc)" -eq 0 ] || fail "the installed skip must exit 0"
[ "$(curl_calls)" -eq 0 ] || fail "the installed skip must not download anything"
grep -q "bun is already installed, skipping" "$TMP/out" || fail "the installed skip must say why"
pass "an installed bun is skipped"

# 9) A machine without bun fetches the upstream installer and runs it with SHELL empty and no
#    arguments -- with a shell named, the installer would edit that shell's rc file, which
#    chezmoi owns and rewrites.
rm -rf "$HOME/.bun"
run_install_bun
[ "$(rc)" -eq 0 ] || fail "the install must exit 0"
grep -q 'https://bun.sh/install' "$CURL_CALLS" || fail "the install must fetch the bun installer"
[ "$(sed -n '1p' "$INSTALLER_CALLS")" = "shell=" ] || fail "the installer must run with SHELL empty: $(sed -n '1p' "$INSTALLER_CALLS")"
[ "$(sed -n '2p' "$INSTALLER_CALLS")" = "args=" ] || fail "the installer must be run without arguments: $(sed -n '2p' "$INSTALLER_CALLS")"
pass "the upstream installer runs with SHELL empty"

# 10) A failed download fails the install, so `verify` retries it on the next apply.
rm -rf "$HOME/.bun"
export CURL_FAIL=1
run_install_bun
unset CURL_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed download must exit non-zero"
grep -q "failed to download the bun installer" "$TMP/out" || fail "a failed download must say what failed"
pass "a failed download fails the install"

# 11) A failed installer fails the install the same way.
rm -rf "$HOME/.bun"
export INSTALLER_FAIL=7
run_install_bun
unset INSTALLER_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed installer must exit non-zero"
grep -q "exited with status 7" "$TMP/out" || fail "a failed installer must report its status"
pass "a failed installer fails the install"

# 12) The Linux dependency installer verifies install_bun; the Android one installs nothing.
if grep -q '^verify install_bun$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_bun"
else
    fail "the Linux installer no longer verifies install_bun"
fi
if grep -q 'install_bun' "$ANDROID_INSTALLER"; then
    fail "the Android installer must not install bun"
else
    pass "the Android installer installs nothing"
fi

# 13) The ZSHENV template carries the ~/.bun/bin PATH block on Linux and macOS (the same
#     non-Android branch as flyctl and opencode) and none on Android.
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
    if render linux | grep -qF 'export PATH="$HOME/.bun/bin:$PATH"'; then
        pass "Linux carries the ~/.bun/bin PATH block"
    else
        fail "Linux lost the ~/.bun/bin PATH block"
    fi

    if render darwin | grep -qF 'export PATH="$HOME/.bun/bin:$PATH"'; then
        pass "macOS carries the ~/.bun/bin PATH block"
    else
        fail "macOS lost the ~/.bun/bin PATH block"
    fi

    if render android | grep -q '\.bun'; then
        fail "Android must not carry the ~/.bun/bin PATH block"
    else
        pass "Android carries no ~/.bun/bin PATH block"
    fi
fi

# 14) A running ocode executes the installed binary, so the prompt appears; with nothing on stdin
#     to answer it, the build is skipped, and the marker and the binary are both left alone.
printf 'fake7890\n' >"$CHECKOUT/.git/HEAD"
cp /bin/sleep "$HOME/.local/bin/ocode"
"$HOME/.local/bin/ocode" 300 &
declined_pid=$!
before="$(calls)"
run_script
[ "$(rc)" -eq 0 ] || fail "a declined prompt must exit 0"
grep -q "ocode is running" "$TMP/out" || fail "a running ocode must be reported"
grep -q "skipped the build" "$TMP/out" || fail "a declined prompt must say the build was skipped"
[ "$(calls)" -eq "$before" ] || fail "a declined prompt must not build"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake4567" ] || fail "a declined prompt must leave the marker"
cmp -s "$HOME/.local/bin/ocode" /bin/sleep || fail "a declined prompt must leave the binary"
pass "a running ocode is asked about, and a decline skips the build"

# 15) The same situation answered yes: the process is killed and the build runs.
printf 'y\n' >"$TMP/answer"
before="$(calls)"
run_script "$TMP/answer"
[ "$(rc)" -eq 0 ] || fail "an accepted prompt must exit 0"
grep -q "killed PID" "$TMP/out" || fail "an accepted prompt must report the kill"
[ "$(calls)" -eq $((before + 1)) ] || fail "an accepted prompt must build"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake7890" ] || fail "an accepted prompt must move the marker"
grep -q "fake ocode" "$HOME/.local/bin/ocode" || fail "an accepted prompt must install the new binary"
wait "$declined_pid" 2>/dev/null || true
if kill -0 "$declined_pid" 2>/dev/null; then
    fail "the killed ocode must be gone"
fi
pass "a running ocode is killed when the prompt is accepted, and the build proceeds"

# 16) An unchanged head needs no build, so a running ocode is not asked about at all.
cp /bin/sleep "$HOME/.local/bin/ocode"
"$HOME/.local/bin/ocode" 300 &
unchanged_pid=$!
before="$(calls)"
run_script
[ "$(rc)" -eq 0 ] || fail "an unchanged head must exit 0 with ocode running"
[ "$(calls)" -eq "$before" ] || fail "an unchanged head must not build with ocode running"
if grep -q "ocode is running" "$TMP/out"; then
    fail "an unchanged head must not prompt about ocode"
fi
kill -0 "$unchanged_pid" 2>/dev/null || fail "the running ocode must be left alone when nothing builds"
kill "$unchanged_pid" 2>/dev/null || true
wait "$unchanged_pid" 2>/dev/null || true
pass "a running ocode is not prompted about when the head is unchanged"

# 17) One started *while* the build runs (the stub starts it mid-build) must not fail the install:
#     a direct cp onto it would die with "Text file busy", the staged rename replaces it.
printf 'fake9999\n' >"$CHECKOUT/.git/HEAD"
export BUN_STUB_RACE=1 BUN_RACE_PID="$TMP/race-pid"
before="$(calls)"
run_script
unset BUN_STUB_RACE BUN_RACE_PID
race_pid="$(cat "$TMP/race-pid")"
[ "$(rc)" -eq 0 ] || fail "a process started mid-build must not fail the install"
if grep -q "Text file busy" "$TMP/out"; then
    fail "the install must not lose the running-binary race"
fi
[ "$(calls)" -eq $((before + 1)) ] || fail "the race case must build once"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake9999" ] || fail "the race case must move the marker"
grep -q "fake ocode" "$HOME/.local/bin/ocode" || fail "the race case must install the new binary"
kill -0 "$race_pid" 2>/dev/null || fail "the racing process must be left running (it holds the old file)"
kill "$race_pid" 2>/dev/null || true
wait "$race_pid" 2>/dev/null || true
pass "a process started mid-build cannot fail the install"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-ocode] all ocode fork-builder and bun provisioning tests passed" >&2
fi
exit $EXIT_CODE
