#!/bin/bash
set -euo pipefail

# Tests the ocode fork-builder and the bun provisioning it depends on, without bun, git, the
# network or a real fork checkout: `git` and `bun` are stubs, the checkout is a fake directory
# whose `.git` holds a head, a branch and refs, the build fabricates the artifact the fork's
# build would emit, and `install_bun` is sourced from the shared dependency library against a
# `curl` stub that fabricates the upstream installer. Covers the checkout the builder obtains
# itself (the clone onto the fork's branch with the fork/upstream remote layout, the branch
# switch, the branch created from the fork's remote-tracking one, the checkout holding no fork
# branch, a directory that is not a checkout, a failed clone), the skip without bun, the first
# build (including the fork channel and release-grade version it must carry), the no-op
# rebuild, the rebuild on a new head, the rebuild that restores a missing binary, the prompt
# for a running ocode with no answer, a decline and an acceptance -- none of which may skip the
# build -- the process started while the build runs, the ~/.bun/bin fallback, the installed
# skip, the installer call (with SHELL empty, so bun's script cannot edit an rc file chezmoi
# owns), both installer failures, the Linux wiring and the PATH block rendered on each platform.

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

# git stub: a fake checkout under .git -- HEAD holds the sha, HEAD_REF the branch, refs/ the
# branches and the remote-tracking ones, remotes/ the remote URLs -- so the clone, the branch
# switch and the remote layout are all assertable. Every invocation is recorded in $GIT_CALLS.
# CLONE_FAIL makes the clone fail the way a machine without the network does.
cat >"$STUB/git" <<'STUB'
#!/bin/bash
echo "$*" >>"${GIT_CALLS:?}"
if [ "$1" = "-C" ]; then
    dir="$2"
    shift 2
else
    dir="$PWD"
fi
sub="$1"
shift
case "$sub" in
    rev-parse)
        case "$*" in
            "HEAD") cat "$dir/.git/HEAD" ;;
            "--abbrev-ref HEAD") cat "$dir/.git/HEAD_REF" ;;
            --verify*)
                for arg in "$@"; do ref="$arg"; done
                [ -e "$dir/.git/$ref" ]
                ;;
            *) echo "stub git: unexpected rev-parse: $*" >&2; exit 1 ;;
        esac
        ;;
    log) echo "fake0123 chore: fake fork commit" ;;
    clone)
        [[ -z "${CLONE_FAIL:-}" ]] || exit 128
        remote=""; branch=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --origin) remote="$2"; shift 2 ;;
                --branch) branch="$2"; shift 2 ;;
                *) url="$1"; target="$1"; shift ;;
            esac
        done
        mkdir -p "$target/.git" "$target/.git/remotes"
        printf '%s\n' "$branch" >"$target/.git/HEAD_REF"
        printf 'fake0001\n' >"$target/.git/HEAD"
        mkdir -p "$(dirname "$target/.git/refs/heads/$branch")" "$(dirname "$target/.git/refs/remotes/$remote/$branch")"
        : >"$target/.git/refs/heads/$branch"
        : >"$target/.git/refs/remotes/$remote/$branch"
        printf '%s\n' "$url" >"$target/.git/remotes/$remote"
        ;;
    remote)
        case "$1" in
            get-url)
                [ -f "$dir/.git/remotes/$2" ] || exit 2
                cat "$dir/.git/remotes/$2"
                ;;
            add)
                mkdir -p "$dir/.git/remotes"
                printf '%s\n' "$3" >"$dir/.git/remotes/$2"
                ;;
            *) echo "stub git: unexpected remote: $*" >&2; exit 1 ;;
        esac
        ;;
    checkout)
        if [ "$1" = "-b" ]; then
            branch="$2"
            mkdir -p "$(dirname "$dir/.git/refs/heads/$branch")"
            : >"$dir/.git/refs/heads/$branch"
        else
            branch="$1"
            [ -e "$dir/.git/refs/heads/$branch" ] || exit 1
        fi
        printf '%s\n' "$branch" >"$dir/.git/HEAD_REF"
        ;;
    *) echo "stub git: unexpected args: $*" >&2; exit 1 ;;
esac
STUB
export GIT_CALLS="$TMP/git-calls"
: >"$GIT_CALLS"

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
# nothing leaves the running ocode alone and builds anyway, instead of reading the test runner's
# terminal.
run_script() { (cd "$TMP" && PATH="$BUN_STUB:$STUB:$PATH" bash "$SCRIPT" <"${1:-/dev/null}") >"$TMP/out" 2>&1; echo $? >"$TMP/rc"; }
rc() { cat "$TMP/rc"; }
calls() { wc -l <"$BUN_CALLS"; }

