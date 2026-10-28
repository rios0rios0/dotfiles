#!/bin/bash
set -euo pipefail

# Tests the home-secrets backup without Windows or a real key: the sources live under a scratch
# root, `cmd.exe` and `wslpath` stand in for Windows' side of the personal OneDrive, and `age` runs
# for real against a throwaway key, so a broken encryption round-trip fails here and not on the day
# of a restore. The script is rendered from its template first; the installer is rendered and run
# with a WSL kernel file and with a bare-metal one, and a stub systemctl records what it would do.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-secrets-backup] testing the home-secrets backup script and its installer..." >&2

pass() { echo "[test-secrets-backup] PASS: $1" >&2; }
fail() { echo "[test-secrets-backup] FAIL: $1" >&2; EXIT_CODE=1; }

TEMPLATE="$REPO_ROOT/dot_local/bin/executable_secrets-backup.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-018-setup-secrets-backup.sh.tmpl"
SERVICE="$REPO_ROOT/dot_config/systemd/user/secrets-backup.service"
TIMER="$REPO_ROOT/dot_config/systemd/user/secrets-backup.timer"

for tool in age age-keygen chezmoi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-secrets-backup] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF

SCRIPT="$TMP/secrets-backup"
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

# --- The backup script, against a scratch root and a throwaway key ------------

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
age-keygen -o "$HOME/.ssh/secrets-backup-key" 2>/dev/null
KEY="$HOME/.ssh/secrets-backup-key"

# The scratch root carries exactly the configured sources, plus a ~/.kube cache that must NOT be
# backed up (the sources name .kube/config and .kube/config-files, not .kube whole).
ROOT="$TMP/root"
mkdir -p "$ROOT/.john" "$ROOT/.sqlmap/output/box" "$ROOT/.kube/config-files" "$ROOT/.kube/cache"
printf 'cracked-secret-hash\n' > "$ROOT/.john/john.pot"
printf 'session\n' > "$ROOT/.sqlmap/output/box/session.sqlite"
printf 'apiVersion: v1\n' > "$ROOT/.kube/config"
chmod 600 "$ROOT/.kube/config"
printf 'context: extra\n' > "$ROOT/.kube/config-files/extra.yaml"
printf 'DISCOVERY CACHE, do not back up\n' > "$ROOT/.kube/cache/discovery"

export SECRETS_BACKUP_ROOT="$ROOT"
export SECRETS_BACKUP_DIR="$TMP/backups"
export SECRETS_BACKUP_KEEP=2
export SECRETS_BACKUP_MIRROR="$TMP/mirror"

mkdir -p "$TMP/stub"
# Windows' side of the personal OneDrive: cmd.exe answers %NAME% from FAKE_WIN_<NAME> and logs every
# variable asked for; wslpath maps C:\ under $FAKE_C. Both shadow the real ones on a WSL machine.
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
export PATH="$TMP/stub:$PATH"
export FAKE_C="$TMP/c" FAKE_CMD_LOG="$TMP/cmd.log"

ARCHIVE_GLOB='secrets-*.tar.age'

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
first="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | head -n 1)"
if [[ -n "$first" ]]; then
    pass "an archive appeared"
else
    fail "no archive appeared"
fi

# The archive decrypts and extracts to exactly the configured sources -- with the caches left out,
# and ~/.kube/config still mode 600.
mkdir -p "$TMP/verify"
if age -d -i "$KEY" "$first" 2>/dev/null | tar -x -p -C "$TMP/verify" -f -; then
    pass "the archive decrypts and extracts"
else
    fail "the archive does not decrypt with its own key"
fi
if [[ -f "$TMP/verify/.john/john.pot" && -f "$TMP/verify/.sqlmap/output/box/session.sqlite" &&
    -f "$TMP/verify/.kube/config" && -f "$TMP/verify/.kube/config-files/extra.yaml" ]]; then
    pass "the archive carries .john, .sqlmap, .kube/config and .kube/config-files"
else
    fail "the archive is missing one of the sources: $(cd "$TMP/verify" && find . -type f | sort | tr '\n' ' ')"
fi
if [[ ! -e "$TMP/verify/.kube/cache" ]]; then
    pass "the ~/.kube cache is not backed up"
else
    fail "the ~/.kube cache was backed up"
fi
if [[ "$(stat -c '%a' "$TMP/verify/.kube/config")" == 600 ]]; then
    pass "~/.kube/config keeps mode 600 through the round trip"
else
    fail "~/.kube/config came back mode $(stat -c '%a' "$TMP/verify/.kube/config")"
fi
if grep -q 'cracked-secret-hash' "$TMP/verify/.john/john.pot"; then
    pass "the archive round-trips the file bytes"
else
    fail "the archive content differs"
fi

