#!/bin/bash
set -euo pipefail

# Tests `install_tflint` in the Linux dependency installer without the network or a real TFLint:
# the function is lifted out of the installer, which renders it unchanged, with its pinned SHA-256
# swapped for the digest of a fabricated release zip that a `curl` stub serves. Covers the install
# going ahead while another TFLint is on PATH (a `command -v tflint` check would have skipped it),
# the skip once the pinned version is in ~/.local/bin, the replacement of an older one, version
# checks that turn off TFLint's lookup of the latest release on GitHub, a download that does not
# match the pin, a failed download, and an archive without the binary. Also checks the wiring: the
# installer verifies the call.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-tflint] testing the TFLint install..." >&2

pass() { echo "[test-tflint] PASS: $1" >&2; }
fail() { echo "[test-tflint] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_tflint() {$/,/^}$/p' "$LINUX_INSTALLER")"
VERSION="$(sed -n 's/^    local version="\(.*\)"$/\1/p' <<<"$FUNCTION")"
if [[ -z "$FUNCTION" || -z "$VERSION" ]]; then
    fail "install_tflint or its pinned version was not found in the Linux installer"
    exit 1
fi
case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) fail "no TFLint build is pinned for this runner's $(uname -m)"; exit 1 ;;
esac
# The release zips are fabricated here, so zip is needed beside the unzip the function uses.
if ! command -v zip >/dev/null 2>&1; then
    fail "zip is not on PATH, so TFLint's release zips cannot be fabricated"
    exit 1
fi

# fake_tflint <version it reports> <path>: a TFLint that answers `--version` the way the real one
# does, and records the TFLINT_DISABLE_VERSION_CHECK it ran with, which is all that keeps the real
# one from asking GitHub for the latest release.
fake_tflint() {
    local version="$1" path="$2"
    cat >"$path" <<EOF
#!/bin/bash
[[ "\$1" == --version ]] || exit 1
echo "\${TFLINT_DISABLE_VERSION_CHECK:-unset}" >>"\${VERSION_CHECKS:?}"
printf 'TFLint version %s\n+ ruleset.terraform (0.17.0-bundled)\n' "$version"
EOF
    chmod +x "$path"
}

# fake_release <version> <archive>: a release zip laid out as upstream's, the binary alone at its
# root. Without a version it holds another file instead.
fake_release() {
    local version="$1" archive="$2" dir
    dir="$(mktemp -d -p "$TMP")"
    if [[ -n "$version" ]]; then
        fake_tflint "$version" "$dir/tflint"
        (cd "$dir" && zip -q "$archive" tflint)
    else
        echo "release notes" >"$dir/README.md"
        (cd "$dir" && zip -q "$archive" README.md)
    fi
}
fake_release "$VERSION" "$TMP/release.zip"
fake_release "$VERSION-tampered" "$TMP/tampered.zip"
fake_release "" "$TMP/empty.zip"
fake_tflint "0.50.3" "$TMP/older"

# Both architectures' pins become the digest of <archive>, so the runner's own architecture does
# not decide which one the function checks.
pin_to() {
    local digest
    digest="$(sha256sum "$1" | cut -d' ' -f1)"
    # shellcheck source=/dev/null
    source <(sed -E "s/sha256=\"[0-9a-f]{64}\"/sha256=\"$digest\"/g" <<<"$FUNCTION")
}
pin_to "$TMP/release.zip"

export HOME="$TMP/home"
STUB="$TMP/stub"
mkdir -p "$HOME" "$STUB"

# curl stub: records every invocation and copies $CURL_BODY to the -o target, unless $CURL_FAIL is
# set, standing in for a failed download.
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
chmod +x "$STUB/curl"
# Another TFLint on PATH, at another version, as upstream's install script leaves one in
# /usr/local/bin.
fake_tflint "0.40.0" "$STUB/tflint"

CURL_CALLS="$TMP/curl-calls"
VERSION_CHECKS="$TMP/version-checks"
: >"$VERSION_CHECKS"
export CURL_CALLS VERSION_CHECKS

