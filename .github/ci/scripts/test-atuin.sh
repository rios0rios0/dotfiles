#!/bin/bash
set -euo pipefail

# Tests the Atuin setup without the network, Docker or a real atuin. `install_atuin` is lifted out
# of the Linux installer with its pinned SHA-256 swapped for the digest of a fabricated release that
# a `curl` stub serves: the install, the skip, the replacement of an older version, a download the
# pin does not cover, a failed download and an archive without the binary. The templates are
# rendered for each kind of device: the server device syncs on loopback and every other one with
# the server's tailnet name, the client never checks for updates, and zsh starts Atuin after Oh My
# Zsh with nothing of zsh-histdb left, naming the device on Termux. Also checks the server's compose
# file against the client's pin and port, and the wiring of the removal of zsh-histdb.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
LINUX_REMOVAL="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-006-remove-dependencies.sh.tmpl"
ANDROID_REMOVAL="$REPO_ROOT/.chezmoiscripts/run_onchange_after_android-004-remove-dependencies.sh.tmpl"
CONFIG_TEMPLATE="$REPO_ROOT/dot_config/atuin/config.toml.tmpl"
ZSHRC_TEMPLATE="$REPO_ROOT/dot_zshrc.tmpl"
COMPOSE="$REPO_ROOT/local-services/atuin/compose.yaml"
DATA="$REPO_ROOT/.chezmoidata/atuin.yaml"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-atuin] testing the Atuin setup..." >&2

pass() { echo "[test-atuin] PASS: $1" >&2; }
fail() { echo "[test-atuin] FAIL: $1" >&2; EXIT_CODE=1; }

# =================================================================================================
# install_atuin
FUNCTION="$(sed -n '/^install_atuin() {$/,/^}$/p' "$LINUX_INSTALLER")"
VERSION="$(sed -n 's/^    local version="\(.*\)"$/\1/p' <<<"$FUNCTION")"
if [[ -z "$FUNCTION" || -z "$VERSION" ]]; then
    fail "install_atuin or its pinned version was not found in the Linux installer"
    exit 1
fi
case "$(uname -m)" in
    x86_64) TRIPLE="x86_64-unknown-linux-gnu" ;;
    aarch64) TRIPLE="aarch64-unknown-linux-gnu" ;;
    *) fail "no Atuin build is pinned for this runner's $(uname -m)"; exit 1 ;;
esac

# fake_release <version it reports> <archive>: a release tarball laid out as upstream's, with an
# `atuin` that answers `-V` the way the real one does. Without a version it holds no binary.
fake_release() {
    local version="$1" archive="$2" dir
    dir="$(mktemp -d -p "$TMP")"
    mkdir -p "$dir/atuin-$TRIPLE"
    echo "release notes" >"$dir/atuin-$TRIPLE/README.md"
    if [[ -n "$version" ]]; then
        printf '#!/bin/bash\n[[ "$1" == -V ]] && echo "atuin %s"\n' "$version" >"$dir/atuin-$TRIPLE/atuin"
        chmod +x "$dir/atuin-$TRIPLE/atuin"
    fi
    tar -czf "$archive" -C "$dir" "atuin-$TRIPLE"
}
fake_release "$VERSION" "$TMP/release.tar.gz"
fake_release "$VERSION-tampered" "$TMP/tampered.tar.gz"
fake_release "" "$TMP/empty.tar.gz"
printf '#!/bin/bash\n[[ "$1" == -V ]] && echo "atuin 18.0.0"\n' >"$TMP/older"
chmod +x "$TMP/older"

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
chmod +x "$STUB/curl"

CURL_CALLS="$TMP/curl-calls"
export CURL_CALLS

# run_install <body>: runs install_atuin with the stub ahead of PATH, serving <body>.
run_install() {
    local rc=0
    : >"$CURL_CALLS"
    (export CURL_BODY="$1"; PATH="$STUB:$PATH"; install_atuin) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
curl_calls() { wc -l <"$CURL_CALLS"; }
installed_version() { "$HOME/.local/bin/atuin" -V 2>/dev/null; }

# given nothing in ~/.local/bin
# when install_atuin runs
# then the pinned release for this architecture is downloaded, verified and installed
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] &&
    grep -qF "atuinsh/atuin/releases/download/v$VERSION/atuin-$TRIPLE.tar.gz" "$CURL_CALLS" &&
    [[ "$(installed_version)" == "atuin $VERSION" ]]; then
    pass "installs the pinned release $VERSION"
else
    fail "install of $VERSION: rc=$(rc), calls=$(cat "$CURL_CALLS"), $(cat "$TMP/out")"
fi

# given the pinned version in ~/.local/bin
# when install_atuin runs again
# then nothing is downloaded and the skip says why
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 0 ]] && grep -q "already installed, skipping" "$TMP/out"; then
    pass "the pinned version is skipped"
else
    fail "the pinned version was not skipped: rc=$(rc), $(cat "$TMP/out")"
fi

