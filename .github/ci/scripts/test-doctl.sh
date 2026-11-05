#!/bin/bash
set -euo pipefail

# Tests `install_doctl` in the Linux dependency installer without the network or a real doctl: the
# function is lifted out of the installer, which renders it unchanged, with its pinned SHA-256
# swapped for the digest of a fabricated release that a `curl` stub serves. Covers the install, the
# skip once the pinned version is in ~/.local/bin, the replacement of an older one, a download that
# does not match the pin, a failed download, an archive without the binary, and a `doctl version`
# that never returns -- the real one asks GitHub for the latest release with no timeout of its own
# -- failing the install within its bound instead of holding the installer up. Also checks the
# wiring: the installer verifies the call, and zsh loads Oh My Zsh's doctl plugin, which writes the
# completion.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ZSHRC_TEMPLATE="$REPO_ROOT/dot_zshrc.tmpl"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-doctl] testing the doctl install..." >&2

pass() { echo "[test-doctl] PASS: $1" >&2; }
fail() { echo "[test-doctl] FAIL: $1" >&2; EXIT_CODE=1; }

FUNCTION="$(sed -n '/^install_doctl() {$/,/^}$/p' "$LINUX_INSTALLER")"
VERSION="$(sed -n 's/^    local version="\(.*\)"$/\1/p' <<<"$FUNCTION")"
if [[ -z "$FUNCTION" || -z "$VERSION" ]]; then
    fail "install_doctl or its pinned version was not found in the Linux installer"
    exit 1
fi
case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) fail "no doctl build is pinned for this runner's $(uname -m)"; exit 1 ;;
esac

# fake_doctl <version it reports> <path>: a doctl that answers `version` the way the real one does,
# in one write. "stall" makes `version` hang, as the real one does while its lookup of the latest
# release gets no answer; the sleep is short enough that a missing bound fails this suite rather
# than hanging it.
fake_doctl() {
    local version="$1" path="$2"
    if [[ "$version" == stall ]]; then
        printf '#!/bin/bash\nexec sleep 20\n' >"$path"
    else
        cat >"$path" <<EOF
#!/bin/bash
[[ "\$1" == version ]] || exit 1
printf 'doctl version %s-release\nGit commit hash: 7e220580\nAPI endpoint: https://api.digitalocean.com/\n' "$version"
EOF
    fi
    chmod +x "$path"
}

# fake_release <version> <archive>: a release tarball laid out as upstream's, the binary alone at its
# root. Without a version it holds another file instead.
fake_release() {
    local version="$1" archive="$2" dir
    dir="$(mktemp -d -p "$TMP")"
    if [[ -n "$version" ]]; then
        fake_doctl "$version" "$dir/doctl"
        tar -czf "$archive" -C "$dir" doctl
    else
        echo "release notes" >"$dir/README.md"
        tar -czf "$archive" -C "$dir" README.md
    fi
}
fake_release "$VERSION" "$TMP/release.tar.gz"
fake_release "$VERSION-tampered" "$TMP/tampered.tar.gz"
fake_release "" "$TMP/empty.tar.gz"
fake_release stall "$TMP/stalled.tar.gz"
fake_doctl "1.186.0" "$TMP/older"
fake_doctl stall "$TMP/stalled"

# Both architectures' pins become the digest of <archive>, so the runner's own architecture does
# not decide which one the function checks.
pin_to() {
    local digest
    digest="$(sha256sum "$1" | cut -d' ' -f1)"
    # shellcheck source=/dev/null
    source <(sed -E "s/sha256=\"[0-9a-f]{64}\"/sha256=\"$digest\"/g" <<<"$FUNCTION")
}
pin_to "$TMP/release.tar.gz"

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
# timeout stub: records the bound the function asked for, then hands the command to the real
# timeout with two seconds instead, so a stalled lookup costs this suite seconds, not minutes.
cat >"$STUB/timeout" <<'STUB'
#!/bin/bash
echo "$1" >>"${TIMEOUT_CALLS:?}"
shift
exec "${REAL_TIMEOUT:?}" 2 "$@"
STUB
chmod +x "$STUB/curl" "$STUB/timeout"

CURL_CALLS="$TMP/curl-calls"
TIMEOUT_CALLS="$TMP/timeout-calls"
REAL_TIMEOUT="$(command -v timeout)"
export CURL_CALLS TIMEOUT_CALLS REAL_TIMEOUT

