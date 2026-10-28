#!/bin/bash
set -euo pipefail

# Tests omniroute-restore without Docker, a gateway, Windows or 1Password. The archives are real:
# fixture databases built with sqlite3, packed with tar and encrypted with age to a throwaway key,
# so the decryption, the member allowlist, the integrity and schema checks and the env filtering
# all run for real. `docker` is a stub that records every call and keeps what would have gone into
# the data volume; its `run --entrypoint node` runs the restore's key check with the host's node,
# against credentials encrypted the way OmniRoute encrypts them, so a wrong derivation fails here.
# `op` and omniroute-backup are stubs too, and cmd.exe/wslpath shadow Windows' on a WSL machine.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0
# The stub's record of the container's entrypoint shell: the restore started the gateway.
ENTRYPOINT_CALL='entrypoint sh'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-omniroute-restore] testing the OmniRoute restore..." >&2

pass() { echo "[test-omniroute-restore] PASS: $1" >&2; }
fail() { echo "[test-omniroute-restore] FAIL: $1" >&2; EXIT_CODE=1; }

for tool in age age-keygen chezmoi jq sqlite3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-omniroute-restore] SKIP: $tool is not installed" >&2
        exit 0
    fi
done
HAVE_NODE=false
command -v node >/dev/null 2>&1 && HAVE_NODE=true

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF
RESTORE="$TMP/omniroute-restore"
if chezmoi execute-template --config "$TMP/chezmoi.yaml" < "$REPO_ROOT/dot_local/bin/executable_omniroute-restore.tmpl" > "$RESTORE"; then
    chmod +x "$RESTORE"
    pass "the restore renders"
else
    fail "the restore does not render"
    exit 1
fi
if grep -qx "default_env_reference='op://Private/OmniRouter/notesPlain'" "$RESTORE" &&
    grep -qx "default_ca_reference='op://Private/OmniRouter/ca-bundle.pem'" "$RESTORE"; then
    pass "the 1Password references come from .chezmoidata/omniroute.yaml"
else
    fail "the 1Password references are not the ones .chezmoidata/omniroute.yaml names"
fi

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
age-keygen -o "$HOME/.ssh/omniroute-backup-key" 2>/dev/null
KEY_FILE="$HOME/.ssh/omniroute-backup-key"
STORAGE_KEY="fake-storage-key-value"
WRONG_KEY="another-storage-key-value"
CA_PATH="$HOME/.local/share/omniroute/ca-bundle.pem"
SECRETS=(fake-jwt-secret-value fake-api-key-secret-value "$STORAGE_KEY" fake-initial-password-value nvapi-fake-provider-key)

# --- Fixtures ------------------------------------------------------------------

# encrypt <key> <static|legacy>: a credential encrypted the way OmniRoute's encryption.ts does.
encrypt() {
    K="$1" SALT="$2" node -e '
const { createCipheriv, createHash, randomBytes, scryptSync } = require("node:crypto");
const secret = process.env.K;
const salt = process.env.SALT === "legacy" ? createHash("sha256").update(secret).digest().subarray(0, 16) : "omniroute-field-encryption-v1";
const iv = randomBytes(16);
const cipher = createCipheriv("aes-256-gcm", scryptSync(secret, salt, 32), iv);
let data = cipher.update("nvapi-fake-provider-key", "utf8", "hex");
data += cipher.final("hex");
console.log("enc:v1:" + iv.toString("hex") + ":" + data + ":" + cipher.getAuthTag().toString("hex"));'
}

# make_db <file> <schema> <credential>
make_db() {
    local file="$1" schema="$2" credential="$3" versions="" i
    for ((i = 1; i <= schema; i++)); do
        versions+="('$(printf '%03d' "$i")','m$i'),"
    done
    sqlite3 "$file" "
CREATE TABLE _omniroute_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT (datetime('now')));
INSERT INTO _omniroute_migrations (version, name) VALUES ${versions%,};
CREATE TABLE provider_connections (id TEXT PRIMARY KEY, provider TEXT, api_key TEXT, access_token TEXT, refresh_token TEXT, id_token TEXT);
INSERT INTO provider_connections VALUES ('c1', 'nvidia', NULL, '$credential', NULL, NULL);
CREATE TABLE api_keys (id TEXT PRIMARY KEY, name TEXT NOT NULL, key TEXT NOT NULL UNIQUE, machine_id TEXT, created_at TEXT NOT NULL);
INSERT INTO api_keys VALUES ('k1', 'opencode', 'hashed', NULL, '2026-10-27');"
}

