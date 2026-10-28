#!/bin/bash
set -euo pipefail

# Tests `install_chlog` from the shared install library without the network or a real Go: a `go`
# stub stands in for `go install` and writes a chlog that reports the version its -ldflags stamp.
# Covers the install (upstream's module at the pinned tag, the version stamp, ~/.local/bin), the
# skip once the pinned version is there, the replacement of an older or unstamped build, a machine
# without Go, a failed build, a build that does not report the pin, and the wiring: both platform
# installers verify the call after Go is in place, and only the library defines the function.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIBRARY="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-chlog] testing the chlog install..." >&2

pass() { echo "[test-chlog] PASS: $1" >&2; }
fail() { echo "[test-chlog] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_chlog() {$/,/^}$/p' "$LIBRARY")"
VERSION="$(sed -n 's/^    local version="\(.*\)"$/\1/p' <<<"$FUNCTION")"
if [[ -z "$FUNCTION" || -z "$VERSION" ]]; then
    fail "install_chlog or its pinned version was not found in the shared install library"
    exit 1
fi

# The library only defines functions, so it is sourced whole: install_chlog uses command_exists.
# shellcheck source=/dev/null
source "$LIBRARY"

export HOME="$TMP/home"
STUB="$TMP/stub"
mkdir -p "$HOME" "$STUB" "$TMP/no-go"

# go stub: records its command line with the GOBIN it got and, for `install`, writes a chlog into
# GOBIN reporting the version the -ldflags stamp -- or $GO_STAMP, standing in for a build that
# ignored the stamp -- unless $GO_FAIL is set, standing in for a failed build.
cat >"$STUB/go" <<'STUB'
#!/bin/bash
echo "GOBIN=${GOBIN:-} go $*" >>"${GO_CALLS:?}"
[[ -z "${GO_FAIL:-}" ]] || exit 1
[[ "$1" == install ]] || exit 0
version=""
for arg in "$@"; do
    [[ "$arg" != "-X main.version="* ]] || version="${arg#-X main.version=}"
done
printf '#!/bin/bash\necho "chlog version: %s"\n' "${GO_STAMP:-$version}" >"${GOBIN:?}/chlog"
chmod +x "$GOBIN/chlog"
STUB
chmod +x "$STUB/go"
export GO_CALLS="$TMP/go-calls"

# fake_chlog <version>: a chlog in ~/.local/bin reporting <version>, as a previous install left it.
fake_chlog() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/bash\necho "chlog version: %s"\n' "$1" >"$HOME/.local/bin/chlog"
    chmod +x "$HOME/.local/bin/chlog"
}

# run_install [PATH]: install_chlog with PATH holding the stub (or the given directory), its output
# in $TMP/out and its status in $TMP/rc
run_install() {
    local status=0
    : >"$GO_CALLS"
    (export PATH="${1:-$STUB:/usr/bin:/bin}"; install_chlog) >"$TMP/out" 2>&1 || status=$?
    echo "$status" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
go_calls() { wc -l <"$GO_CALLS" | tr -d ' '; }
installed_version() { "$HOME/.local/bin/chlog" --version 2>/dev/null || true; }

# given a machine without chlog
# when install_chlog runs
# then Go installs upstream's module at the pinned tag into ~/.local/bin, stamped with its version
run_install
expected="GOBIN=$HOME/.local/bin go install -ldflags -X main.version=$VERSION github.com/luizjhonata/chlog@v$VERSION"
if [[ "$(rc)" -eq 0 ]] && grep -qxF "$expected" "$GO_CALLS" && [[ "$(installed_version)" == "chlog version: $VERSION" ]]; then
    pass "chlog is installed from upstream's pinned tag into ~/.local/bin, stamped with its version"
else
    fail "a first install: rc=$(rc), calls=$(cat "$GO_CALLS"), $(cat "$TMP/out")"
fi

# given the pinned version in ~/.local/bin
# when install_chlog runs again
# then Go is not run, and the skip says why
run_install
if [[ "$(rc)" -eq 0 ]] && [[ "$(go_calls)" -eq 0 ]] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "the pinned version is skipped"
else
    fail "the pinned version was not skipped: rc=$(rc), $(cat "$TMP/out")"
fi

# given an older chlog, as a bumped pin leaves it, or one an unstamped `go install` built
# when install_chlog runs
# then it is replaced by the pinned one
for older in 0.3.1 dev; do
    fake_chlog "$older"
    run_install
    if [[ "$(rc)" -eq 0 ]] && [[ "$(go_calls)" -eq 1 ]] && [[ "$(installed_version)" == "chlog version: $VERSION" ]]; then
        pass "a chlog reporting '$older' is replaced by the pinned one"
    else
        fail "a chlog reporting '$older' was not replaced: rc=$(rc), $(installed_version)"
    fi
done

# given a machine without Go
# when install_chlog runs
# then it fails, says why and installs nothing
rm -f "$HOME/.local/bin/chlog"
run_install "$TMP/no-go"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/chlog" ]] && grep -q "go is not available" "$TMP/out"; then
    pass "a machine without Go fails the install and says why"
else
    fail "a machine without Go: rc=$(rc), $(cat "$TMP/out")"
fi

# given a build that fails
# when install_chlog runs
# then it fails and names what failed
export GO_FAIL=1
run_install
unset GO_FAIL
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/chlog" ]] &&
    grep -qF "go install github.com/luizjhonata/chlog@v$VERSION failed" "$TMP/out"; then
    pass "a failed build fails the install"
else
    fail "a failed build: rc=$(rc), $(cat "$TMP/out")"
fi

# given a build that does not report the pinned version
# when install_chlog runs
# then it fails rather than report a chlog it cannot vouch for
export GO_STAMP=dev
run_install
unset GO_STAMP
if [[ "$(rc)" -ne 0 ]] && grep -q "does not report chlog $VERSION" "$TMP/out"; then
    pass "a build that does not report the pinned version fails the install"
else
    fail "a build that does not report the pin: rc=$(rc), $(cat "$TMP/out")"
fi

# The wiring: each platform installer pulls in the library and verifies the call, so a failure
# fails the run and the next apply retries it; neither defines a copy of its own; and on Linux the
# call comes after install_gvm, which puts Go on PATH, while Android installs Termux's golang.
for installer in "$LINUX_INSTALLER" "$ANDROID_INSTALLER"; do
    name="$(basename "$installer")"
    if grep -qF '{{ template "lib-install-deps.sh" }}' "$installer" && grep -qx 'verify install_chlog' "$installer" &&
        ! grep -q '^install_chlog() {$' "$installer"; then
        pass "$name verifies the library's install_chlog"
    else
        fail "$name does not verify the library's install_chlog"
    fi
done
gvm_line="$(grep -n '^install_gvm || exit 1$' "$LINUX_INSTALLER" | cut -d: -f1)"
chlog_line="$(grep -n '^verify install_chlog$' "$LINUX_INSTALLER" | cut -d: -f1)"
if [[ -n "$gvm_line" && -n "$chlog_line" && "$gvm_line" -lt "$chlog_line" ]]; then
    pass "the Linux installer installs chlog after GVM's Go"
else
    fail "the Linux installer does not install chlog after install_gvm: gvm=$gvm_line chlog=$chlog_line"
fi
if grep -qE '^\s*"golang"' "$ANDROID_INSTALLER"; then
    pass "the Android installer installs Termux's golang"
else
    fail "the Android installer no longer installs Termux's golang, which install_chlog builds with"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-chlog] all chlog install tests passed" >&2
fi

exit "$EXIT_CODE"
