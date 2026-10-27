#!/bin/bash
set -euo pipefail

# Tests run_after_linux-015-start-omniroute.sh.tmpl, which keeps the OmniRoute stack running across
# applies and never creates its database. It is rendered for WSL and run against a stub docker in
# each state it can find -- Docker down, no .env, a container running, stopped or crash-looping, no
# data volume, a volume without containers -- with cmd.exe and wslpath standing in for Windows (the
# personal OneDrive, Docker Desktop's settings); the other platforms must render nothing.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-omniroute-stack] testing the OmniRoute start script..." >&2

pass() { echo "[test-omniroute-stack] PASS: $1" >&2; }
fail() { echo "[test-omniroute-stack] FAIL: $1" >&2; EXIT_CODE=1; }

for tool in chezmoi jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-omniroute-stack] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

TEMPLATE="$REPO_ROOT/.chezmoiscripts/run_after_linux-015-start-omniroute.sh.tmpl"
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF

# render <os> <kernel release>
render() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"chezmoi\":{\"os\":\"$1\",\"kernel\":{\"osrelease\":\"$2\",\"ostype\":\"Linux\",\"version\":\"#1 SMP\"}}}" \
        < "$TEMPLATE"
}

SCRIPT="$TMP/start-omniroute.sh"
render linux 6.6.87.2-microsoft-standard-WSL2 > "$SCRIPT"
if [[ "$(head -n 1 "$SCRIPT")" == "#!/bin/bash" ]] && bash -n "$SCRIPT"; then
    pass "it renders to a bash script on WSL"
else
    fail "it does not render to a bash script on WSL"
fi
for platform in "linux 6.8.0-45-generic" "windows 10.0.26100" "android 6.1.0-android14"; do
    # shellcheck disable=SC2086 # the OS and the kernel are two arguments
    if [[ -z "$(render $platform | tr -d '[:space:]')" ]]; then
        pass "it renders to nothing on ${platform%% *} (${platform#* })"
    else
        fail "it renders something on ${platform%% *} (${platform#* })"
    fi
done
if grep -qx "default_compose_dir='$REPO_ROOT/local-services/omniroute'" "$SCRIPT"; then
    pass "the stack runs from the chezmoi source's local-services/omniroute"
else
    fail "the compose directory is not the source's local-services/omniroute"
fi

# --- Stubs ----------------------------------------------------------------------

STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/docker" <<'STUB_DOCKER'
#!/bin/bash
# Records every call in $FAKE/calls.log and answers from the FAKE_* state.
set -uo pipefail
echo "docker $*" >> "$FAKE/calls.log"
case "$*" in
    info) [[ "${FAKE_DOCKER_DOWN:-}" != true ]] ;;
    "compose config --quiet") [[ "${FAKE_CONFIG_FAIL:-}" != true ]] ;;
    "compose config --images") printf 'docker.io/library/redis:8.6.5-alpine\nghcr.io/rios0rios0/omniroute@sha256:2222\n' ;;
    "inspect dotfiles-omniroute-1")
        if [[ -z "${FAKE_STATE:-}" ]]; then
            echo '[]'
            exit 1
        fi
        printf '[{"State":{"Status":"%s"},"Config":{"Image":"%s"}}]\n' "$FAKE_STATE" "${FAKE_IMAGE:-ghcr.io/rios0rios0/omniroute@sha256:2222}"
        ;;
    "volume inspect dotfiles_omniroute-data") [[ "${FAKE_VOLUME:-}" == true ]] ;;
    "compose pull --quiet") [[ "${FAKE_PULL_FAIL:-}" != true ]] ;;
    "compose up -d --no-recreate --wait --wait-timeout 300") [[ "${FAKE_UP_FAIL:-}" != true ]] ;;
    *) echo "stub docker: unhandled: $*" >&2; exit 2 ;;
esac
STUB_DOCKER
cat > "$STUB/cmd.exe" <<'STUB_CMD'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" =~ ^echo\ %([A-Za-z]+)%$ ]]; then
        var="FAKE_WIN_${BASH_REMATCH[1]}"
        printf '%s\r\n' "${!var:-%${BASH_REMATCH[1]}%}"
        exit 0
    fi
