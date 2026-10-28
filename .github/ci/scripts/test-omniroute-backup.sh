#!/bin/bash
set -euo pipefail

# Tests the OmniRoute backup feature without Docker, an OmniRoute stack, Windows or a real key:
# `docker` is a stub backed by a fake container directory and a fixture of its `docker inspect`,
# `cmd.exe` and `wslpath` stand in for Windows' side of the personal OneDrive, and `age` runs for
# real against a throwaway key, so a broken encryption round-trip fails here and not on the day of
# a restore. The script is rendered from its template first; the installer is rendered and run
# with a WSL kernel file and with a bare-metal one, and a stub systemctl records what it would
# enable.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-omniroute-backup] testing the OmniRoute backup script and its installer..." >&2

pass() { echo "[test-omniroute-backup] PASS: $1" >&2; }
fail() { echo "[test-omniroute-backup] FAIL: $1" >&2; EXIT_CODE=1; }

TEMPLATE="$REPO_ROOT/dot_local/bin/executable_omniroute-backup.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-013-setup-omniroute-backup.sh.tmpl"
SERVICE="$REPO_ROOT/dot_config/systemd/user/omniroute-backup.service"
TIMER="$REPO_ROOT/dot_config/systemd/user/omniroute-backup.timer"

for tool in age age-keygen chezmoi jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-omniroute-backup] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

# The secrets the fake gateway runs with: none of them may ever reach the output.
SECRETS=(fake-jwt-secret-value fake-api-key-secret-value fake-storage-key-value fake-initial-password-value)

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF

SCRIPT="$TMP/omniroute-backup"
if chezmoi execute-template --config "$TMP/chezmoi.yaml" < "$TEMPLATE" > "$SCRIPT"; then
    chmod +x "$SCRIPT"
    pass "the backup script renders"
else
    fail "the backup script does not render"
    exit 1
fi
if [[ "$(basename "$TEMPLATE")" == executable_* ]]; then
    pass "the backup script deploys executable"
else
    fail "the backup script does not deploy executable"
fi

# --- The backup script, against a stub docker and a throwaway key ------------

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
age-keygen -o "$HOME/.ssh/omniroute-backup-key" 2>/dev/null
KEY="$HOME/.ssh/omniroute-backup-key"

FAKE_CONTAINER="$TMP/container"
mkdir -p "$FAKE_CONTAINER/app/data" "$TMP/ca"
printf 'STORAGE_ENCRYPTION_KEY_VERSION=v1\n' > "$FAKE_CONTAINER/app/data/server.env"
printf -- '-----BEGIN CERTIFICATE-----\nfake corporate root\n-----END CERTIFICATE-----\n' > "$TMP/ca/ca-bundle.pem"

# What `docker inspect` says about the running gateway: Compose's environment, with .env's secrets,
# the CA bundle on this machine, and keys that must never travel -- NODE_OPTIONS above all.
jq -n --arg ca "$TMP/ca/ca-bundle.pem" '[{
    State: {Running: true, Status: "running"},
    Config: {
        Image: "ghcr.io/rios0rios0/omniroute@sha256:1111111111111111111111111111111111111111111111111111111111111111",
        Env: [
            "PATH=/usr/local/bin:/usr/bin:/bin",
            "JWT_SECRET=fake-jwt-secret-value",
            "API_KEY_SECRET=fake-api-key-secret-value",
            "INITIAL_PASSWORD=fake-initial-password-value",
            "STORAGE_ENCRYPTION_KEY=fake-storage-key-value",
            ("OMNIROUTE_CA_BUNDLE=" + $ca),
            "NODE_OPTIONS=--require /tmp/evil.js",
            "DATA_DIR=/app/data",
            "QODER_OAUTH_CLIENT_SECRET=first line\nsecond line"
        ]
    }
}]' > "$FAKE_CONTAINER/inspect.json"