# pack <archive> <dir> <members...>: what omniroute-backup writes, encrypted to the test key.
pack() {
    local archive="$1" dir="$2"
    shift 2
    tar -C "$dir" -cf - "$@" | age -e -i "$KEY_FILE" -o "$archive"
}

if $HAVE_NODE; then
    CREDENTIAL="$(encrypt "$STORAGE_KEY" static)"
    LEGACY_CREDENTIAL="$(encrypt "$STORAGE_KEY" legacy)"
else
    echo "[test-omniroute-restore] SKIP: node is not installed, so the key check runs against plaintext credentials" >&2
    CREDENTIAL="plaintext"
    LEGACY_CREDENTIAL="plaintext"
fi

F="$TMP/fixtures"
mkdir -p "$F/v2" "$F/v1" "$F/planted" "$F/corrupt" "$F/newer" "$F/legacy"
make_db "$F/v2/storage.sqlite" 5 "$CREDENTIAL"
printf 'STORAGE_ENCRYPTION_KEY_VERSION=v1\nNODE_OPTIONS=--require /tmp/evil.js\n' > "$F/v2/server.env"
cat > "$F/v2/compose.env" <<EOF
JWT_SECRET=fake-jwt-secret-value
API_KEY_SECRET=fake-api-key-secret-value
INITIAL_PASSWORD=fake-initial-password-value
STORAGE_ENCRYPTION_KEY=$STORAGE_KEY
OMNIROUTE_CA_BUNDLE=$CA_PATH
EVIL=1
EOF
printf 'format=2\ncreated=2026-10-27T03:30:00Z\ndevice=other-device\nimage=ghcr.io/rios0rios0/omniroute@sha256:3333\nschema=5\nproviders=1\napi_keys=1\n' > "$F/v2/manifest"
printf -- '-----BEGIN CERTIFICATE-----\narchived root\n-----END CERTIFICATE-----\n' > "$F/v2/ca-bundle.pem"
pack "$F/v2.tar.age" "$F/v2" storage.sqlite server.env compose.env manifest ca-bundle.pem

cp "$F/v2/storage.sqlite" "$F/v2/server.env" "$F/v1/"
pack "$F/v1.tar.age" "$F/v1" storage.sqlite server.env

cp "$F/v2/storage.sqlite" "$F/v2/server.env" "$F/planted/"
printf '#!/bin/sh\necho owned\n' > "$F/planted/evil.sh"
pack "$F/planted.tar.age" "$F/planted" storage.sqlite server.env evil.sh

printf 'not a database at all\n' > "$F/corrupt/storage.sqlite"
cp "$F/v2/server.env" "$F/corrupt/"
pack "$F/corrupt.tar.age" "$F/corrupt" storage.sqlite server.env

make_db "$F/newer/storage.sqlite" 9 "$CREDENTIAL"
cp "$F/v2/server.env" "$F/v2/manifest" "$F/newer/"
pack "$F/newer.tar.age" "$F/newer" storage.sqlite server.env manifest

make_db "$F/legacy/storage.sqlite" 5 "$LEGACY_CREDENTIAL"
cp "$F/v2/server.env" "$F/v2/compose.env" "$F/legacy/"
pack "$F/legacy.tar.age" "$F/legacy" storage.sqlite server.env compose.env

# --- Stubs ----------------------------------------------------------------------

STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/docker" <<'STUB_DOCKER'
#!/bin/bash
# Records every call on one line in $FAKE/calls.log and answers as a Docker with the stack's images.
set -uo pipefail
printf 'docker %s\n' "$(printf '%s ' "$@" | tr '\n' ' ')" >> "$FAKE/calls.log"
case "${1:-}" in
    info)
        [[ "${FAKE_DOCKER_DOWN:-}" != true ]]
        exit
        ;;
    inspect)
        if [[ "${FAKE_RUNNING:-false}" == true ]]; then
            echo '[{"State":{"Running":true,"Status":"running"}}]'
        else
            echo '[]'
            exit 1
        fi
        ;;
    image)
        if [[ "${FAKE_NO_IMAGE:-}" == true ]]; then
            echo '[]'
            exit 1
        fi
        echo '[{"Config":{"Env":["PATH=/usr/bin","OMNIROUTE_MIGRATIONS_DIR=/app/migrations"]}}]'
        ;;
    compose)
        shift
        case "$*" in
            "config --quiet") [[ -f .env ]] || { echo "env file .env not found" >&2; exit 1; } ;;
            "config --images") printf 'docker.io/library/redis:8.6.5-alpine\nghcr.io/rios0rios0/omniroute@sha256:2222\n' ;;
            "pull --quiet") [[ "${FAKE_PULL_FAIL:-}" != true ]] || exit 1 ;;
            logs*) printf '%s\n' "${FAKE_LOGS:-[bootstrap] ready}" ;;
            *) ;;
        esac
        ;;
    run)
        args=" $* "
        if [[ "$args" == *" --entrypoint ls "* ]]; then
            for ((i = 1; i <= ${FAKE_IMAGE_SCHEMA:-5}; i++)); do
                printf '%03d_migration.sql\n' "$i"
            done
            printf 'README.md\n'
        elif [[ "$args" == *" --entrypoint node "* ]]; then
            command -v node >/dev/null 2>&1 || exit 3
            exec node -e "${@: -1}"
        elif [[ "$args" == *" --entrypoint sh "* ]]; then
            cat > "$FAKE/volume.tar"
            printf '%s\n' "${@: -1}" > "$FAKE/populate.sh"
        fi
        ;;
esac
exit 0
STUB_DOCKER
cat > "$STUB/op" <<'STUB_OP'
#!/bin/bash
# 1Password: the notes field holds the .env (with Windows line endings), the attachment a PEM.
printf 'op %s\n' "$*" >> "$FAKE/op.log"
[[ "${FAKE_OP_FAIL:-}" != true ]] || exit 1
case "$2" in
    op://Private/OmniRouter/notesPlain)
        printf '# from 1Password\r\nJWT_SECRET=fake-jwt-secret-value\r\nSTORAGE_ENCRYPTION_KEY=%s\r\nOMNIROUTE_CA_BUNDLE=%s\r\n' \
            "${FAKE_OP_KEY:-fake-storage-key-value}" "${FAKE_OP_CA:-$HOME/.local/share/omniroute/ca-bundle.pem}"
        ;;
    op://Private/OmniRouter/ca-bundle.pem)
        printf -- '-----BEGIN CERTIFICATE-----\n1password root\n-----END CERTIFICATE-----\n'
        ;;
    *) exit 1 ;;