# A missing source is skipped with a warning; the present ones still back up.
rm -rf "$TMP/root2"
mkdir -p "$TMP/root2/.john"
printf 'only john\n' > "$TMP/root2/.john/john.pot"
if SECRETS_BACKUP_ROOT="$TMP/root2" SECRETS_BACKUP_DIR="$TMP/backups2" SECRETS_BACKUP_MIRROR="" "$SCRIPT" 2>"$TMP/partial.log" &&
    find "$TMP/backups2" -maxdepth 1 -name "$ARCHIVE_GLOB" | grep -q . &&
    grep -q "does not exist, skipping" "$TMP/partial.log"; then
    pass "a missing source is skipped, and the present ones still back up"
else
    fail "a partially-present root did not back up what it has: $(cat "$TMP/partial.log")"
fi

# No source present at all: a no-op with a warning, no archive.
rm -rf "$TMP/root3"
mkdir -p "$TMP/root3"
if SECRETS_BACKUP_ROOT="$TMP/root3" SECRETS_BACKUP_DIR="$TMP/backups3" SECRETS_BACKUP_MIRROR="" "$SCRIPT" 2>"$TMP/none.log" &&
    ! find "$TMP/backups3" -maxdepth 1 -name "$ARCHIVE_GLOB" 2>/dev/null | grep -q . &&
    grep -q "none of the sources" "$TMP/none.log"; then
    pass "a root with no sources is a no-op with a warning"
else
    fail "a root with no sources did not no-op cleanly: $(cat "$TMP/none.log")"
fi

# The mirror: a byte-for-byte copy under the device's folder, no partial copy left.
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

# Retention keeps the newest SECRETS_BACKUP_KEEP archives here.
sleep 1; "$SCRIPT" >/dev/null 2>&1
sleep 1; "$SCRIPT" >/dev/null 2>&1
count="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" | wc -l)"
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

# Mirror retention: the newest MIRROR_KEEP, plus the newest of each of MIRROR_MONTHLY months, by the
# names; anything else stays.
mkdir -p "$TMP/mirror2/test-device"
for name in 20260101T034500Z 20260115T034500Z 20260201T034500Z 20260220T034500Z 20260301T034500Z \
    20260302T034500Z 20260303T034500Z; do
    printf 'old\n' > "$TMP/mirror2/test-device/secrets-$name.tar.age"