# 1) No checkout: the fork is cloned onto its branch, the remotes are named the way the
#    hand-made checkouts on this machine have them (`fork` for rios0rios0, `origin` for sst
#    upstream), and the build then runs -- a fresh machine ends the apply with ocode installed
#    *and* the checkout ready to edit. The build carries a release-grade version on the fork's
#    channel, because the Console's free tier refuses client versions below 1.18.0 and a bare
#    branch build's preview version falls below it.
rm -rf "$CHECKOUT"
run_script
[ "$(rc)" -eq 0 ] || fail "the clone must exit 0"
grep -qF "clone --origin fork --branch feat/provider-omniroute https://github.com/rios0rios0/opencode.git $CHECKOUT" "$GIT_CALLS" ||
    fail "a missing checkout must be cloned from the fork on its branch"
[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "feat/provider-omniroute" ] || fail "the clone must land on the fork's branch"
[ "$(cat "$CHECKOUT/.git/remotes/origin")" = "https://github.com/sst/opencode.git" ] ||
    fail "the clone must get sst upstream as origin"
[ -x "$HOME/.local/bin/ocode" ] || fail "the build after the clone must install an executable ocode"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake0001" ] || fail "marker must hold the built head"
[ "$(calls)" -eq 1 ] || fail "the first build must invoke bun once"
identity="$(tail -n 1 "$BUN_ENV")"
[ "${identity%%/*}" = "feat-provider-omniroute" ] || fail "the build must carry the fork's channel: $identity"
[[ "${identity##*/}" =~ ^2\.0\.[0-9]+$ ]] || fail "the build must carry a release-grade version, not a preview one: $identity"
pass "a missing checkout is cloned onto the fork's branch with the fork/upstream remotes, then built"

# 2) A checkout left on another branch is switched to the fork's: the channel below is stamped
#    onto whatever HEAD holds, so building `main` would label a binary as the fork and carry
#    none of its code. The head is unchanged, so nothing is rebuilt.
printf 'main\n' >"$CHECKOUT/.git/HEAD_REF"
before="$(calls)"
: >"$GIT_CALLS"
run_script
[ "$(rc)" -eq 0 ] || fail "a branch switch must exit 0"
grep -q "checkout is on main, switching to feat/provider-omniroute" "$TMP/out" || fail "the switch must say which branch it came from"
[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "feat/provider-omniroute" ] || fail "the checkout must end on the fork's branch"
[ "$(calls)" -eq "$before" ] || fail "an unchanged head must not rebuild after a branch switch"
pass "a checkout on another branch is switched to the fork's without rebuilding"

# 3) The branch is missing locally but the fork's remote-tracking one is there: it is created
#    from that, so a clone made by hand with another branch checked out still lands on the fork.
rm -f "$CHECKOUT/.git/refs/heads/feat/provider-omniroute"
printf 'main\n' >"$CHECKOUT/.git/HEAD_REF"
: >"$GIT_CALLS"
run_script
[ "$(rc)" -eq 0 ] || fail "tracking the fork's branch must exit 0"
grep -qF "checkout -b feat/provider-omniroute --track fork/feat/provider-omniroute" "$GIT_CALLS" ||
    fail "a missing local branch must be created from fork/<branch>"
[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "feat/provider-omniroute" ] || fail "the tracked branch must be checked out"
pass "a missing local branch is created from the fork's remote-tracking one"

# 4) Neither the branch nor the fork's remote one exists: the checkout is left alone and
#    nothing is built, rather than building whatever branch it happens to be on.
rm -rf "$CHECKOUT/.git/refs/heads/feat/provider-omniroute" "$CHECKOUT/.git/refs/remotes"
printf 'main\n' >"$CHECKOUT/.git/HEAD_REF"
rm -f "$HOME/.local/bin/ocode"
before="$(calls)"
run_script
[ "$(rc)" -eq 0 ] || fail "a checkout without the fork's branch must skip"
grep -q "has no feat/provider-omniroute branch" "$TMP/out" || fail "the missing branch must be reported"
[ "$(calls)" -eq "$before" ] || fail "a checkout without the fork's branch must not build"
[ ! -e "$HOME/.local/bin/ocode" ] || fail "a checkout without the fork's branch must not install a binary"
pass "a checkout with no fork branch warns and builds nothing"

