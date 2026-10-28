#!/bin/bash
set -euo pipefail

# Tests the Atuin setup without the network, Docker or a real atuin. `install_atuin` is lifted out
# of the Linux installer with its pinned SHA-256 swapped for the digest of a fabricated release that
# a `curl` stub serves: the install, the skip, the replacement of an older version, a download the
# pin does not cover, a failed download and an archive without the binary. The templates are
# rendered for each kind of device: the server device syncs on loopback and every other one with
# the server's tailnet name, the client never checks for updates, and zsh starts Atuin after Oh My
# Zsh with nothing of zsh-histdb left, naming the device on Termux. Also checks the server's compose
# file against the client's pin and port, and the wiring of the removal of zsh-histdb. The login and
# the one-time history import that every apply runs are rendered and run against stubbed `atuin` and
# `op`, which record their arguments, environment and stdin, so the suite proves where the password
# and the key travel, and against a small zsh-histdb database built with sqlite3.

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
LOGIN_LINUX="$REPO_ROOT/.chezmoiscripts/run_after_linux-016-login-atuin.sh.tmpl"
IMPORT_LINUX="$REPO_ROOT/.chezmoiscripts/run_after_linux-017-import-atuin-history.sh.tmpl"
LOGIN_ANDROID="$REPO_ROOT/.chezmoiscripts/run_after_android-009-login-atuin.sh.tmpl"
IMPORT_ANDROID="$REPO_ROOT/.chezmoiscripts/run_after_android-010-import-atuin-history.sh.tmpl"
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
# record end to end before it leaves the client. SonarCloud's clear-text protocol rule (S5332)
# exempts only loopback, so the assertions on the other addresses carry NOSONAR for that reason.
server_config="$(render linux "$CONFIG_TEMPLATE" "{\"deviceName\":\"$SERVER\"}")"
client_config="$(render linux "$CONFIG_TEMPLATE")"
phone_config="$(render android "$CONFIG_TEMPLATE")"
override_config="$(render linux "$CONFIG_TEMPLATE" '{"atuin":{"devices":{"testdevice":{"serverHost":"100.64.0.9"}}}}')"

if grep -qx "sync_address = \"http://127.0.0.1:$PORT\"" <<<"$server_config"; then
    pass "the server device ($SERVER) syncs with its own server on loopback"
else
    fail "the server device's sync_address: $(grep sync_address <<<"$server_config")"
fi
if grep -qx "sync_address = \"http://$SERVER_HOST:$PORT\"" <<<"$client_config" && # NOSONAR
    grep -qx "sync_address = \"http://$SERVER_HOST:$PORT\"" <<<"$phone_config"; then # NOSONAR
    pass "every other device, Termux included, syncs with $SERVER_HOST:$PORT"
else
    fail "another device's sync_address: $(grep sync_address <<<"$client_config"), phone: $(grep sync_address <<<"$phone_config")"
fi
if grep -qx "sync_address = \"http://100.64.0.9:$PORT\"" <<<"$override_config"; then # NOSONAR
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
if grep -qF '~/.atuin/data/key' <<<"$client_config" && ! grep -qF '.local/share/atuin' <<<"$client_config"; then
    pass "the client's settings name the key where Atuin $VERSION keeps it, ~/.atuin/data/key"
else
    fail "the client's settings name another key path: $(grep -n 'key' <<<"$client_config" | head -3)"
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