esac
STUB_OP
cat > "$STUB/omniroute-backup" <<'STUB_BACKUP'
#!/bin/bash
printf 'backup mirror=%s\n' "${OMNIROUTE_BACKUP_MIRROR-<unset>}" >> "$FAKE/calls.log"
STUB_BACKUP
printf '#!/bin/bash\nexit 1\n' > "$STUB/cmd.exe"
printf '#!/bin/bash\nexit 1\n' > "$STUB/wslpath"
chmod +x "$STUB"/*

export PATH="$STUB:$PATH"
export FAKE="$TMP/fake"
export OMNIROUTE_BACKUP_DIR="$TMP/backups"
export OMNIROUTE_BACKUP_MIRROR="$TMP/mirror"
export OMNIROUTE_COMPOSE_DIR="$TMP/compose"
export OMNIROUTE_BACKUP_COMMAND="$STUB/omniroute-backup"

# A clean slate for each case: no .env, no CA bundle, empty logs.
reset() {
    rm -rf "$FAKE" "$OMNIROUTE_COMPOSE_DIR" "$HOME/.local/share/omniroute"
    mkdir -p "$FAKE" "$OMNIROUTE_COMPOSE_DIR"
    : > "$FAKE/calls.log"
    : > "$FAKE/op.log"
    printf 'name: dotfiles\n' > "$OMNIROUTE_COMPOSE_DIR/compose.yaml"
    unset FAKE_RUNNING FAKE_DOCKER_DOWN FAKE_PULL_FAIL FAKE_NO_IMAGE FAKE_LOGS FAKE_IMAGE_SCHEMA FAKE_OP_FAIL FAKE_OP_CA FAKE_OP_KEY
}

# restore <case> [args]: runs it without a terminal, stdout and stderr in $TMP/<case>.log.
restore() {
    local name="$1"
    shift
    "$RESTORE" "$@" < /dev/null > "$TMP/$name.log" 2>&1
}

# Whether the file $1 carries any of the fake secrets.
leaks() {
    local file="$1" secret
    for secret in "${SECRETS[@]}"; do
        grep -qF -- "$secret" "$file" && return 0
    done
    return 1
}

called() {
    local pattern="$1"
    grep -qE "$pattern" "$FAKE/calls.log"
}
# The line number of the first call matching $1, or 0.
call_at() {
    local pattern="$1"
    grep -nE "$pattern" "$FAKE/calls.log" | head -n 1 | cut -d: -f1 || echo 0
}

# --- Usage ----------------------------------------------------------------------

if "$RESTORE" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help does not exit 0"
fi
reset
if restore bogus --bogus; then
    fail "an unknown option exits 0"
else
    pass "an unknown option exits non-zero"
fi

# --- --list -------------------------------------------------------------------------

mkdir -p "$OMNIROUTE_BACKUP_DIR" "$OMNIROUTE_BACKUP_MIRROR/test-device" "$OMNIROUTE_BACKUP_MIRROR/other-device"
cp "$F/v1.tar.age" "$OMNIROUTE_BACKUP_DIR/omniroute-20261001T033000Z.tar.age"
cp "$F/v2.tar.age" "$OMNIROUTE_BACKUP_MIRROR/test-device/omniroute-20261002T033000Z.tar.age"
cp "$F/v2.tar.age" "$OMNIROUTE_BACKUP_MIRROR/other-device/omniroute-20261003T033000Z.tar.age"
printf 'junk\n' > "$OMNIROUTE_BACKUP_DIR/omniroute-notes.txt"
reset
if restore list --list; then
    listed="$(cut -f2 "$TMP/list.log" | tr '\n' ' ')"
    if [[ "$listed" == "$OMNIROUTE_BACKUP_MIRROR/test-device/omniroute-20261002T033000Z.tar.age $OMNIROUTE_BACKUP_DIR/omniroute-20261001T033000Z.tar.age " ]]; then
        pass "--list shows this device's archives here and in the mirror, newest first, and nothing else"
    else
        fail "--list shows: $(cat "$TMP/list.log")"
    fi
else
    fail "--list fails: $(cat "$TMP/list.log")"
fi
if restore list-other --list --device other-device && grep -q "other-device/omniroute-20261003T033000Z.tar.age" "$TMP/list-other.log" &&
    ! grep -q "$OMNIROUTE_BACKUP_DIR" "$TMP/list-other.log"; then
    pass "--list --device reads that device's folder in the mirror, and not this machine's archives"
else
    fail "--list --device shows: $(cat "$TMP/list-other.log")"
fi
if ! restore traversal --list --device '../escape'; then
    pass "a device name with a path in it is refused"
else
    fail "a device name with a path in it is accepted"
fi
rm -rf "$OMNIROUTE_BACKUP_DIR" "$OMNIROUTE_BACKUP_MIRROR"

# --- A self-contained archive on a fresh machine -----------------------------------

reset
if restore v2 --yes "$F/v2.tar.age"; then
    pass "a self-contained archive restores on a machine with no .env"
else
    fail "a self-contained archive does not restore: $(cat "$TMP/v2.log")"
fi
ENV_FILE="$OMNIROUTE_COMPOSE_DIR/.env"
if [[ -f "$ENV_FILE" && "$(stat -c '%a' "$ENV_FILE")" == 600 ]]; then
    pass ".env is written with mode 600"
else
    fail ".env is missing or not mode 600"
fi
if [[ "$(cut -d= -f1 "$ENV_FILE" | LC_ALL=C sort | tr '\n' ' ')" == "API_KEY_SECRET INITIAL_PASSWORD JWT_SECRET OMNIROUTE_CA_BUNDLE STORAGE_ENCRYPTION_KEY " ]]; then
    pass ".env takes the archive's compose.env, allowed keys only"
else
    fail ".env holds: $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')"
fi
if [[ -f "$CA_PATH" && "$(cat "$CA_PATH")" == "$(cat "$F/v2/ca-bundle.pem")" && "$(stat -c '%a' "$CA_PATH")" == 644 ]]; then
    pass "the CA bundle goes where .env names it, from the archive, readable by the gateway"
else
    fail "the CA bundle was not written from the archive"
fi
if [[ ! -s "$FAKE/op.log" ]]; then
    pass "1Password is not asked when the archive carries everything"
else
    fail "1Password was asked: $(cat "$FAKE/op.log")"
fi
if [[ -f "$FAKE/volume.tar" && "$(tar -tf "$FAKE/volume.tar" | LC_ALL=C sort | tr '\n' ' ')" == "server.env storage.sqlite " ]]; then
    pass "only the database and server.env go into the volume"
else
    fail "the volume received: $(tar -tf "$FAKE/volume.tar" 2>/dev/null | tr '\n' ' ')"
fi
if tar -xOf "$FAKE/volume.tar" server.env | grep -qx 'STORAGE_ENCRYPTION_KEY_VERSION=v1' &&
    ! tar -xOf "$FAKE/volume.tar" server.env | grep -q NODE_OPTIONS; then
    pass "server.env keeps the allowed keys and loses NODE_OPTIONS"
else
    fail "server.env in the volume: $(tar -xOf "$FAKE/volume.tar" server.env | cut -d= -f1 | tr '\n' ' ')"
fi
if cmp -s <(tar -xOf "$FAKE/volume.tar" storage.sqlite) "$F/v2/storage.sqlite"; then
    pass "the database goes into the volume byte for byte"
else
    fail "the database in the volume differs from the archive's"
fi
if grep -q "chown node:node" "$FAKE/populate.sh" && grep -q "storage.sqlite-wal" "$FAKE/populate.sh"; then
    pass "the volume's files go to the container's user, after the stale write-ahead log is removed"
else
    fail "the populate script does not chown or clear the write-ahead log"
fi
created_at="$(call_at 'docker compose create')"
populated_at="$(call_at 'docker run .*--entrypoint sh')"
up_at="$(call_at 'docker compose up -d --wait')"
if [[ "$created_at" -gt 0 && "$populated_at" -gt "$created_at" && "$up_at" -gt "$populated_at" ]]; then
    pass "Compose creates the volume, the database goes in, then the stack starts and is waited on"
else
    fail "the order was create=$created_at populate=$populated_at up=$up_at"
fi
if [[ "$(call_at "backup mirror=$OMNIROUTE_BACKUP_MIRROR\$")" -gt "$up_at" ]]; then
    pass "the first backup after the restore runs, with the mirror"
else
    fail "no backup with the mirror after the restore: $(cat "$FAKE/calls.log")"
fi
if ! called ' down'; then
    pass "nothing runs docker compose down"
else
    fail "something ran docker compose down"
fi
if $HAVE_NODE; then
    if grep -q "stored credentials: match" "$TMP/v2.log"; then
        pass "the key check opens the stored credential with the archive's key"
    else
        fail "the key check did not report a match: $(grep 'stored credentials' "$TMP/v2.log")"
    fi
fi
if ! leaks "$TMP/v2.log" && ! leaks "$FAKE/calls.log"; then
    pass "no secret reaches the output or a command line"
else
    fail "a secret reached the output or a command line"
fi
if grep -q "written on other-device at 2026-10-27T03:30:00Z" "$TMP/v2.log"; then
    pass "the summary shows where and when the archive was written"
else
    fail "the summary does not show the manifest"
fi

# --- An archive from before the manifest, .env from 1Password ------------------------

reset
if restore v1 --yes "$F/v1.tar.age"; then
    pass "a two-member archive restores"
else
    fail "a two-member archive does not restore: $(cat "$TMP/v1.log")"
fi
if grep -qF 'op read op://Private/OmniRouter/notesPlain --account my' "$FAKE/op.log" &&
    grep -qF 'op read op://Private/OmniRouter/ca-bundle.pem --account my' "$FAKE/op.log"; then
    pass "1Password supplies .env and the CA bundle, from the personal account"
else
    fail "1Password was asked for: $(cat "$FAKE/op.log")"
fi
if [[ "$(stat -c '%a' "$ENV_FILE" 2>/dev/null)" == 600 ]] && ! grep -q $'\r' "$ENV_FILE" && grep -qx '# from 1Password' "$ENV_FILE"; then
    pass "1Password's .env is written whole, mode 600, without carriage returns"
else
    fail "1Password's .env was not written as expected"
fi
if [[ "$(cat "$CA_PATH" 2>/dev/null)" == *"1password root"* ]]; then
    pass "1Password's CA bundle goes where .env names it"
else
    fail "1Password's CA bundle was not written"
fi
if grep -q "written before archives carried a manifest" "$TMP/v1.log"; then
    pass "the summary says the archive predates the manifest"
else
    fail "the summary does not handle an archive without a manifest"
fi

# --- The checkout's own .env stays, and its key is checked ---------------------------

reset
printf 'STORAGE_ENCRYPTION_KEY=%s\n' "$WRONG_KEY" > "$ENV_FILE"
if $HAVE_NODE; then
    if restore mismatch --yes "$F/v2.tar.age"; then
        fail "a .env whose key does not open the credentials restores"
    else
        if grep -q "key check says 'mismatch'" "$TMP/mismatch.log" && ! called 'compose (create|stop)' &&
            ! called "$ENTRYPOINT_CALL" && grep -qx "STORAGE_ENCRYPTION_KEY=$WRONG_KEY" "$ENV_FILE"; then
            pass "a key that does not open the credentials stops the restore before anything changes, .env kept"
        else
            fail "a mismatching key: $(cat "$TMP/mismatch.log")"
        fi
    fi
    reset
    printf 'STORAGE_ENCRYPTION_KEY=%s\n' "$WRONG_KEY" > "$ENV_FILE"
    if restore mismatch-allowed --yes --allow-key-mismatch "$F/v2.tar.age" && called "$ENTRYPOINT_CALL" &&
        grep -q "WARN: the key check says 'mismatch'" "$TMP/mismatch-allowed.log"; then
        pass "--allow-key-mismatch restores anyway, with a warning"
    else
        fail "--allow-key-mismatch: $(cat "$TMP/mismatch-allowed.log")"
    fi
    reset
    printf 'STORAGE_ENCRYPTION_KEY="%s"\n' "$STORAGE_KEY" > "$ENV_FILE"
    if restore quoted --yes "$F/v2.tar.age" && grep -q "stored credentials: match" "$TMP/quoted.log"; then
        pass "a quoted key in .env is read without its quotes, as Compose reads it"
    else
        fail "a quoted key: $(cat "$TMP/quoted.log")"
    fi
    reset
    if restore legacy --yes "$F/legacy.tar.age" && grep -q "stored credentials: match" "$TMP/legacy.log"; then
        pass "a credential under OmniRoute's legacy key derivation also opens"
    else
        fail "the legacy derivation: $(cat "$TMP/legacy.log")"
    fi
    reset
    printf 'JWT_SECRET=x\n' > "$ENV_FILE"
    if restore serverenv --yes "$F/v1.tar.age"; then
        fail "a key in neither .env nor server.env restores"
    else
        if grep -q "key check says 'no-key'" "$TMP/serverenv.log"; then
            pass "encrypted credentials with no key anywhere stop the restore"
        else
            fail "no key anywhere: $(cat "$TMP/serverenv.log")"
        fi
    fi
fi

# --- Archives that are refused -----------------------------------------------------

reset
if restore planted --yes "$F/planted.tar.age"; then
    fail "an archive with a member omniroute-backup never writes restores"
else
    if grep -q "holds 'evil.sh', which omniroute-backup never writes" "$TMP/planted.log" && ! called 'compose' && [[ ! -f "$ENV_FILE" ]]; then
        pass "an archive with an unexpected member is refused before anything is written"
    else
        fail "a planted archive: $(cat "$TMP/planted.log")"
    fi
fi
reset
if restore corrupt --yes "$F/corrupt.tar.age"; then
    fail "a database that fails its integrity check restores"
else
    if grep -q "fails its integrity check" "$TMP/corrupt.log" && ! called 'compose'; then
        pass "a database that fails its integrity check is refused"
    else
        fail "a corrupt database: $(cat "$TMP/corrupt.log")"
    fi
fi
reset
export FAKE_IMAGE_SCHEMA=7
if restore newer --yes "$F/newer.tar.age"; then
    fail "a database newer than the pinned image restores"
else
    if grep -q "at migration 9, and the image this checkout pins knows up to 7" "$TMP/newer.log" &&
        grep -q "ghcr.io/rios0rios0/omniroute@sha256:3333" "$TMP/newer.log" && ! called 'compose create'; then
        pass "a database newer than the pinned image is refused, naming the image that wrote it"
    else
        fail "a newer database: $(cat "$TMP/newer.log")"
    fi
fi
unset FAKE_IMAGE_SCHEMA
reset
printf 'garbage\n' > "$TMP/not-age.tar.age"
if restore notage --yes "$TMP/not-age.tar.age"; then
    fail "a file that does not decrypt restores"
else
    if grep -q "does not decrypt with" "$TMP/notage.log"; then
        pass "a file the key does not open is refused"
    else
        fail "an undecryptable file: $(cat "$TMP/notage.log")"
    fi
fi

# --- A running stack, the confirmation, the start ------------------------------------

reset
export FAKE_RUNNING=true
if restore running --yes "$F/v2.tar.age"; then
    snapshot_at="$(call_at 'backup mirror=$')"
    stop_at="$(call_at 'docker compose stop omniroute')"
    created_at="$(call_at 'docker compose create')"
    if [[ "$snapshot_at" -gt 0 && "$stop_at" -gt "$snapshot_at" && "$created_at" -gt "$stop_at" ]]; then
        pass "a running stack is snapshotted, without the mirror, and stopped before anything is replaced"
    else
        fail "the order was snapshot=$snapshot_at stop=$stop_at create=$created_at"
    fi
else
    fail "a restore over a running stack failed: $(cat "$TMP/running.log")"
fi
unset FAKE_RUNNING
reset
if restore notty "$F/v2.tar.age"; then
    fail "a restore without --yes and without a terminal proceeds"
else
    if grep -q "pass --yes" "$TMP/notty.log" && ! called 'compose create' && ! called "$ENTRYPOINT_CALL"; then
        pass "without a terminal, only --yes confirms, and nothing is replaced"
    else
        fail "no terminal: $(cat "$TMP/notty.log")"
    fi
fi
reset
if restore nostart --yes --no-start "$F/v2.tar.age" && called "$ENTRYPOINT_CALL" && ! called 'compose up'; then
    pass "--no-start restores into the volume and leaves the stack stopped"
else
    fail "--no-start: $(cat "$TMP/nostart.log")"
fi
reset
export FAKE_LOGS="[bootstrap] ⛔ STORAGE_ENCRYPTION_KEY does not match the key used to encrypt your stored credentials."
if restore badstart --yes "$F/v2.tar.age"; then
    fail "a gateway that reports a key mismatch at start passes"
else
    if [[ "$(call_at 'docker compose stop omniroute')" -gt "$(call_at 'docker compose up')" ]] && grep -q "so it was stopped" "$TMP/badstart.log"; then
        pass "a gateway that reports a key mismatch at start is stopped again"
    else
        fail "a mismatch at start: $(cat "$TMP/badstart.log")"
    fi
fi
unset FAKE_LOGS
reset
export FAKE_PULL_FAIL=true FAKE_NO_IMAGE=true
if restore offline --yes "$F/v2.tar.age"; then
    fail "an offline restore without the image proceeds"
else
    if grep -q "could not pull" "$TMP/offline.log" && ! called 'compose create'; then
        pass "an image that can be neither pulled nor found stops the restore"
    else
        fail "offline: $(cat "$TMP/offline.log")"
    fi
fi
reset
export FAKE_PULL_FAIL=true
if restore offline-cached --yes "$F/v2.tar.age" && grep -q "using the ones already here" "$TMP/offline-cached.log"; then
    pass "offline, the images already here are used, with a warning"
else
    fail "offline with the images here: $(cat "$TMP/offline-cached.log")"
fi
unset FAKE_PULL_FAIL

# --- Preconditions ------------------------------------------------------------------

reset
if OMNIROUTE_BACKUP_IDENTITY="$TMP/nope" restore nokey --yes "$F/v2.tar.age"; then
    fail "a restore without the backup key proceeds"
else
    if grep -q "never generate a new one" "$TMP/nokey.log"; then
        pass "a missing backup key fails, and says never to generate one"
    else
        fail "no key: $(cat "$TMP/nokey.log")"
    fi
fi
reset
export FAKE_DOCKER_DOWN=true
if restore dockerdown --yes "$F/v2.tar.age"; then
    fail "a restore without Docker proceeds"
else
    if grep -q "Docker is not reachable" "$TMP/dockerdown.log"; then
        pass "an unreachable Docker fails the restore"
    else
        fail "Docker down: $(cat "$TMP/dockerdown.log")"
    fi
fi
unset FAKE_DOCKER_DOWN
reset
export FAKE_OP_CA=/etc/omniroute/ca-bundle.pem
if restore outside --yes "$F/v1.tar.age"; then
    fail "a CA bundle outside \$HOME is written"
else
    if grep -q "is outside $HOME" "$TMP/outside.log" && [[ ! -e /etc/omniroute/ca-bundle.pem ]]; then
        pass "a CA bundle outside \$HOME is left to the user, with a hint"
    else
        fail "a CA bundle outside \$HOME: $(cat "$TMP/outside.log")"
    fi
fi
unset FAKE_OP_CA

# --- --env-only -----------------------------------------------------------------------

reset
if OMNIROUTE_BACKUP_IDENTITY="$TMP/nope" restore envonly --env-only; then
    if [[ -f "$ENV_FILE" && -f "$CA_PATH" ]] && grep -qF 'notesPlain' "$FAKE/op.log" && ! grep -q '^docker' "$FAKE/calls.log"; then
        pass "--env-only on a machine with neither key nor archive writes .env and the CA bundle from 1Password, without Docker"
    else
        fail "--env-only: $(cat "$TMP/envonly.log")"
    fi
else
    fail "--env-only failed: $(cat "$TMP/envonly.log")"
fi
reset
mkdir -p "$OMNIROUTE_BACKUP_DIR"
cp "$F/v2.tar.age" "$OMNIROUTE_BACKUP_DIR/omniroute-20261005T033000Z.tar.age"
if restore envonly-archive --env-only && [[ ! -s "$FAKE/op.log" ]] && grep -qx "STORAGE_ENCRYPTION_KEY=$STORAGE_KEY" "$ENV_FILE"; then
    pass "--env-only prefers the newest archive's compose.env over 1Password"
else
    fail "--env-only with an archive: $(cat "$TMP/envonly-archive.log")"
fi
rm -rf "$OMNIROUTE_BACKUP_DIR"
reset
export FAKE_OP_FAIL=true
if OMNIROUTE_BACKUP_IDENTITY="$TMP/nope" restore envonly-fail --env-only; then
    fail "--env-only without any source exits 0"
else
    if grep -q "never new values" "$TMP/envonly-fail.log" && [[ ! -f "$ENV_FILE" ]]; then
        pass "--env-only with no source fails, and never invents a .env"
    else
        fail "--env-only with no source: $(cat "$TMP/envonly-fail.log")"
    fi
fi
unset FAKE_OP_FAIL

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-omniroute-restore] all checks passed" >&2
fi
exit "$EXIT_CODE"