# 5) A directory that is not a checkout is not cloned into: it may hold somebody's work, and a
#    clone would either fail on it or, worse, be mistaken for done.
rm -rf "$CHECKOUT"
mkdir -p "$CHECKOUT"
before="$(wc -l <"$GIT_CALLS")"
run_script
[ "$(rc)" -eq 0 ] || fail "a non-checkout directory must skip"
grep -q "exists but is not a git checkout" "$TMP/out" || fail "a non-checkout directory must say why it is left alone"
[ "$(wc -l <"$GIT_CALLS")" -eq "$before" ] || fail "a non-checkout directory must not be cloned into"
pass "a directory that is not a checkout is left alone"

# 6) A clone that fails -- no network, for instance -- is a warning, not a failed apply: there
#    is simply nothing to build yet, and the next apply tries again.
rm -rf "$CHECKOUT"
export CLONE_FAIL=1
run_script
unset CLONE_FAIL
[ "$(rc)" -eq 0 ] || fail "a failed clone must not fail the apply"
grep -q "WARN: failed to clone" "$TMP/out" || fail "a failed clone must say what failed"
[ ! -e "$HOME/.local/bin/ocode" ] || fail "a failed clone must not install a binary"
pass "a failed clone warns and skips"

# Restore the checkout the remaining cases build from: the head test 1 built, on the fork's
# branch, with the binary that the marker now matches.
rm -rf "$CHECKOUT"
mkdir -p "$CHECKOUT/.git/refs/heads/feat" "$CHECKOUT/.git/refs/remotes/fork/feat"
printf 'fake0001\n' >"$CHECKOUT/.git/HEAD"
printf 'feat/provider-omniroute\n' >"$CHECKOUT/.git/HEAD_REF"
: >"$CHECKOUT/.git/refs/heads/feat/provider-omniroute"
: >"$CHECKOUT/.git/refs/remotes/fork/feat/provider-omniroute"
printf '#!/bin/bash\necho fake ocode\n' >"$HOME/.local/bin/ocode"
chmod +x "$HOME/.local/bin/ocode"
# 7) Unchanged head: no rebuild.
run_script
[ "$(rc)" -eq 0 ] || fail "unchanged apply must exit 0"
[ "$(calls)" -eq 1 ] || fail "unchanged head must not rebuild"
pass "unchanged head does not rebuild"

# 8) New head: rebuild and move the marker.
printf 'fake4567\n' >"$CHECKOUT/.git/HEAD"
run_script
[ "$(rc)" -eq 0 ] || fail "rebuild must exit 0"
[ "$(calls)" -eq 2 ] || fail "new head must rebuild"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake4567" ] || fail "marker must move with the head"
pass "new head rebuilds"

# 9) Binary deleted but head unchanged: the rebuild restores it.
rm -f "$HOME/.local/bin/ocode"
run_script
[ "$(rc)" -eq 0 ] || fail "missing binary must rebuild"
[ -x "$HOME/.local/bin/ocode" ] || fail "missing binary must be reinstalled"
pass "missing binary is reinstalled"

# 10) bun off PATH but at ~/.bun/bin: the build runs anyway. This is the first apply after
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

# 11) No bun anywhere: skip, and the message names both places that were looked at. The
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

# 12) An existing ~/.bun/bin/bun is a skip: nothing is downloaded.
mkdir -p "$HOME/.bun/bin"
cp "$BUN_STUB/bun" "$HOME/.bun/bin/bun"
run_install_bun
[ "$(rc)" -eq 0 ] || fail "the installed skip must exit 0"
[ "$(curl_calls)" -eq 0 ] || fail "the installed skip must not download anything"
grep -q "bun is already installed, skipping" "$TMP/out" || fail "the installed skip must say why"
pass "an installed bun is skipped"

# 13) A machine without bun fetches the upstream installer and runs it with SHELL empty and no
#    arguments -- with a shell named, the installer would edit that shell's rc file, which
#    chezmoi owns and rewrites.
rm -rf "$HOME/.bun"
run_install_bun
[ "$(rc)" -eq 0 ] || fail "the install must exit 0"
grep -q 'https://bun.sh/install' "$CURL_CALLS" || fail "the install must fetch the bun installer"
[ "$(sed -n '1p' "$INSTALLER_CALLS")" = "shell=" ] || fail "the installer must run with SHELL empty: $(sed -n '1p' "$INSTALLER_CALLS")"
[ "$(sed -n '2p' "$INSTALLER_CALLS")" = "args=" ] || fail "the installer must be run without arguments: $(sed -n '2p' "$INSTALLER_CALLS")"
pass "the upstream installer runs with SHELL empty"