# =================================================================================================
# The account on apply: the login, and the one-time import of zsh-histdb's history. The rendered
# scripts run against stubs that stand in for `atuin` and `op`: each records its arguments in
# $ATUIN_STATE, the atuin stub keeps a login in a file there and records the password it found in
# its environment and the key it read on stdin, and the op stub answers the account's two fields.
ACCT_BIN="$TMP/acct-bin"
mkdir -p "$ACCT_BIN"
cat >"$ACCT_BIN/atuin" <<'STUB'
#!/bin/bash
state="${ATUIN_STATE:?}"
printf '%s\n' "$*" >>"$state/argv"
case "$1" in
    status)
        if [[ -e "$state/logged-in" ]]; then
            echo "Username: rios0rios0"
            exit 0
        fi
        echo "Error: You are not logged in to a sync server - cannot show sync status" >&2
        exit 1
        ;;
    login)
        printf '%s' "${ATUIN_PASSWORD:-}" >"$state/login-password"
        cat >"$state/login-stdin"
        if [[ -n "${STUB_LOGIN_FAIL:-}" ]]; then
            echo "Error: invalid login details" >&2
            exit 1
        fi
        : >"$state/logged-in"
        echo "Logged in!"
        ;;
    uuid) echo "0190c1b2-7c3e-7000-8000-000000000001" ;;
    import)
        printf '%s' "${HISTDB_FILE:-}" >"$state/histdb-path"
        cp "${HISTDB_FILE:?}" "$state/imported.db"
        if [[ -n "${STUB_IMPORT_FAIL:-}" ]]; then
            echo "Error: the database is locked" >&2
            exit 1
        fi
        echo "Import complete!"
        ;;
    sync) printf '%s' "${ATUIN_SESSION:-}" >"$state/sync-session" ;;
    *) ;;
esac
STUB
cat >"$ACCT_BIN/op" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${ATUIN_STATE:?}/op-argv"
[[ -z "${STUB_OP_FAIL:-}" ]] || exit 1
case "$*" in
    */password) echo "fixture-password-placeholder" ;;
    */key) echo "fixture-key-placeholder words" ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$ACCT_BIN/atuin" "$ACCT_BIN/op"

# new_state: a fresh $ATUIN_STATE, and a fresh Atuin home for the import's marker
new_state() {
    ATUIN_STATE="$(mktemp -d -p "$TMP")"
    export ATUIN_STATE
    export ATUIN_HOME="$ATUIN_STATE/atuin-home"
}
# run_rendered <script> [VAR=value...]: runs a rendered script with the stubs first on PATH; its
# output lands in $ATUIN_STATE/out and its exit code in $ATUIN_STATE/rc.
run_rendered() {
    local script="$1" status=0
    shift
    env PATH="$ACCT_BIN:$PATH" "$@" bash "$script" >"$ATUIN_STATE/out" 2>&1 || status=$?
    echo "$status" >"$ATUIN_STATE/rc"
}
state_rc() { cat "$ATUIN_STATE/rc"; }
state_out() { cat "$ATUIN_STATE/out"; }
calls() {
    local pattern="$1" log="${2:-argv}"
    grep -c -- "$pattern" "$ATUIN_STATE/$log" 2>/dev/null || true
}
# What .github/ci/fixtures/mock-op.sh answers for every 1Password read, which Termux's render embeds.
MOCK_SECRET='stub-value'
# leaks: every place a secret must never reach -- the stubs' arguments and the script's output
leaks() { cat "$ATUIN_STATE/argv" "$ATUIN_STATE/op-argv" "$ATUIN_STATE/out" 2>/dev/null | grep -c "fixture-\\|$MOCK_SECRET" || true; }

render linux "$LOGIN_LINUX" >"$TMP/login-linux.sh"
render linux "$LOGIN_LINUX" "{\"deviceName\":\"$SERVER\"}" >"$TMP/login-server.sh"

if grep -qx "atuin_ensure_login 'rios0rios0' false" "$TMP/login-linux.sh" &&
    grep -qF "read --account 'my' 'op://Private/Atuin/'\"\$field\"" "$TMP/login-linux.sh"; then
    pass "the Linux login names the account and reads its 1Password item, Atuin in Private"
else
    fail "the Linux login's account: $(grep -n 'atuin_ensure_login\|op://' "$TMP/login-linux.sh")"
fi

# given a device that is logged in
new_state
: >"$ATUIN_STATE/logged-in"
# when the login runs
run_rendered "$TMP/login-linux.sh"
# then it asks Atuin and nothing else
if [[ "$(state_rc)" -eq 0 && ! -e "$ATUIN_STATE/op-argv" && "$(calls login)" -eq 0 ]]; then
    pass "a device already logged in reads nothing from 1Password and does not log in again"
else
    fail "a logged-in device: rc=$(state_rc), op: $(cat "$ATUIN_STATE/op-argv" 2>/dev/null), $(state_out)"
fi