done
printf 'not ours\n' > "$TMP/mirror2/test-device/notes.txt"
if SECRETS_BACKUP_MIRROR="$TMP/mirror2" SECRETS_BACKUP_MIRROR_KEEP=2 SECRETS_BACKUP_MIRROR_MONTHLY=3 \
    "$SCRIPT" >/dev/null 2>&1; then
    new="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    left="$(find "$TMP/mirror2/test-device" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')"
    if [[ "$left" == "notes.txt secrets-20260220T034500Z.tar.age secrets-20260303T034500Z.tar.age $new " ]]; then
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
if SECRETS_BACKUP_MIRROR=onedrive-personal FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' \
    FAKE_WIN_OneDrive='C:\Users\Test\OneDrive - Work' "$SCRIPT" >/dev/null 2>"$TMP/onedrive.log"; then
    if find "$TMP/c/Users/Test/OneDrive/Backup/secrets/test-device" -name "$ARCHIVE_GLOB" | grep -q .; then
        pass "'onedrive-personal' copies to %OneDriveConsumer%\\Backup\\secrets\\<device>"
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
newest_before="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
sleep 1
if SECRETS_BACKUP_MIRROR=onedrive-personal FAKE_WIN_OneDrive='C:\Users\Test\OneDrive - Work' \
    "$SCRIPT" >/dev/null 2>"$TMP/noconsumer.log"; then
    fail "a missing personal OneDrive exits 0"
else
    newest_after="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    if grep -q "OneDriveConsumer" "$TMP/noconsumer.log" && [[ "$newest_after" != "$newest_before" ]]; then
        pass "a missing personal OneDrive fails the run, says why, and keeps the archive here"
    else
        fail "a missing personal OneDrive fails without keeping the archive or saying why: $(cat "$TMP/noconsumer.log")"
    fi
fi

# A mirror that cannot be written fails the run after the archive is kept.
printf 'a file, not a folder\n' > "$TMP/not-a-folder"
newest_before="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
sleep 1
if SECRETS_BACKUP_MIRROR="$TMP/not-a-folder" "$SCRIPT" >/dev/null 2>"$TMP/mirrorfail.log"; then
    fail "an unwritable mirror exits 0"
else
    newest_after="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name "$ARCHIVE_GLOB" -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
    if [[ "$newest_after" != "$newest_before" ]] && grep -q "stays in" "$TMP/mirrorfail.log"; then
        pass "an unwritable mirror fails the run after keeping the archive here"
    else
        fail "an unwritable mirror lost the archive or said nothing: $(cat "$TMP/mirrorfail.log")"
    fi
fi

# A missing identity fails the run, because silently not backing up is worse.
if SECRETS_BACKUP_IDENTITY="$TMP/nope" "$SCRIPT" >/dev/null 2>"$TMP/nokey.log"; then
    fail "a missing identity exits 0"
else
    pass "a missing identity fails the run"
fi
if grep -q "no age identity at" "$TMP/nokey.log"; then
    pass "the failure says what is missing"
else
    fail "the failure does not say what is missing"
fi

# A device name that cannot name a folder is refused before anything is written.
if SECRETS_BACKUP_DEVICE='../escape' "$SCRIPT" >/dev/null 2>&1; then
    fail "a device name with a path in it exits 0"
else
    pass "a device name with a path in it is refused"
fi

# A source that holds a symlink fails the backup: only regular files and directories are backed up,
# so a symlink can never ride into an archive a restore would then have to refuse.
rm -rf "$TMP/rootsym"
mkdir -p "$TMP/rootsym/.john"
ln -s /etc/passwd "$TMP/rootsym/.john/link"
if SECRETS_BACKUP_ROOT="$TMP/rootsym" SECRETS_BACKUP_DIR="$TMP/backupssym" SECRETS_BACKUP_MIRROR="" \
    "$SCRIPT" >/dev/null 2>"$TMP/symbackup.log"; then
    fail "a source holding a symlink backed up"
else
    if grep -q "symlink or a special file" "$TMP/symbackup.log" &&
        ! find "$TMP/backupssym" -name "$ARCHIVE_GLOB" 2>/dev/null | grep -q .; then
        pass "a source holding a symlink fails the backup, and writes no archive"
    else
        fail "a symlink source was not refused cleanly: $(cat "$TMP/symbackup.log")"
    fi
fi

# --- The installer: the WSL gate and the systemd handoff ---------------------

mkdir -p "$TMP/systemd" "$TMP/stubctl" "$TMP/emptyhome"
printf 'Linux version 5.15.167.4-microsoft-standard-WSL2 (x86_64)\n' > "$TMP/proc-version-wsl"
printf 'Linux version 6.8.0-45-generic (x86_64)\n' > "$TMP/proc-version-bare"
cat > "$TMP/stubctl/systemctl" <<'STUB_SYSTEMCTL'
#!/bin/bash
set -euo pipefail
if [[ -n "${SYSTEMCTL_LOG:-}" ]]; then
    echo "systemctl $*" >> "$SYSTEMCTL_LOG"
fi
exit 0
STUB_SYSTEMCTL
chmod +x "$TMP/stubctl/systemctl"
export SYSTEMCTL_LOG="$TMP/systemctl.log"
: > "$SYSTEMCTL_LOG"

render_installer() {
    local systemd_dir="$1" proc_version="$2"
    sed -e "s|/run/systemd/system|$systemd_dir|g" -e "s|/proc/version|$proc_version|g" "$INSTALLER" \
        | chezmoi execute-template --config "$TMP/chezmoi.yaml"
}

if rendered="$(render_installer "$TMP/systemd" "$TMP/proc-version-wsl")"; then
    if [[ "$rendered" == *"secrets-backup.timer"* ]]; then
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

script_digest="$(grep -oE 'script [0-9a-f]{64}' <<<"$rendered" | cut -d' ' -f2)"
if [[ "$script_digest" == "$(sha256sum "$SCRIPT" | cut -d' ' -f1)" ]]; then
    pass "the installer's script digest is the rendered script's"
else
    fail "the installer's script digest is not the rendered script's"
fi

printf '%s\n' "$rendered" > "$TMP/installer.sh"
chmod +x "$TMP/installer.sh"

export PATH="$TMP/stubctl:$PATH"
if FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' bash "$TMP/installer.sh" 2>"$TMP/install.log"; then
    pass "the installer runs where systemd is up"
else
    fail "the installer failed where systemd is up: $(cat "$TMP/install.log")"
fi
for call in "daemon-reload" "enable secrets-backup.timer" "start secrets-backup.timer"; do
    if grep -qF -- "$call" "$SYSTEMCTL_LOG"; then
        pass "the installer calls: $call"
    else
        fail "the installer never calls: $call"
    fi
done
if grep -qF "copied to $TMP/c/Users/Test/OneDrive/Backup/secrets/test-device" "$TMP/install.log"; then
    pass "the installer names where the archives are copied"
else
    fail "the installer does not name the mirror: $(cat "$TMP/install.log")"
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
    if grep -qx '#   systemd not running' "$TMP/installer-nosystemd.sh" &&
        bash "$TMP/installer-nosystemd.sh" 2>"$TMP/install-nosystemd.log" &&
        grep -q "WARN: systemd is not running" "$TMP/install-nosystemd.log"; then
        pass "without systemd the installer records it, exits 0 and says so"
    else
        fail "the installer mishandles a missing systemd: $(cat "$TMP/install-nosystemd.log" 2>/dev/null)"
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

# The units themselves.
if grep -q "ExecStart=%h/.local/bin/secrets-backup" "$SERVICE"; then
    pass "the service starts the backup script"
else
    fail "the service does not start the backup script"
fi
if grep -q "Persistent=true" "$TIMER" && grep -q "WantedBy=timers.target" "$TIMER"; then
    pass "the timer catches up on missed runs and is enabled at the timers target"
else
    fail "the timer is missing Persistent or WantedBy"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-secrets-backup] all checks passed" >&2
fi
exit "$EXIT_CODE"