# given an older atuin in ~/.local/bin, as a bumped pin leaves it
# when install_atuin runs
# then it is replaced
cp "$TMP/older" "$HOME/.local/bin/atuin"
run_install "$TMP/release.tar.gz"
if [[ "$(rc)" -eq 0 ]] && [[ "$(curl_calls)" -eq 1 ]] && [[ "$(installed_version)" == "atuin $VERSION" ]]; then
    pass "an older atuin is replaced by the pinned one"
else
    fail "an older atuin was not replaced: rc=$(rc), $(installed_version)"
fi

# given a download whose bytes the pin does not cover
# when install_atuin runs on a machine without atuin
# then it fails and installs nothing
rm -f "$HOME/.local/bin/atuin"
run_install "$TMP/tampered.tar.gz"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/atuin" ]] && grep -q "does not match its pinned SHA-256" "$TMP/out"; then
    pass "a download that does not match the pin fails and installs nothing"
else
    fail "a mismatched download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a failed download
# when install_atuin runs
# then it fails and says what failed
export CURL_FAIL=1
run_install "$TMP/release.tar.gz"
unset CURL_FAIL
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/atuin" ]] && grep -q "failed to download Atuin" "$TMP/out"; then
    pass "a failed download fails the install"
else
    fail "a failed download: rc=$(rc), $(cat "$TMP/out")"
fi

# given a verified archive that holds no binary
# when install_atuin runs
# then it fails and installs nothing
pin_to "$TMP/empty.tar.gz"
run_install "$TMP/empty.tar.gz"
if [[ "$(rc)" -ne 0 ]] && [[ ! -e "$HOME/.local/bin/atuin" ]] && grep -q "archive holds no atuin-$TRIPLE/atuin" "$TMP/out"; then
    pass "an archive without the binary fails the install"
else
    fail "an archive without the binary: rc=$(rc), $(cat "$TMP/out")"
fi

# The wiring: the Linux installer verifies the call, so a failure fails the run and the next apply
# retries it, and Termux installs its own package of the same release.
if grep -q '^verify install_atuin$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_atuin"
else
    fail "the Linux installer does not verify install_atuin"
fi
if sed -n '/^utilities=(/,/^)/p' "$ANDROID_INSTALLER" | grep -qE '^\s*"atuin"'; then
    pass "the Android installer installs Termux's atuin package"
else
    fail "the Android installer does not install Termux's atuin package"
fi

# =================================================================================================
# The client's config and zsh, rendered per device
if ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not installed; the templates cannot be rendered"
    exit 1
fi
chmod +x "$CI_DIR/fixtures/mock-op.sh"
cat >"$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

# render <os> <template> [override data]: the OS is set for every render, so the host running the
# suite decides nothing; chezmoi merges the override into the data key by key.
render() {
    local os="$1" template="$2" extra="${3:-}"
    local data="{\"chezmoi\":{\"os\":\"$os\"}}"
    [[ -z "$extra" ]] || data="$(jq -c --argjson extra "$extra" '. * $extra' <<<"$data")"
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "$data" <"$template"
}

data() {
    local key="$1"
    chezmoi execute-template --config "$TMP/chezmoi.yaml" "{{ .atuin.$key }}"
}
SERVER="$(data serverDevice)"
SERVER_HOST="$(data serverHost)"
PORT="$(data port)"
if [[ -z "$SERVER" || -z "$SERVER_HOST" || ! "$PORT" =~ ^[0-9]+$ ]]; then
    fail "$DATA does not declare serverDevice, serverHost and port"
    exit 1
fi

# Every sync address is plain HTTP by design: the server listens on loopback, every other device
# reaches it through the tailnet, whose WireGuard tunnel encrypts the hop, and Atuin encrypts each
# record end to end before it leaves the client.
SCHEME="http"

server_config="$(render linux "$CONFIG_TEMPLATE" "{\"deviceName\":\"$SERVER\"}")"
client_config="$(render linux "$CONFIG_TEMPLATE")"
phone_config="$(render android "$CONFIG_TEMPLATE")"
override_config="$(render linux "$CONFIG_TEMPLATE" '{"atuin":{"devices":{"testdevice":{"serverHost":"100.64.0.9"}}}}')"

if grep -qx "sync_address = \"$SCHEME://127.0.0.1:$PORT\"" <<<"$server_config"; then
    pass "the server device ($SERVER) syncs with its own server on loopback"
else
    fail "the server device's sync_address: $(grep sync_address <<<"$server_config")"
fi
if grep -qx "sync_address = \"$SCHEME://$SERVER_HOST:$PORT\"" <<<"$client_config" &&
    grep -qx "sync_address = \"$SCHEME://$SERVER_HOST:$PORT\"" <<<"$phone_config"; then
    pass "every other device, Termux included, syncs with $SERVER_HOST:$PORT"
else
    fail "another device's sync_address: $(grep sync_address <<<"$client_config"), phone: $(grep sync_address <<<"$phone_config")"
fi
if grep -qx "sync_address = \"$SCHEME://100.64.0.9:$PORT\"" <<<"$override_config"; then
    pass "a device override names the server by its tailnet address"
else
    fail "a device override was not applied: $(grep sync_address <<<"$override_config")"