# given a device with no session
new_state
# when the login runs
run_rendered "$TMP/login-linux.sh"
# then it reads both fields through op and hands the password over in the environment and the key
# on stdin, with neither on a command line or in its output
if [[ "$(state_rc)" -eq 0 ]] &&
    grep -qx "read --account my op://Private/Atuin/password" "$ATUIN_STATE/op-argv" &&
    grep -qx "read --account my op://Private/Atuin/key" "$ATUIN_STATE/op-argv" &&
    grep -qx "login -u rios0rios0" "$ATUIN_STATE/argv" &&
    [[ "$(cat "$ATUIN_STATE/login-password")" == "fixture-password-placeholder" ]] &&
    [[ "$(cat "$ATUIN_STATE/login-stdin")" == "fixture-key-placeholder words" ]] &&
    [[ "$(leaks)" -eq 0 ]] && grep -q "logged in to the sync server as rios0rios0" "$ATUIN_STATE/out"; then
    pass "a device with no session logs in with the password in its environment and the key on stdin"
else
    fail "the login: rc=$(state_rc), op: $(cat "$ATUIN_STATE/op-argv" 2>/dev/null), atuin: $(cat "$ATUIN_STATE/argv"), leaks: $(leaks), $(state_out)"
fi

# given 1Password that cannot be reached
new_state
# when the login runs
run_rendered "$TMP/login-linux.sh" STUB_OP_FAIL=1
# then it only warns, and the next apply tries again
if [[ "$(state_rc)" -eq 0 && "$(calls login)" -eq 0 ]] &&
    grep -q "WARN: could not read the Atuin password from 1Password" "$ATUIN_STATE/out"; then
    pass "a 1Password that cannot be reached is a warning, not a failed apply"
else
    fail "op failing: rc=$(state_rc), $(state_out)"
fi

# given a server that refuses the login
new_state
# when the login runs
run_rendered "$TMP/login-linux.sh" STUB_LOGIN_FAIL=1
# then it warns with Atuin's own reason, and still keeps the secrets out of its output
if [[ "$(state_rc)" -eq 0 && "$(leaks)" -eq 0 ]] &&
    grep -q "WARN: atuin login failed (Error: invalid login details)" "$ATUIN_STATE/out"; then
    pass "a refused login is a warning that gives Atuin's reason"
else
    fail "a refused login: rc=$(state_rc), leaks: $(leaks), $(state_out)"
fi

# given the server's own device, not logged in
new_state
# when the login runs
run_rendered "$TMP/login-server.sh"
# then it points at the registration, which stays by hand, and reads nothing from 1Password
if [[ "$(state_rc)" -eq 0 && ! -e "$ATUIN_STATE/op-argv" ]] &&
    grep -q "WARN: this device runs the sync server and is not logged in to it; register the account by hand" "$ATUIN_STATE/out"; then
    pass "the server's own device is only pointed at the registration by hand"
else
    fail "the server device: rc=$(state_rc), op: $(cat "$ATUIN_STATE/op-argv" 2>/dev/null), $(state_out)"
fi

# given a machine where atuin is not installed yet
new_state
if [[ -e /usr/bin/atuin || -e /bin/atuin ]]; then
    pass "a machine without atuin: skipped, this runner has its own atuin in /usr/bin"
else
    # when the login runs with nothing but the system's directories on PATH
    status=0
    env PATH=/usr/bin:/bin bash "$TMP/login-linux.sh" >"$ATUIN_STATE/out" 2>&1 || status=$?
    # then it does nothing, quietly
    if [[ "$status" -eq 0 && ! -s "$ATUIN_STATE/out" ]]; then
        pass "a machine without atuin skips the login quietly"
    else
        fail "a machine without atuin: rc=$status, $(state_out)"
    fi
fi

# On Termux no op is signed in for a script to call, so the secrets are rendered into the script, and
# only by a render that finds no session.
new_state
PATH="$ACCT_BIN:$PATH" render android "$LOGIN_ANDROID" >"$TMP/login-android-out.sh" 2>"$TMP/render.err" ||
    fail "Termux's login does not render: $(cat "$TMP/render.err")"