mkdir -p "$TMP/stub"
cat > "$TMP/stub/docker" <<'STUB_DOCKER'
#!/bin/bash
# A docker stub for one fake container whose files live in $FAKE_CONTAINER.
set -euo pipefail
fake="${FAKE_CONTAINER:?stub docker: FAKE_CONTAINER is not set}"
cmd="${1:-}"
shift || true
case "$cmd" in
    inspect)
        if [[ "${FAKE_INSPECT_FAIL:-}" == "true" ]]; then
            echo "[]"
            exit 1
        fi
        last=""
        for last in "$@"; do :; done
        if [[ "$last" == "dotfiles-omniroute-1" && "${FAKE_RUNNING:-true}" == "true" ]]; then
            cat "$fake/inspect.json"
        else
            echo '[{"State":{"Running":false,"Status":"exited"}}]'
        fi
        ;;
    exec)
        if [[ " $* " == *" node - "* ]]; then
            # The VACUUM INTO program arrives on stdin; keep it for the suite to inspect.
            cat > "$fake/last-exec-stdin"
            if [[ "${FAKE_SNAPSHOT_FAIL:-}" == "true" ]]; then
                exit 1
            fi
            printf 'fake sqlite snapshot\n' > "$fake/app/data/.omniroute-backup-snapshot.sqlite"
            printf '{"schema":212,"providers":%s,"api_keys":%s}\n' "${FAKE_PROVIDERS:-2}" "${FAKE_API_KEYS:-1}"
        else
            for arg in "$@"; do
                if [[ "$arg" == /app/data/* ]]; then
                    rm -f "$fake$arg"
                fi
            done
        fi
        ;;
    cp)
        src="${1:?stub docker cp: no source}"
        dst="${2:?stub docker cp: no destination}"
        cp "$fake${src#dotfiles-omniroute-1:}" "$dst"
        ;;
    *)
        echo "stub docker: unhandled command: $cmd" >&2
        exit 2
        ;;
esac
STUB_DOCKER
chmod +x "$TMP/stub/docker"

# Windows' side of the personal OneDrive: cmd.exe answers %NAME% from FAKE_WIN_<NAME> -- unset
# prints the name back, as cmd.exe does -- and logs every variable it was asked for; wslpath maps
# C:\ under $FAKE_C. Both shadow the real ones on a WSL machine, so no test ever writes there.
cat > "$TMP/stub/cmd.exe" <<'STUB_CMD'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" =~ ^echo\ %([A-Za-z]+)%$ ]]; then
        name="${BASH_REMATCH[1]}"
        echo "$name" >> "${FAKE_CMD_LOG:-/dev/null}"
        var="FAKE_WIN_$name"
        printf '%s\r\n' "${!var:-%$name%}"
        exit 0
    fi
done
exit 1
STUB_CMD
cat > "$TMP/stub/wslpath" <<'STUB_WSLPATH'
#!/bin/bash
path="${@: -1}"
path="${path//\\//}"
printf '%s\n' "${FAKE_C:?}/${path#C:/}"
STUB_WSLPATH
chmod +x "$TMP/stub/cmd.exe" "$TMP/stub/wslpath"

export FAKE_CONTAINER PATH="$TMP/stub:$PATH"
export FAKE_C="$TMP/c" FAKE_CMD_LOG="$TMP/cmd.log"
export OMNIROUTE_BACKUP_DIR="$TMP/backups"
export OMNIROUTE_BACKUP_KEEP=2
export OMNIROUTE_BACKUP_MIRROR="$TMP/mirror"

# What a produced archive is called, named once so the counting around it cannot drift.
ARCHIVE_GLOB='omniroute-*.tar.age'

# Whether the file $1 carries any of the fake secrets.
leaks() {
    local file="$1" secret
    for secret in "${SECRETS[@]}"; do
        grep -qF -- "$secret" "$file" && return 0
    done
    return 1
}

if "$SCRIPT" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help does not exit 0"
fi
if "$SCRIPT" --bogus >/dev/null 2>&1; then
    fail "an unknown argument exits 0"
else
    pass "an unknown argument exits non-zero"
fi

if "$SCRIPT" >"$TMP/run1.out" 2>"$TMP/run1.log"; then
    pass "a first backup succeeds"
else
    fail "a first backup failed: $(cat "$TMP/run1.log")"
fi
if ! leaks "$TMP/run1.log" && ! leaks "$TMP/run1.out"; then
    pass "the run prints none of the gateway's secrets"
else
    fail "the run printed a secret"
fi

first="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | head -n 1)"
if [[ -n "$first" ]]; then
    pass "an archive appeared"
else
    fail "no archive appeared"
fi
if grep -q "VACUUM INTO" "$FAKE_CONTAINER/last-exec-stdin" 2>/dev/null; then
    pass "the snapshot program uses VACUUM INTO"
else
    fail "the snapshot program does not use VACUUM INTO"
fi
if grep -q "_omniroute_migrations" "$FAKE_CONTAINER/last-exec-stdin" && grep -q "provider_connections" "$FAKE_CONTAINER/last-exec-stdin" &&
    grep -q "FROM api_keys" "$FAKE_CONTAINER/last-exec-stdin"; then
    pass "the snapshot program counts the schema, the providers and the API keys"
else
    fail "the snapshot program does not count what the manifest records"
fi
if [[ ! -e "$FAKE_CONTAINER/app/data/.omniroute-backup-snapshot.sqlite" ]]; then
    pass "the in-container snapshot was cleaned up"
else
    fail "the in-container snapshot was left behind"
fi
if list="$(age -d -i "$KEY" "$first" 2>/dev/null | tar -tf - | LC_ALL=C sort | tr '\n' ' ')"; then
    if [[ "$list" == "ca-bundle.pem compose.env manifest server.env storage.sqlite " ]]; then
        pass "the archive decrypts and holds the database, both env files, the manifest and the CA bundle"
    else
        fail "the archive holds: $list"
    fi
else
    fail "the archive does not decrypt with its own key"
fi
content="$(age -d -i "$KEY" "$first" | tar -xOf - storage.sqlite)"
if [[ "$content" == "fake sqlite snapshot" ]]; then
    pass "the archive round-trips the snapshot bytes"
else
    fail "the archive content differs: $content"
fi

# compose.env: exactly the allowed keys, with their values; nothing Compose set for itself, no
# NODE_OPTIONS, and no value that spans lines.
age -d -i "$KEY" "$first" | tar -xOf - compose.env > "$TMP/compose.env"
if [[ "$(cut -d= -f1 "$TMP/compose.env" | LC_ALL=C sort | tr '\n' ' ')" == "API_KEY_SECRET INITIAL_PASSWORD JWT_SECRET OMNIROUTE_CA_BUNDLE STORAGE_ENCRYPTION_KEY " ]]; then
    pass "compose.env carries the allowed keys and nothing else"
else
    fail "compose.env carries: $(cut -d= -f1 "$TMP/compose.env" | tr '\n' ' ')"
fi
if grep -qx 'STORAGE_ENCRYPTION_KEY=fake-storage-key-value' "$TMP/compose.env"; then
    pass "compose.env keeps the storage key's value"
else
    fail "compose.env lost the storage key's value"
fi
if grep -q "QODER_OAUTH_CLIENT_SECRET spans several lines" "$TMP/run1.log"; then
    pass "a value that spans lines is named and left out"
else
    fail "a value that spans lines is not reported"
fi
if [[ "$(age -d -i "$KEY" "$first" | tar -xOf - ca-bundle.pem)" == "$(cat "$TMP/ca/ca-bundle.pem")" ]]; then
    pass "the archive carries the CA bundle .env names"
else
    fail "the archive's CA bundle differs from the one .env names"
fi

age -d -i "$KEY" "$first" | tar -xOf - manifest > "$TMP/manifest"
for line in "format=2" "device=test-device" "schema=212" "providers=2" "api_keys=1" \
    "image=ghcr.io/rios0rios0/omniroute@sha256:1111111111111111111111111111111111111111111111111111111111111111"; do
    if grep -qxF "$line" "$TMP/manifest"; then
        pass "the manifest records $line"
    else
        fail "the manifest does not record $line"
    fi
done
stamp="$(basename "$first" .tar.age)"
stamp="${stamp#omniroute-}"
created="$(sed -n 's/^created=//p' "$TMP/manifest")"
if [[ "$created" == "${stamp:0:4}-${stamp:4:2}-${stamp:6:2}T${stamp:9:2}:${stamp:11:2}:${stamp:13:2}Z" ]]; then
    pass "the manifest's time is the archive name's"
else
    fail "the manifest's time ($created) is not the archive name's ($stamp)"
fi

# The mirror: a byte-for-byte copy under the device's folder.
if [[ -f "$TMP/mirror/test-device/${first##*/}" ]] && cmp -s "$first" "$TMP/mirror/test-device/${first##*/}"; then
    pass "the archive is copied to the mirror, under the device's folder"
else
    fail "the archive is not in the mirror"
fi
if ! find "$TMP/mirror" -name '*.tmp' | grep -q .; then
    pass "the mirror holds no partial copy"
else
    fail "the mirror holds a partial copy"
fi

# Retention keeps the newest OMNIROUTE_BACKUP_KEEP archives.
sleep 1
if "$SCRIPT" >/dev/null 2>&1; then
    pass "a second backup succeeds"
else
    fail "a second backup failed"
fi
sleep 1
if "$SCRIPT" >/dev/null 2>&1; then
    pass "a third backup succeeds"
else
    fail "a third backup failed"
fi
count="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
if [[ "$count" -eq 2 ]]; then
    pass "retention keeps the newest 2"
else
    fail "retention left $count archives, expected 2"
fi
if [[ ! -e "$first" ]]; then
    pass "the oldest archive was removed"
else
    fail "the oldest archive survived retention"
fi

# Mirror retention: the newest OMNIROUTE_BACKUP_MIRROR_KEEP, plus the newest of each of the
# OMNIROUTE_BACKUP_MIRROR_MONTHLY most recent months, by the names; anything else stays.
mkdir -p "$TMP/mirror2/test-device"
for name in 20260101T033000Z 20260115T033000Z 20260201T033000Z 20260220T033000Z 20260301T033000Z \
    20260302T033000Z 20260303T033000Z; do
    printf 'old\n' > "$TMP/mirror2/test-device/omniroute-$name.tar.age"
done
printf 'not ours\n' > "$TMP/mirror2/test-device/notes.txt"
if OMNIROUTE_BACKUP_MIRROR="$TMP/mirror2" OMNIROUTE_BACKUP_MIRROR_KEEP=2 OMNIROUTE_BACKUP_MIRROR_MONTHLY=3 \
    "$SCRIPT" >/dev/null 2>&1; then
    new="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    left="$(find "$TMP/mirror2/test-device" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')"
    # Newest first: the new archive (this month) and 20260303 are the newest two; the newest of the
    # three most recent months are the new one, 20260303 (March) and 20260220 (February).
    if [[ "$left" == "notes.txt omniroute-20260220T033000Z.tar.age omniroute-20260303T033000Z.tar.age $new " ]]; then
        pass "the mirror keeps the newest two and the newest of each of three months, and leaves other files"
    else
        fail "the mirror kept: $left"
    fi
else
    fail "a backup with a seeded mirror failed"
fi

# The personal OneDrive: %OneDriveConsumer%, never %OneDrive% -- the work account's on a machine
# signed in to both.
mkdir -p "$TMP/c/Users/Test/OneDrive" "$TMP/c/Users/Test/OneDrive - Work"
: > "$FAKE_CMD_LOG"
if OMNIROUTE_BACKUP_MIRROR=onedrive-personal FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' \
    FAKE_WIN_OneDrive='C:\Users\Test\OneDrive - Work' "$SCRIPT" >/dev/null 2>"$TMP/onedrive.log"; then
    if find "$TMP/c/Users/Test/OneDrive/Backup/omniroute/test-device" -name "$ARCHIVE_GLOB" | grep -q .; then
        pass "'onedrive-personal' copies to %OneDriveConsumer%\\Backup\\omniroute\\<device>"
    else
        fail "'onedrive-personal' did not copy to the personal OneDrive"
    fi
else
    fail "a backup to the personal OneDrive failed: $(cat "$TMP/onedrive.log")"
fi
if [[ -z "$(find "$TMP/c/Users/Test/OneDrive - Work" -mindepth 1)" ]] && ! grep -qx OneDrive "$FAKE_CMD_LOG"; then
    pass "%OneDrive% is never read, and the work account's folder stays empty"
else
    fail "the work OneDrive was read or written"
fi
newest_before="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
sleep 1
if OMNIROUTE_BACKUP_MIRROR=onedrive-personal FAKE_WIN_OneDrive='C:\Users\Test\OneDrive - Work' \
    "$SCRIPT" >/dev/null 2>"$TMP/noconsumer.log"; then
    fail "a missing personal OneDrive exits 0"
else
    newest_after="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    if grep -q "OneDriveConsumer" "$TMP/noconsumer.log" && [[ "$newest_after" != "$newest_before" ]]; then
        pass "a missing personal OneDrive fails the run, says why, and keeps the archive here"
    else
        fail "a missing personal OneDrive fails without keeping the archive or saying why: $(cat "$TMP/noconsumer.log")"
    fi
fi
if [[ -z "$(find "$TMP/c/Users/Test/OneDrive - Work" -mindepth 1)" ]]; then
    pass "without a personal OneDrive nothing falls back to the work one"
else
    fail "without a personal OneDrive the archive went to the work one"
fi

# A mirror that cannot be written fails the run after the archive is kept.
printf 'a file, not a folder\n' > "$TMP/not-a-folder"
newest_before="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
sleep 1
if OMNIROUTE_BACKUP_MIRROR="$TMP/not-a-folder" "$SCRIPT" >/dev/null 2>"$TMP/mirrorfail.log"; then
    fail "an unwritable mirror exits 0"
else
    newest_after="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    if [[ "$newest_after" != "$newest_before" ]] && grep -q "stays in" "$TMP/mirrorfail.log"; then
        pass "an unwritable mirror fails the run after keeping the archive here"
    else
        fail "an unwritable mirror lost the archive or said nothing: $(cat "$TMP/mirrorfail.log")"
    fi
fi

# An empty gateway is archived, but rotates nothing out and is never copied to the mirror.
for i in 1 2 3; do
    touch -d "2026-01-0${i} 03:30" "$OMNIROUTE_BACKUP_DIR/omniroute-2026010${i}T033000Z.tar.age"
done
before="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
mirrored_before="$(find "$TMP/mirror/test-device" -name "$ARCHIVE_GLOB" | wc -l)"
sleep 1
if FAKE_PROVIDERS=0 FAKE_API_KEYS=0 "$SCRIPT" >/dev/null 2>"$TMP/empty.log"; then
    after="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
    mirrored_after="$(find "$TMP/mirror/test-device" -name "$ARCHIVE_GLOB" | wc -l)"
    if [[ "$after" -eq $((before + 1)) && "$mirrored_after" -eq "$mirrored_before" ]] && grep -q "holds no provider and no API key" "$TMP/empty.log"; then
        pass "an empty gateway is archived here, rotates nothing out and is not mirrored"
    else
        fail "an empty gateway: $before -> $after here, $mirrored_before -> $mirrored_after mirrored: $(cat "$TMP/empty.log")"
    fi
else
    fail "an empty gateway fails the run"
fi
if FAKE_PROVIDERS=1 FAKE_API_KEYS=0 "$SCRIPT" >/dev/null 2>&1 &&
    [[ "$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)" -eq 2 ]]; then
    pass "a gateway with one provider rotates as usual"
else
    fail "a gateway with one provider did not rotate"
fi

# A stopped stack or an unreachable daemon skips with a warning, not a failure.
before="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
if FAKE_RUNNING=false "$SCRIPT" 2>"$TMP/down.log"; then
    pass "a stopped stack skips with exit 0"
else
    fail "a stopped stack does not skip cleanly"
fi
if grep -q "WARN: container .* is not running" "$TMP/down.log"; then
    pass "the skip says why"
else
    fail "the skip does not say why"
fi
if FAKE_INSPECT_FAIL=true "$SCRIPT" >/dev/null 2>&1; then
    pass "an unreachable Docker daemon skips with exit 0"
else
    fail "an unreachable Docker daemon does not skip cleanly"
fi
after="$(find "$OMNIROUTE_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
if [[ "$before" -eq "$after" ]]; then
    pass "skip runs write nothing"
else
    fail "a skip run wrote an archive"
fi

# A missing identity fails the run, because silently not backing up is worse.
if OMNIROUTE_BACKUP_IDENTITY="$TMP/nope" "$SCRIPT" >/dev/null 2>"$TMP/nokey.log"; then
    fail "a missing identity exits 0"
else
    pass "a missing identity fails the run"
fi
if grep -q "no age identity at" "$TMP/nokey.log"; then
    pass "the failure says what is missing"
else
    fail "the failure does not say what is missing"
fi

# A failed snapshot fails the run too.
if FAKE_SNAPSHOT_FAIL=true "$SCRIPT" >/dev/null 2>"$TMP/snap.log"; then
    fail "a failed snapshot exits 0"
else
    pass "a failed snapshot fails the run"
fi
if grep -q "snapshot failed" "$TMP/snap.log"; then
    pass "the failure says the snapshot failed"
else
    fail "the failure does not say the snapshot failed"
fi

# A device name that cannot name a folder is refused before anything is written.
if OMNIROUTE_BACKUP_DEVICE='../escape' "$SCRIPT" >/dev/null 2>&1; then
    fail "a device name with a path in it exits 0"
else
    pass "a device name with a path in it is refused"
fi

# --- The installer: the WSL gate and the systemd handoff ---------------------

mkdir -p "$TMP/systemd" "$TMP/stubctl" "$TMP/emptyhome"
printf 'Linux version 5.15.167.4-microsoft-standard-WSL2 (x86_64)\n' > "$TMP/proc-version-wsl"
printf 'Linux version 6.8.0-45-generic (x86_64)\n' > "$TMP/proc-version-bare"
cat > "$TMP/stubctl/systemctl" <<'STUB_SYSTEMCTL'
#!/bin/bash
# Records every call and succeeds at everything.
set -euo pipefail
if [[ -n "${SYSTEMCTL_LOG:-}" ]]; then
    echo "systemctl $*" >> "$SYSTEMCTL_LOG"
fi
exit 0
STUB_SYSTEMCTL
chmod +x "$TMP/stubctl/systemctl"
export SYSTEMCTL_LOG="$TMP/systemctl.log"
: > "$SYSTEMCTL_LOG"

# Renders the installer for a run: $1 is the directory the template should treat as
# /run/systemd/system, $2 the file that stands in for /proc/version, since no CI runner has a
# WSL kernel.
render_installer() {
    local systemd_dir="$1"
    local proc_version="$2"
    sed -e "s|/run/systemd/system|$systemd_dir|g" \
        -e "s|/proc/version|$proc_version|g" \
        "$INSTALLER" \
        | chezmoi execute-template --config "$TMP/chezmoi.yaml"
}

if rendered="$(render_installer "$TMP/systemd" "$TMP/proc-version-wsl")"; then
    if [[ "$rendered" == *"omniroute-backup.timer"* ]]; then
        pass "the installer mentions the timer"
    else
        fail "the installer does not mention the timer"
    fi
    if grep -qx '#   systemd running' <<<"$rendered"; then
        pass "the installer says systemd is running"
    else
        fail "the installer does not say systemd is running"
    fi
    for kind in service timer script; do
        if grep -qE "$kind [0-9a-f]{64}" <<<"$rendered"; then
            pass "the installer records the $kind digest"
        else
            fail "the installer does not record the $kind digest"
        fi
    done
else
    fail "the installer failed to render for WSL"
fi

# The script's digest is of what it renders to, so a change to its data or to lib-omniroute.sh
# re-runs the installer too.
script_digest="$(grep -oE 'script [0-9a-f]{64}' <<<"$rendered" | cut -d' ' -f2)"
if [[ "$script_digest" == "$(sha256sum "$SCRIPT" | cut -d' ' -f1)" ]]; then
    pass "the installer's script digest is the rendered script's"
else
    fail "the installer's script digest is not the rendered script's"
fi
cat > "$TMP/chezmoi-other.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "other-device"
EOF
other_digest="$(sed -e "s|/proc/version|$TMP/proc-version-wsl|g" "$INSTALLER" |
    chezmoi execute-template --config "$TMP/chezmoi-other.yaml" | grep -oE 'script [0-9a-f]{64}' | cut -d' ' -f2)"
if [[ -n "$other_digest" && "$other_digest" != "$script_digest" ]]; then
    pass "another device name changes the script digest"
else
    fail "the script digest ignores the rendered data"
fi

printf '%s\n' "$rendered" > "$TMP/installer.sh"
chmod +x "$TMP/installer.sh"

export PATH="$TMP/stubctl:$PATH"
if FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' bash "$TMP/installer.sh" 2>"$TMP/install.log"; then
    pass "the installer runs where systemd is up"
else
    fail "the installer failed where systemd is up: $(cat "$TMP/install.log")"
fi
for call in "daemon-reload" "enable omniroute-backup.timer" "start omniroute-backup.timer"; do
    if grep -qF -- "$call" "$SYSTEMCTL_LOG"; then
        pass "the installer calls: $call"
    else
        fail "the installer never calls: $call"
    fi
done
if grep -qF "copied to $TMP/c/Users/Test/OneDrive/Backup/omniroute/test-device" "$TMP/install.log"; then
    pass "the installer names where the archives are copied"
else
    fail "the installer does not name the mirror: $(cat "$TMP/install.log")"
fi
if bash "$TMP/installer.sh" 2>"$TMP/install-noonedrive.log" &&
    grep -q "WARN: the archives cannot be copied off this machine.*OneDriveConsumer" "$TMP/install-noonedrive.log"; then
    pass "the installer warns, and still succeeds, without a personal OneDrive"
else
    fail "the installer does not warn about a missing personal OneDrive: $(cat "$TMP/install-noonedrive.log")"
fi

if HOME="$TMP/emptyhome" bash "$TMP/installer.sh" 2>"$TMP/install-keywarn.log"; then
    if grep -q "fetches it from 1Password (op://" "$TMP/install-keywarn.log"; then
        pass "the installer warns when the backup key is missing, and names the item"
    else
        fail "the installer does not warn when the backup key is missing"
    fi
else
    fail "the installer fails when the backup key is missing (it should only warn)"
fi

if rendered_nosystemd="$(render_installer "$TMP/no-systemd" "$TMP/proc-version-wsl")"; then
    printf '%s\n' "$rendered_nosystemd" > "$TMP/installer-nosystemd.sh"
    if grep -qx '#   systemd not running' "$TMP/installer-nosystemd.sh"; then
        pass "the installer says systemd is not running"
    else
        fail "the installer does not say systemd is not running"
    fi
    if bash "$TMP/installer-nosystemd.sh" 2>"$TMP/install-nosystemd.log"; then
        if grep -q "WARN: systemd is not running" "$TMP/install-nosystemd.log"; then
            pass "the installer exits 0 and says systemd is missing"
        else
            fail "the installer does not say systemd is missing"
        fi
    else
        fail "the installer does not exit 0 without systemd"
    fi
else
    fail "the installer failed to render without systemd"
fi

if rendered_bare="$(render_installer "$TMP/systemd" "$TMP/proc-version-bare")"; then
    printf '%s\n' "$rendered_bare" > "$TMP/installer-bare.sh"
    if SYSTEMCTL_LOG="$TMP/systemctl-bare.log" bash "$TMP/installer-bare.sh" >/dev/null 2>"$TMP/install-bare.log"; then
        if [[ ! -e "$TMP/systemctl-bare.log" ]]; then
            pass "the installer exits 0 without touching systemctl off WSL"
        else
            fail "the installer reaches systemctl off WSL"
        fi
    else
        fail "the installer fails off WSL: $(cat "$TMP/install-bare.log")"
    fi
else
    fail "the installer failed to render for bare metal"
fi

# The units themselves: what the timer and the service promise.
if grep -q "ExecStart=%h/.local/bin/omniroute-backup" "$SERVICE"; then
    pass "the service starts the backup script"
else
    fail "the service does not start the backup script"
fi
if grep -q "Persistent=true" "$TIMER"; then
    pass "the timer catches up on missed runs"
else
    fail "the timer does not catch up on missed runs"
fi
if grep -q "WantedBy=timers.target" "$TIMER"; then
    pass "the timer is enabled at the timers target"
else
    fail "the timer is not enabled at the timers target"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-omniroute-backup] all checks passed" >&2
fi
exit "$EXIT_CODE"