# run_install <body>: runs install_tflint with the stubs ahead of PATH, serving <body>.
run_install() {
    local rc=0
    : >"$CURL_CALLS"
    (export CURL_BODY="$1"; PATH="$STUB:$PATH"; install_tflint) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
curl_calls() { wc -l <"$CURL_CALLS"; }
# The test's own look at the binary stays out of the record of the function's version checks.
installed_version() { VERSION_CHECKS=/dev/null "$HOME/.local/bin/tflint" --version 2>/dev/null | head -n 1; }

# given another TFLint on PATH and nothing in ~/.local/bin
# when install_tflint runs
# then the pinned release for this architecture is downloaded, verified and installed anyway
run_install "$TMP/release.zip"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] &&
    grep -qF "terraform-linters/tflint/releases/download/v$VERSION/tflint_linux_$ARCH.zip" "$CURL_CALLS" &&
    [[ "$(installed_version)" == "TFLint version $VERSION" ]]; then
    pass "another TFLint on PATH does not stop the install of $VERSION"
else
    fail "install of $VERSION: rc=$(rc), calls=$(cat "$CURL_CALLS"), $(cat "$TMP/out")"
fi

# given the pinned version in ~/.local/bin
# when install_tflint runs again
# then nothing is downloaded and the skip says why
run_install "$TMP/release.zip"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 0 ]] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "the pinned version is skipped"
else
    fail "the pinned version was not skipped: rc=$(rc), $(cat "$TMP/out")"
fi

# given an older TFLint in ~/.local/bin, as a bumped pin leaves it
# when install_tflint runs
# then it is replaced
cp "$TMP/older" "$HOME/.local/bin/tflint"
run_install "$TMP/release.zip"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] && [[ "$(installed_version)" == "TFLint version $VERSION" ]]; then
    pass "an older TFLint is replaced by the pinned one"
else
    fail "an older TFLint was not replaced: rc=$(rc), $(installed_version)"
fi

# given the version checks of the three runs above
# then every one turned off TFLint's lookup of the latest release, which the real `--version`
# otherwise makes on GitHub
if [[ -s "$VERSION_CHECKS" ]] && ! grep -qvx 1 "$VERSION_CHECKS"; then
    pass "every version check turns TFLint's lookup of the latest release off"
else
    fail "a version check ran with the lookup on: TFLINT_DISABLE_VERSION_CHECK was $(paste -sd, "$VERSION_CHECKS")"
fi

# given a download whose bytes the pin does not cover
# when install_tflint runs on a machine without TFLint in ~/.local/bin
# then it fails and installs nothing
rm -f "$HOME/.local/bin/tflint"
run_install "$TMP/tampered.zip"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/tflint" ]] && grep -q "does not match its pinned SHA-256" "$TMP/out"; then
    pass "a download that does not match the pin fails and installs nothing"
else
    fail "a mismatched download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a failed download
# when install_tflint runs
# then it fails and says what failed
export CURL_FAIL=1
run_install "$TMP/release.zip"
unset CURL_FAIL
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/tflint" ]] && grep -q "failed to download TFLint" "$TMP/out"; then
    pass "a failed download fails the install"
else
    fail "a failed download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a verified archive that holds no binary
# when install_tflint runs
# then it fails and installs nothing
pin_to "$TMP/empty.zip"
run_install "$TMP/empty.zip"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/tflint" ]] && grep -q "could not unpack tflint" "$TMP/out"; then
    pass "an archive without the binary fails the install"
else
    fail "an archive without the binary: rc=$(rc), $(cat "$TMP/out")"
fi

# The wiring: the installer verifies the call, so a failure fails the run and the next apply retries
# it.
if grep -q '^verify install_tflint$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_tflint"
else
    fail "the Linux installer does not verify install_tflint"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-tflint] all TFLint install tests passed" >&2
fi
exit "$EXIT_CODE"
