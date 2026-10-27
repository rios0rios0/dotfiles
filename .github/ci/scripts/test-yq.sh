#!/bin/bash
set -euo pipefail

# Tests `install_yq` in the Linux dependency installer without the network or a real yq: the
# function is lifted out of the installer, which renders it unchanged, with its pinned SHA-256
# swapped for the digest of a fabricated binary that a `curl` stub serves. Covers the install
# going ahead while Kali's Python yq is on PATH (a `command -v yq` check would have skipped it),
# the skip once the pinned version is in ~/.local/bin, the replacement of an older one, a
# download that does not match the pin, a failed download, and the wiring: the installer verifies
# the call, apt no longer installs `yq`, and the Linux removal script tombstones the apt package.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
LINUX_REMOVAL="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-006-remove-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-yq] testing the yq install..." >&2

pass() { echo "[test-yq] PASS: $1" >&2; }
fail() { echo "[test-yq] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_yq() {$/,/^}$/p' "$LINUX_INSTALLER")"
VERSION="$(sed -n 's/^    local version="\(.*\)"$/\1/p' <<<"$FUNCTION")"
if [[ -z "$FUNCTION" || -z "$VERSION" ]]; then
    fail "install_yq or its pinned version was not found in the Linux installer"
    exit 1
fi

# The fabricated releases: one that reports the pinned version, one an older version, and one
# whose bytes the pin does not cover.
fake_yq() {
    printf '#!/bin/bash\necho "yq (https://github.com/mikefarah/yq/) version v%s"\n' "$1" >"$2"
    chmod +x "$2"
}
fake_yq "$VERSION" "$TMP/release"
fake_yq "4.0.0" "$TMP/older"
fake_yq "$VERSION-tampered" "$TMP/tampered"
DIGEST="$(sha256sum "$TMP/release" | cut -d' ' -f1)"

# Both architectures' pins become the fabricated release's digest, so the runner's own
# architecture does not decide which one the function checks.
# shellcheck source=/dev/null
source <(sed -E "s/sha256=\"[0-9a-f]{64}\"/sha256=\"$DIGEST\"/g" <<<"$FUNCTION")

export HOME="$TMP/home"
STUB="$TMP/stub"
mkdir -p "$HOME" "$STUB"

# curl stub: records every invocation and copies $CURL_BODY to the -o target, unless $CURL_FAIL
# is set, standing in for a failed download.
cat >"$STUB/curl" <<'STUB'
#!/bin/bash
echo "$*" >>"${CURL_CALLS:?}"
[[ -z "${CURL_FAIL:-}" ]] || exit 22
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "${CURL_BODY:?}" "$out"
STUB
# Kali's Python yq, which answers to the same name.
printf '#!/bin/bash\necho "yq 3.4.3"\n' >"$STUB/yq"
chmod +x "$STUB/curl" "$STUB/yq"

CURL_CALLS="$TMP/curl-calls"
export CURL_CALLS

# run_install <body>: runs install_yq with the stubs ahead of PATH, serving <body>.
run_install() {
    local rc=0
    : >"$CURL_CALLS"
    (export CURL_BODY="$1"; PATH="$STUB:$PATH"; install_yq) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
curl_calls() { wc -l <"$CURL_CALLS"; }
installed_version() { "$HOME/.local/bin/yq" --version 2>/dev/null; }

# given Kali's Python yq on PATH and nothing in ~/.local/bin
# when install_yq runs
# then the pinned release is downloaded, verified and installed anyway
run_install "$TMP/release"
if [ "$(rc)" -eq 0 ] && [ "$(curl_calls)" -eq 1 ] &&
    grep -qF "mikefarah/yq/releases/download/v$VERSION/yq_linux_" "$CURL_CALLS" &&
    [[ "$(installed_version)" == *"version v$VERSION" ]]; then
    pass "the Python yq on PATH does not stop the install of $VERSION"
else
    fail "install with the Python yq on PATH: rc=$(rc), calls=$(cat "$CURL_CALLS"), $(cat "$TMP/out")"
fi

# given the pinned version in ~/.local/bin
# when install_yq runs again
# then nothing is downloaded and the skip says why
run_install "$TMP/release"
if [ "$(rc)" -eq 0 ] && [ "$(curl_calls)" -eq 0 ] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "the pinned version is skipped"
else
    fail "the pinned version was not skipped: rc=$(rc), $(cat "$TMP/out")"
fi

# given an older yq in ~/.local/bin, as a bumped pin leaves it
# when install_yq runs
# then it is replaced
cp "$TMP/older" "$HOME/.local/bin/yq"
run_install "$TMP/release"
if [ "$(rc)" -eq 0 ] && [ "$(curl_calls)" -eq 1 ] && [[ "$(installed_version)" == *"version v$VERSION" ]]; then
    pass "an older yq is replaced by the pinned one"
else
    fail "an older yq was not replaced: rc=$(rc), $(installed_version)"
fi

# given a download whose bytes the pin does not cover
# when install_yq runs on a machine without yq
# then it fails and installs nothing
rm -f "$HOME/.local/bin/yq"
run_install "$TMP/tampered"
if [ "$(rc)" -ne 0 ] && [ ! -e "$HOME/.local/bin/yq" ] && grep -q "does not match its pinned SHA-256" "$TMP/out"; then
    pass "a download that does not match the pin fails and installs nothing"
else
    fail "a mismatched download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a failed download
# when install_yq runs
# then it fails and says what failed
export CURL_FAIL=1
run_install "$TMP/release"
unset CURL_FAIL
if [ "$(rc)" -ne 0 ] && [ ! -e "$HOME/.local/bin/yq" ] && grep -q "failed to download yq" "$TMP/out"; then
    pass "a failed download fails the install"
else
    fail "a failed download: rc=$(rc), $(cat "$TMP/out")"
fi

# The wiring: the installer verifies the call, so a failure fails the run and the next apply
# retries it; apt no longer installs the Python yq; and the removal script takes it off machines
# that already have it.
if grep -q '^verify install_yq$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_yq"
else
    fail "the Linux installer no longer verifies install_yq"
fi
if sed -n '/^utilities=(/,/^)/p' "$LINUX_INSTALLER" | grep -qE '^\s*"yq"'; then
    fail "apt still installs \"yq\", Kali's Python wrapper, in the utilities list"
else
    pass "apt no longer installs Kali's Python yq"
fi
if grep -qE '^\s*"apt:yq"$' "$LINUX_REMOVAL"; then
    pass "the Linux removal script tombstones the apt yq"
else
    fail "the Linux removal script does not tombstone apt:yq"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-yq] all yq install tests passed" >&2
fi
exit "$EXIT_CODE"