: >"$ATUIN_STATE/logged-in"
PATH="$ACCT_BIN:$PATH" render android "$LOGIN_ANDROID" >"$TMP/login-android-in.sh" 2>"$TMP/render.err" ||
    fail "Termux's login does not render with a session: $(cat "$TMP/render.err")"
if grep -qx "$MOCK_SECRET" "$TMP/login-android-out.sh" && grep -qx 'END_OF_ATUIN_KEY' "$TMP/login-android-out.sh" &&
    ! grep -q "$MOCK_SECRET\\|END_OF_ATUIN" "$TMP/login-android-in.sh"; then
    pass "Termux's login renders the secrets only when the render finds no session"
else
    fail "Termux's render: $(grep -c "$MOCK_SECRET" "$TMP/login-android-out.sh") values without a session, $(grep -c "$MOCK_SECRET" "$TMP/login-android-in.sh") with one"
fi
new_state
run_rendered "$TMP/login-android-out.sh"
if [[ "$(state_rc)" -eq 0 && ! -e "$ATUIN_STATE/op-argv" ]] && grep -qx "login -u rios0rios0" "$ATUIN_STATE/argv" &&
    [[ "$(cat "$ATUIN_STATE/login-password")" == "$MOCK_SECRET" && "$(cat "$ATUIN_STATE/login-stdin")" == "$MOCK_SECRET" ]] &&
    [[ "$(leaks)" -eq 0 ]]; then
    pass "Termux logs in with the rendered secrets, the password in the environment and the key on stdin"
else
    fail "Termux's login: rc=$(state_rc), atuin: $(cat "$ATUIN_STATE/argv"), leaks: $(leaks), $(state_out)"
fi

# The import: a zsh-histdb database with commands recorded under four hosts -- the laptop, the
# desktop under both its names, and a phone's `localhost` -- in the schema zsh-histdb creates.
if ! command -v sqlite3 >/dev/null 2>&1; then
    fail "sqlite3 is not installed; the history import cannot be tested"
else
    HISTDB="$HOME/.histdb/zsh-history.db"
    mkdir -p "$(dirname "$HISTDB")"
    sqlite3 "$HISTDB" <<'SQL'
CREATE TABLE commands (id INTEGER PRIMARY KEY AUTOINCREMENT, argv TEXT, UNIQUE(argv) ON CONFLICT IGNORE);
CREATE TABLE places (id INTEGER PRIMARY KEY AUTOINCREMENT, host TEXT, dir TEXT, UNIQUE(host, dir) ON CONFLICT IGNORE);
CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, session INT, command_id INT REFERENCES commands (id),
    place_id INT REFERENCES places (id), exit_status INT, start_time INT, duration INT);
INSERT INTO commands (argv) VALUES ('ls'), ('git status'), ('make test');
INSERT INTO places (host, dir) VALUES ('alien-a51', '/home/u'), ('rios0rios0-z790', '/home/u'),
    ('mxhero-z790', '/home/u'), ('localhost', '/data/home');
INSERT INTO history (session, command_id, place_id, exit_status, start_time, duration) VALUES
    (1, 1, 1, 0, 1793000000, 1), (1, 2, 1, 0, 1793000001, 1),
    (2, 1, 2, 0, 1700000000, 1), (2, 2, 2, 0, 1700000001, 1), (2, 3, 2, 0, 1700000002, 1),
    (3, 3, 3, 0, 1750000000, 1),
    (4, 1, 4, 0, 1760000000, 1);