fi
if grep -qx 'update_check = false' <<<"$client_config" && grep -qx 'secrets_filter = true' <<<"$client_config" &&
    grep -qx 'auto_sync = true' <<<"$client_config"; then
    pass "the client syncs on its own, never checks api.atuin.sh for updates, and filters secrets"
else
    fail "the client's settings: $client_config"
fi

linux_zshrc="$(render linux "$ZSHRC_TEMPLATE")"
android_zshrc="$(render android "$ZSHRC_TEMPLATE")"
init_line="$(grep -n -F 'eval "$(atuin init zsh --disable-ai)"' <<<"$linux_zshrc" | cut -d: -f1 | head -1)"
omz_line="$(grep -n -F 'source $ZSH/oh-my-zsh.sh' <<<"$linux_zshrc" | cut -d: -f1 | head -1)"
if [[ -n "$init_line" && -n "$omz_line" && "$init_line" -gt "$omz_line" ]] &&
    grep -q 'command -v atuin' <<<"$linux_zshrc"; then
    pass "zsh starts Atuin after Oh My Zsh, whose own Ctrl-R and up-arrow bindings would otherwise win"
else
    fail "zsh does not start Atuin after Oh My Zsh (init at line ${init_line:-none}, Oh My Zsh at ${omz_line:-none})"
fi
if grep -qi 'histdb' <<<"$linux_zshrc" || grep -qi 'histdb' <<<"$android_zshrc"; then
    fail "the rendered .zshrc still mentions zsh-histdb: $(grep -i histdb <<<"$linux_zshrc$android_zshrc" | head -3)"
else
    pass "nothing of zsh-histdb is left in .zshrc"
fi
if grep -qx '    export ATUIN_HOST_NAME="testdevice"' <<<"$android_zshrc" &&
    ! grep -q 'ATUIN_HOST_NAME' <<<"$linux_zshrc"; then
    pass "Termux records the device's name rather than localhost, and Linux its hostname"
else
    fail "ATUIN_HOST_NAME: android $(grep ATUIN_HOST_NAME <<<"$android_zshrc"), linux $(grep ATUIN_HOST_NAME <<<"$linux_zshrc")"
fi

# =================================================================================================
# The server: the same release as the client, on the port the clients use, on loopback alone. The
# compose file is read line by line, as it is written, so the suite needs no YAML tool.
image="$(sed -n "s/^    image: '\(.*\)'$/\1/p" "$COMPOSE")"
if [[ "$image" =~ ^ghcr\.io/atuinsh/atuin:${VERSION//./\\.}@sha256:[0-9a-f]{64}$ ]]; then
    pass "the server image is Atuin $VERSION, pinned by digest"
else
    fail "the server image is not $VERSION pinned by digest: $image"
fi
published="$(sed -n '/^    ports:$/,/^    [a-z]/p' "$COMPOSE" | grep -E "^      - " || true)"
if grep -qx "      ATUIN_PORT: '$PORT'" "$COMPOSE" &&
    [[ "$published" == "      - '127.0.0.1:$PORT:$PORT'" ]]; then
    pass "the server listens on port $PORT, published on the host's loopback alone"
else
    fail "the server's port: ATUIN_PORT $(grep ATUIN_PORT "$COMPOSE"), published: $published"
fi
if grep -qxF '      ATUIN_OPEN_REGISTRATION: "${ATUIN_OPEN_REGISTRATION:-false}"' "$COMPOSE" &&
    grep -qE "^      ATUIN_DB_URI: 'sqlite:///config/[a-z.]+'$" "$COMPOSE"; then
    pass "registration is closed unless opened for it, and the database is SQLite in the volume"
else
    fail "registration or the database: $(grep -E 'OPEN_REGISTRATION|DB_URI' "$COMPOSE")"
fi

# =================================================================================================
# zsh-histdb's removal: no source files, no watcher or extractor entry, and tombstones for the
# plugin where it was loaded
if [[ ! -e "$REPO_ROOT/dot_histdb" ]]; then
    pass "the repository no longer carries ~/.histdb"
else
    fail "dot_histdb is still in the source"
fi
if sed -n '/^WATCH_DIRS=($/,/^)$/p' "$REPO_ROOT/dot_scripts/executable_linux-toolbox-watch-compress-folders.sh" |
    grep -q '\.histdb' ||
    grep -q '^WATCH_DIRS=.*\.histdb' "$REPO_ROOT/.chezmoiscripts/run_once_after_linux-001-extract-compressed-folders.sh"; then
    fail "the folder watcher or the extractor still lists ~/.histdb"
else
    pass "neither the folder watcher nor the extractor lists ~/.histdb"
fi
for removal in "$LINUX_REMOVAL" "$ANDROID_REMOVAL"; do
    if grep -qF '"path:$HOME/.local/share/zinit/plugins/larkery---zsh-histdb"' "$removal" &&
        grep -qF '"path:$HOME/.oh-my-zsh/custom/plugins/zsh-histdb"' "$removal"; then
        pass "$(basename "$removal") tombstones the zsh-histdb plugin"
    else
        fail "$(basename "$removal") does not tombstone the zsh-histdb plugin"
    fi
done

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-atuin] all Atuin tests passed" >&2
fi
exit "$EXIT_CODE"