# run_install <body>: runs install_doctl with the stubs ahead of PATH, serving <body>.
run_install() {
    local rc=0
    : >"$CURL_CALLS"
    : >"$TIMEOUT_CALLS"
    (export CURL_BODY="$1"; PATH="$STUB:$PATH"; install_doctl) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
curl_calls() { wc -l <"$CURL_CALLS"; }
timeout_calls() { wc -l <"$TIMEOUT_CALLS"; }
installed_version() { "$HOME/.local/bin/doctl" version 2>/dev/null | head -n 1; }

# given nothing in ~/.local/bin
# when install_doctl runs
# then the pinned release for this architecture is downloaded, verified and installed
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] &&
    grep -qF "digitalocean/doctl/releases/download/v$VERSION/doctl-$VERSION-linux-$ARCH.tar.gz" "$CURL_CALLS" &&
    [[ "$(installed_version)" == "doctl version $VERSION-release" ]]; then
    pass "installs the pinned release $VERSION"
else
    fail "install of $VERSION: rc=$(rc), calls=$(cat "$CURL_CALLS"), $(cat "$TMP/out")"
fi

# given the pinned version in ~/.local/bin
# when install_doctl runs again
# then nothing is downloaded and the skip says why
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 0 ]] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "the pinned version is skipped"
else
    fail "the pinned version was not skipped: rc=$(rc), $(cat "$TMP/out")"
fi

# given an older doctl in ~/.local/bin, as a bumped pin leaves it
# when install_doctl runs
# then it is replaced
cp "$TMP/older" "$HOME/.local/bin/doctl"
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] && [[ "$(installed_version)" == "doctl version $VERSION-release" ]]; then
    pass "an older doctl is replaced by the pinned one"
else
    fail "an older doctl was not replaced: rc=$(rc), $(installed_version)"
fi

# given a download whose bytes the pin does not cover
# when install_doctl runs on a machine without doctl
# then it fails and installs nothing
rm -f "$HOME/.local/bin/doctl"
run_install "$TMP/tampered.tar.gz"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/doctl" ]] && grep -q "does not match its pinned SHA-256" "$TMP/out"; then
    pass "a download that does not match the pin fails and installs nothing"
else
    fail "a mismatched download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a failed download
# when install_doctl runs
# then it fails and says what failed
export CURL_FAIL=1
run_install "$TMP/release.tar.gz"
unset CURL_FAIL
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/doctl" ]] && grep -q "failed to download doctl" "$TMP/out"; then
    pass "a failed download fails the install"
else
    fail "a failed download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a verified archive that holds no binary
# when install_doctl runs
# then it fails and installs nothing
pin_to "$TMP/empty.tar.gz"
run_install "$TMP/empty.tar.gz"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/doctl" ]] && grep -q "archive holds no doctl" "$TMP/out"; then
    pass "an archive without the binary fails the install"
else
    fail "an archive without the binary: rc=$(rc), $(cat "$TMP/out")"
fi

# given an installed doctl whose `version` never returns, and a release that behaves the same
# when install_doctl runs
# then both version checks go through timeout, and the install fails within their bound
pin_to "$TMP/stalled.tar.gz"
cp "$TMP/stalled" "$HOME/.local/bin/doctl"
started="$SECONDS"
run_install "$TMP/stalled.tar.gz"
elapsed=$((SECONDS - started))
if [[ "$(rc)" -ne 0 ]] && [[ "$elapsed" -lt 15 ]] && [[ "$(timeout_calls)" -eq 2 ]] &&
    grep -q "does not report doctl $VERSION after the install" "$TMP/out"; then
    pass "a version check that never returns is bounded and fails the install"
else
    fail "a stalled version check: rc=$(rc), ${elapsed}s, timeout calls=$(timeout_calls), $(cat "$TMP/out")"
fi

# The wiring: the installer verifies the call, so a failure fails the run and the next apply retries
# it; and zsh loads Oh My Zsh's doctl plugin, which writes the completion from `doctl completion zsh`.
if grep -q '^verify install_doctl$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_doctl"
else
    fail "the Linux installer does not verify install_doctl"
fi
if sed -n '/^plugins=(/,/^)/p' "$ZSHRC_TEMPLATE" | grep -qw doctl; then
    pass "zsh loads Oh My Zsh's doctl plugin"
else
    fail "zsh does not load Oh My Zsh's doctl plugin"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-doctl] all doctl install tests passed" >&2
fi
exit "$EXIT_CODE"