SQL
    HISTORY_COUNT='SELECT COUNT(*) FROM history;'
    # imported <query>: a query against the copy the atuin stub received
    imported() {
        local query="$1"
        sqlite3 "$ATUIN_STATE/imported.db" "$query"
    }
    marker() { echo "$ATUIN_HOME/data/.dotfiles-histdb-imported"; }

    render linux "$IMPORT_LINUX" '{"chezmoi":{"hostname":"alien-a51"}}' >"$TMP/import-laptop.sh"
    render linux "$IMPORT_LINUX" '{"chezmoi":{"hostname":"mxhero-z790"},"deviceName":"mxhero-z790"}' >"$TMP/import-desktop.sh"
    render android "$IMPORT_ANDROID" >"$TMP/import-phone.sh"

    # given the laptop, not logged in yet
    new_state
    # when the import runs
    run_rendered "$TMP/import-laptop.sh"
    # then Atuin gets a copy with the laptop's own two commands, the database itself is untouched,
    # the copy is gone, the marker is written, and nothing syncs before the login
    if [[ "$(state_rc)" -eq 0 && "$(imported "$HISTORY_COUNT")" -eq 2 ]] &&
        [[ "$(imported 'SELECT DISTINCT p.host FROM history h JOIN places p ON p.id = h.place_id;')" == "alien-a51" ]] &&
        [[ "$(sqlite3 "$HISTDB" "$HISTORY_COUNT")" -eq 7 ]] &&
        [[ ! -e "$(cat "$ATUIN_STATE/histdb-path")" && -e "$(marker)" && "$(calls sync)" -eq 0 ]] &&
        grep -q "imported 2 commands from zsh-histdb, recorded under alien-a51" "$ATUIN_STATE/out"; then
        pass "the laptop imports its own commands from a private copy, and writes the marker"
    else
        fail "the laptop's import: rc=$(state_rc), $(state_out)"
    fi

    # when it runs again
    run_rendered "$TMP/import-laptop.sh"
    # then the marker stops it: atuin import does not deduplicate
    if [[ "$(state_rc)" -eq 0 && "$(calls import)" -eq 1 ]]; then
        pass "the marker keeps a second apply from importing the same commands again"
    else
        fail "a second import ran: $(calls import) imports"
    fi

    # given the desktop, logged in, whose history carries both of its names
    new_state
    : >"$ATUIN_STATE/logged-in"
    # when the import runs
    run_rendered "$TMP/import-desktop.sh"
    # then both names are imported, and the sync that uploads them gets a session of its own
    if [[ "$(state_rc)" -eq 0 && "$(imported "$HISTORY_COUNT")" -eq 4 ]] &&
        [[ -n "$(cat "$ATUIN_STATE/sync-session" 2>/dev/null)" ]] && grep -q "synced them with the server" "$ATUIN_STATE/out"; then
        pass "the desktop imports both of its names, and syncs with an ATUIN_SESSION of its own"
    else
        fail "the desktop's import: rc=$(state_rc), session: $(cat "$ATUIN_STATE/sync-session" 2>/dev/null), $(state_out)"
    fi

    # given a phone, whose commands zsh-histdb recorded under localhost
    new_state
    # when the import runs
    run_rendered "$TMP/import-phone.sh"
    # then they are imported under the device's name, as the shell now records them
    if [[ "$(state_rc)" -eq 0 && "$(imported "$HISTORY_COUNT")" -eq 1 ]] &&
        [[ "$(imported 'SELECT DISTINCT p.host FROM history h JOIN places p ON p.id = h.place_id;')" == "testdevice" ]]; then
        pass "Termux imports the commands recorded under localhost, named after the device"
    else
        fail "the phone's import: rc=$(state_rc), $(state_out)"
    fi

    # given an import Atuin refuses
    new_state
    # when the import runs
    run_rendered "$TMP/import-laptop.sh" STUB_IMPORT_FAIL=1
    # then it warns and writes no marker, so the next apply tries again
    if [[ "$(state_rc)" -eq 0 && ! -e "$(marker)" ]] &&
        grep -q "WARN: atuin import failed (Error: the database is locked)" "$ATUIN_STATE/out"; then
        pass "a failed import is a warning that leaves no marker"
    else
        fail "a failed import: rc=$(state_rc), marker: $(ls "$(marker)" 2>&1), $(state_out)"
    fi

    # given a device that never ran zsh-histdb
    new_state
    # when the import runs
    run_rendered "$TMP/import-laptop.sh" HOME="$ATUIN_STATE/empty-home"
    # then there is nothing to import, and the marker says so
    if [[ "$(state_rc)" -eq 0 && "$(calls import)" -eq 0 ]] && grep -q '^nothing to import' "$(marker)"; then
        pass "a device without zsh-histdb writes the marker and imports nothing"
    else
        fail "no zsh-histdb: rc=$(state_rc), $(state_out)"
    fi
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-atuin] all Atuin tests passed" >&2
fi
exit "$EXIT_CODE"
