#!/bin/bash
set -euo pipefail

# Tests the OmniRoute backup feature without Docker, an OmniRoute stack or a real key: `docker`
# is a stub backed by a fake container directory, while `age` runs for real against a throwaway
# key, so a broken encryption round-trip fails here and not on the day of a restore. The
# installer is rendered and run with a WSL kernel file and with a bare-metal one, and a stub
# systemctl records what it would enable.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-omniroute-backup] testing the OmniRoute backup script and its installer..." >&2

pass() { echo "[test-omniroute-backup] PASS: $1" >&2; }
fail() { echo "[test-omniroute-backup] FAIL: $1" >&2; EXIT_CODE=1; }

SCRIPT="$REPO_ROOT/dot_local/bin/executable_omniroute-backup"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-013-setup-omniroute-backup.sh.tmpl"
SERVICE="$REPO_ROOT/dot_config/systemd/user/omniroute-backup.service"
TIMER="$REPO_ROOT/dot_config/systemd/user/omniroute-backup.timer"

for tool in age age-keygen chezmoi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-omniroute-backup] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

# --- The backup script, against a stub docker and a throwaway key ------------

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
age-keygen -o "$HOME/.ssh/omniroute-backup-key" 2>/dev/null
KEY="$HOME/.ssh/omniroute-backup-key"

FAKE_CONTAINER="$TMP/container"
mkdir -p "$FAKE_CONTAINER/app/data"
printf 'fake server env\n' > "$FAKE_CONTAINER/app/data/server.env"

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
            exit 1
        fi
        last=""
        for last in "$@"; do :; done
        if [[ "$last" == "dotfiles-omniroute-1" && "${FAKE_RUNNING:-true}" == "true" ]]; then
            echo "true"
        else
            echo "false"
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

export FAKE_CONTAINER PATH="$TMP/stub:$PATH"
export OMNIROUTE_BACKUP_DIR="$TMP/backups"
export OMNIROUTE_BACKUP_KEEP=2

# What a produced archive is called, named once so the counting around it cannot drift.
ARCHIVE_GLOB='omniroute-*.tar.age'

if [[ -x "$SCRIPT" ]]; then
    pass "the backup script is executable"
else
    fail "the backup script is not executable"
fi

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

if "$SCRIPT" 2>"$TMP/run1.log"; then
    pass "a first backup succeeds"
else
    fail "a first backup failed: $(cat "$TMP/run1.log")"
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
if [[ ! -e "$FAKE_CONTAINER/app/data/.omniroute-backup-snapshot.sqlite" ]]; then
    pass "the in-container snapshot was cleaned up"
else
    fail "the in-container snapshot was left behind"
fi
if list="$(age -d -i "$KEY" "$first" 2>/dev/null | tar -tf -)"; then
    if [[ "$list" == *"storage.sqlite"* && "$list" == *"server.env"* ]]; then
        pass "the archive decrypts and holds storage.sqlite and server.env"
    else
        fail "the archive is missing files: $list"
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

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
EOF

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

printf '%s\n' "$rendered" > "$TMP/installer.sh"
chmod +x "$TMP/installer.sh"

export PATH="$TMP/stubctl:$PATH"
if bash "$TMP/installer.sh" 2>"$TMP/install.log"; then
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