# 14) A failed download fails the install, so `verify` retries it on the next apply.
rm -rf "$HOME/.bun"
export CURL_FAIL=1
run_install_bun
unset CURL_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed download must exit non-zero"
grep -q "failed to download the bun installer" "$TMP/out" || fail "a failed download must say what failed"
pass "a failed download fails the install"

# 15) A failed installer fails the install the same way.
rm -rf "$HOME/.bun"
export INSTALLER_FAIL=7
run_install_bun
unset INSTALLER_FAIL
[ "$(rc)" -ne 0 ] || fail "a failed installer must exit non-zero"
grep -q "exited with status 7" "$TMP/out" || fail "a failed installer must report its status"
pass "a failed installer fails the install"

# 16) The Linux dependency installer verifies install_bun; the Android one installs nothing.
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

# 17) The ZSHENV template carries the ~/.bun/bin PATH block on Linux and macOS (the same
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

# 18) A running ocode executes the installed binary, so the prompt appears; with nothing on stdin
#     to answer it (an unattended apply), the session is left alone and the build runs anyway --
#     the staged rename replaces the file under a running process without disturbing it.
printf 'fake7890\n' >"$CHECKOUT/.git/HEAD"
cp /bin/sleep "$HOME/.local/bin/ocode"
"$HOME/.local/bin/ocode" 300 &
unanswered_pid=$!
before="$(calls)"
run_script
[ "$(rc)" -eq 0 ] || fail "an unanswered prompt must exit 0"
grep -q "ocode is running" "$TMP/out" || fail "a running ocode must be reported"
grep -q "leaving PID" "$TMP/out" || fail "an unanswered prompt must say the session is left alone"
[ "$(calls)" -eq $((before + 1)) ] || fail "an unanswered prompt must build anyway"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake7890" ] || fail "an unanswered prompt must move the marker"
grep -q "fake ocode" "$HOME/.local/bin/ocode" || fail "an unanswered prompt must install the new binary"
kill -0 "$unanswered_pid" 2>/dev/null || fail "the running ocode must survive the build"
kill "$unanswered_pid" 2>/dev/null || true
wait "$unanswered_pid" 2>/dev/null || true
pass "a running ocode is asked about, and an unanswered prompt builds anyway without touching it"

# 19) The same situation answered no: the session is still left alone and the build still runs.
printf 'fakeabcd\n' >"$CHECKOUT/.git/HEAD"
cp /bin/sleep "$HOME/.local/bin/ocode"
"$HOME/.local/bin/ocode" 300 &
declined_pid=$!
before="$(calls)"
printf 'n\n' >"$TMP/answer"
run_script "$TMP/answer"
[ "$(rc)" -eq 0 ] || fail "a declined prompt must exit 0"
grep -q "leaving PID" "$TMP/out" || fail "a declined prompt must say the session is left alone"
[ "$(calls)" -eq $((before + 1)) ] || fail "a declined prompt must build anyway"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fakeabcd" ] || fail "a declined prompt must move the marker"
grep -q "fake ocode" "$HOME/.local/bin/ocode" || fail "a declined prompt must install the new binary"
kill -0 "$declined_pid" 2>/dev/null || fail "the running ocode must survive a declined prompt"
kill "$declined_pid" 2>/dev/null || true
wait "$declined_pid" 2>/dev/null || true
pass "a running ocode survives a decline, and the build proceeds"

# 20) Answered yes: the process is killed first, and then the build runs.
printf 'fakefade\n' >"$CHECKOUT/.git/HEAD"
cp /bin/sleep "$HOME/.local/bin/ocode"
"$HOME/.local/bin/ocode" 300 &
accepted_pid=$!
printf 'y\n' >"$TMP/answer"
before="$(calls)"
run_script "$TMP/answer"
[ "$(rc)" -eq 0 ] || fail "an accepted prompt must exit 0"
grep -q "killed PID" "$TMP/out" || fail "an accepted prompt must report the kill"
[ "$(calls)" -eq $((before + 1)) ] || fail "an accepted prompt must build"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fakefade" ] || fail "an accepted prompt must move the marker"
grep -q "fake ocode" "$HOME/.local/bin/ocode" || fail "an accepted prompt must install the new binary"
wait "$accepted_pid" 2>/dev/null || true
if kill -0 "$accepted_pid" 2>/dev/null; then
    fail "the killed ocode must be gone"
fi
pass "a running ocode is killed when the prompt is accepted, and the build proceeds"

# 21) An unchanged head needs no build, so a running ocode is not asked about at all.
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

# 22) One started *while* the build runs (the stub starts it mid-build) must not fail the install:
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