done
exit 1
STUB_CMD
cat > "$STUB/wslpath" <<'STUB_WSLPATH'
#!/bin/bash
path="${@: -1}"
path="${path//\\//}"
printf '%s\n' "${FAKE_C:?}/${path#C:/}"
STUB_WSLPATH
chmod +x "$STUB"/*

export PATH="$STUB:$PATH"
export FAKE="$TMP/fake" FAKE_C="$TMP/c"
export HOME="$TMP/home"
export OMNIROUTE_COMPOSE_DIR="$TMP/compose"
export OMNIROUTE_BACKUP_DIR="$TMP/backups"

# A clean slate: a compose directory with its .env, no state, empty logs.
reset() {
    rm -rf "$FAKE" "$OMNIROUTE_COMPOSE_DIR" "$OMNIROUTE_BACKUP_DIR" "$FAKE_C"
    mkdir -p "$FAKE" "$OMNIROUTE_COMPOSE_DIR" "$HOME"
    : > "$FAKE/calls.log"
    printf 'name: dotfiles\n' > "$OMNIROUTE_COMPOSE_DIR/compose.yaml"
    printf 'STORAGE_ENCRYPTION_KEY=x\n' > "$OMNIROUTE_COMPOSE_DIR/.env"
    unset FAKE_DOCKER_DOWN FAKE_CONFIG_FAIL FAKE_STATE FAKE_IMAGE FAKE_VOLUME FAKE_PULL_FAIL FAKE_UP_FAIL \
        FAKE_WIN_OneDriveConsumer FAKE_WIN_APPDATA OMNIROUTE_DOCKER_SETTINGS
}

# start <case>: runs the script, stdout and stderr in $TMP/<case>.log; returns its exit code.
start() {
    bash "$SCRIPT" > "$TMP/$1.log" 2>&1
}

called() { grep -qE "$1" "$FAKE/calls.log"; }
# Nothing that makes a database: the volume, the containers, or anything that removes one.
creates_nothing() { ! called 'volume create|compose (create|up|down|run)|docker run'; }

# --- Docker -------------------------------------------------------------------------

reset
export FAKE_DOCKER_DOWN=true
printf '{"AutoStart": false}\n' > "$TMP/settings-off.json"
export OMNIROUTE_DOCKER_SETTINGS="$TMP/settings-off.json"
if start down && grep -q "WARN: Docker is not reachable" "$TMP/down.log" && grep -q "Start Docker Desktop when you sign in" "$TMP/down.log" &&
    ! called compose; then
    pass "Docker unreachable: a warning, the sign-in hint while AutoStart is off, exit 0"
else
    fail "Docker unreachable: $(cat "$TMP/down.log")"
fi
reset
export FAKE_DOCKER_DOWN=true
mkdir -p "$FAKE_C/Users/Test/AppData/Roaming/Docker"
printf '{"AutoStart": true}\n' > "$FAKE_C/Users/Test/AppData/Roaming/Docker/settings-store.json"
export FAKE_WIN_APPDATA='C:\Users\Test\AppData\Roaming'
if start down-autostart && ! grep -q "Start Docker Desktop when you sign in" "$TMP/down-autostart.log"; then
    pass "with AutoStart on, found through %APPDATA%, there is no sign-in hint"
else
    fail "AutoStart on: $(cat "$TMP/down-autostart.log")"
fi
printf '{"AutoStart": false}\n' > "$FAKE_C/Users/Test/AppData/Roaming/Docker/settings-store.json"
if start down-appdata && grep -q "Start Docker Desktop when you sign in" "$TMP/down-appdata.log"; then
    pass "Docker Desktop's settings are found through %APPDATA%"
else
    fail "%APPDATA%: $(cat "$TMP/down-appdata.log")"
fi

# --- The checkout ---------------------------------------------------------------------

reset
rm "$OMNIROUTE_COMPOSE_DIR/.env"
if start noenv && grep -q "omniroute-restore --env-only" "$TMP/noenv.log" && grep -q "never generate new values" "$TMP/noenv.log" &&
    ! called compose; then
    pass "no .env: a warning pointing at omniroute-restore --env-only, exit 0"
else
    fail "no .env: $(cat "$TMP/noenv.log")"
fi
reset
printf 'OMNIROUTE_CA_BUNDLE=%s/missing.pem\n' "$HOME" >> "$OMNIROUTE_COMPOSE_DIR/.env"
if start noca && grep -q "missing.pem, which does not exist" "$TMP/noca.log" && creates_nothing; then
    pass "a CA bundle .env names but this machine lacks: a warning, exit 0"
else
    fail "missing CA bundle: $(cat "$TMP/noca.log")"
fi
reset
rm "$OMNIROUTE_COMPOSE_DIR/compose.yaml"
if start nocompose && grep -q "holds no compose.yaml" "$TMP/nocompose.log"; then
    pass "no compose.yaml: a warning, exit 0"
else
    fail "no compose.yaml: $(cat "$TMP/nocompose.log")"
fi
reset
export FAKE_CONFIG_FAIL=true
if start badconfig; then
    fail "a Compose project that does not load exits 0"
else
    if grep -q "ERROR: the Compose project in .* does not load" "$TMP/badconfig.log"; then
        pass "a Compose project that does not load fails the apply"
    else
        fail "a broken Compose project: $(cat "$TMP/badconfig.log")"
    fi
fi

# --- An existing container is left alone ------------------------------------------

reset
export FAKE_STATE=running
if start running && [[ ! -s "$TMP/running.log" ]] && creates_nothing && ! called 'compose pull'; then
    pass "a running gateway on the pinned image: silence, nothing touched"
else
    fail "running: $(cat "$TMP/running.log")"
fi
reset
export FAKE_STATE=running FAKE_IMAGE=ghcr.io/rios0rios0/omniroute@sha256:1111
if start oldimage && grep -q "runs ghcr.io/rios0rios0/omniroute@sha256:1111, but compose.yaml pins ghcr.io/rios0rios0/omniroute@sha256:2222" "$TMP/oldimage.log" &&
    creates_nothing; then
    pass "a gateway on another image: a warning, and it is never recreated"
else
    fail "another image: $(cat "$TMP/oldimage.log")"
fi
reset
export FAKE_STATE=exited
if start exited && grep -q "container is exited, and stays so" "$TMP/exited.log" && creates_nothing && ! called 'compose start'; then
    pass "a stopped gateway stays stopped"
else
    fail "exited: $(cat "$TMP/exited.log")"
fi
reset
export FAKE_STATE=restarting
if start restarting && grep -q "keeps restarting" "$TMP/restarting.log" && creates_nothing; then
    pass "a crash-looping gateway: a warning"
else
    fail "restarting: $(cat "$TMP/restarting.log")"
fi

# --- No data volume: never created here -------------------------------------------

reset
mkdir -p "$OMNIROUTE_BACKUP_DIR"
touch "$OMNIROUTE_BACKUP_DIR/omniroute-20261001T033000Z.tar.age" "$OMNIROUTE_BACKUP_DIR/omniroute-20261002T033000Z.tar.age"
if start novolume && grep -q "'omniroute-restore' brings back the newest archive, $OMNIROUTE_BACKUP_DIR/omniroute-20261002T033000Z.tar.age" "$TMP/novolume.log" &&
    creates_nothing; then
    pass "no data volume: it names the newest archive and creates nothing"
else
    fail "no data volume: $(cat "$TMP/novolume.log")"
fi
reset
export FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive'
mkdir -p "$FAKE_C/Users/Test/OneDrive/Backup/omniroute/mxhero-z790"
touch "$FAKE_C/Users/Test/OneDrive/Backup/omniroute/mxhero-z790/omniroute-20261003T033000Z.tar.age"
if start otherdevice && grep -q "the mirror holds other devices' (mxhero-z790): 'omniroute-restore --device <name>'" "$TMP/otherdevice.log" &&
    creates_nothing; then
    pass "no archive of this device: it names the devices the mirror holds"
else
    fail "other devices: $(cat "$TMP/otherdevice.log")"
fi
mkdir -p "$FAKE_C/Users/Test/OneDrive/Backup/omniroute/test-device"
touch "$FAKE_C/Users/Test/OneDrive/Backup/omniroute/test-device/omniroute-20261004T033000Z.tar.age"
if start mirrored && grep -q "test-device/omniroute-20261004T033000Z.tar.age" "$TMP/mirrored.log" && creates_nothing; then
    pass "this device's archives in the personal OneDrive count too"
else
    fail "mirrored archives: $(cat "$TMP/mirrored.log")"
fi
reset
if start nothing && grep -q "a first install starts with 'docker compose up -d'" "$TMP/nothing.log" && creates_nothing; then
    pass "no volume and no archive anywhere: the first-install hint, nothing created"
else
    fail "nothing anywhere: $(cat "$TMP/nothing.log")"
fi

# --- A volume without containers: started ------------------------------------------

reset
export FAKE_VOLUME=true
if start volume && called 'compose pull --quiet' && called 'compose up -d --no-recreate --wait --wait-timeout 300' &&
    grep -q "the OmniRoute stack is up" "$TMP/volume.log" && ! called 'compose down'; then
    pass "a data volume without containers: pulled and started, without recreating anything"
else
    fail "a volume: $(cat "$TMP/volume.log")"
fi
reset
export FAKE_VOLUME=true FAKE_PULL_FAIL=true
if start pullfail && grep -q "could not pull" "$TMP/pullfail.log" && ! called 'compose up'; then
    pass "offline: a warning, exit 0, and nothing started"
else
    fail "pull failure: $(cat "$TMP/pullfail.log")"
fi
reset
export FAKE_VOLUME=true FAKE_UP_FAIL=true
if start upfail; then
    fail "a stack that does not become healthy exits 0"
else
    if grep -q "ERROR: the stack did not become healthy" "$TMP/upfail.log"; then
        pass "a stack that does not become healthy fails the apply"
    else
        fail "unhealthy: $(cat "$TMP/upfail.log")"
    fi
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-omniroute-stack] all checks passed" >&2
fi
exit "$EXIT_CODE"
