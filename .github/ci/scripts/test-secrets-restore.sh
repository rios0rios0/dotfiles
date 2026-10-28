#!/bin/bash
set -euo pipefail

# Tests the home-secrets restore without a real key: a throwaway age key stands in, the backup
# script produces a real archive to restore, and planted archives -- which anyone could make, since
# the recipient is public -- prove the allowlist refuses anything outside the configured sources or
# escaping them before a single file is written.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-secrets-restore] testing the home-secrets restore script..." >&2

pass() { echo "[test-secrets-restore] PASS: $1" >&2; }
fail() { echo "[test-secrets-restore] FAIL: $1" >&2; EXIT_CODE=1; }

BACKUP_TEMPLATE="$REPO_ROOT/dot_local/bin/executable_secrets-backup.tmpl"
RESTORE_TEMPLATE="$REPO_ROOT/dot_local/bin/executable_secrets-restore.tmpl"

for tool in age age-keygen chezmoi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-secrets-restore] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF

BACKUP="$TMP/secrets-backup"
RESTORE="$TMP/secrets-restore"
if chezmoi execute-template --config "$TMP/chezmoi.yaml" < "$BACKUP_TEMPLATE" > "$BACKUP" &&
    chezmoi execute-template --config "$TMP/chezmoi.yaml" < "$RESTORE_TEMPLATE" > "$RESTORE"; then
    chmod +x "$BACKUP" "$RESTORE"
    pass "the backup and restore scripts render"
else
    fail "the scripts do not render"
    exit 1
fi
if [[ "$(basename "$RESTORE_TEMPLATE")" == executable_* ]]; then
    pass "the restore script deploys executable"
else
    fail "the restore script does not deploy executable"
fi

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
age-keygen -o "$HOME/.ssh/secrets-backup-key" 2>/dev/null
KEY="$HOME/.ssh/secrets-backup-key"

# A source tree, and a real archive of it from the backup script (no mirror).
SRC="$TMP/src"
mkdir -p "$SRC/.john" "$SRC/.sqlmap/output/box" "$SRC/.kube/config-files"
printf 'cracked\n' > "$SRC/.john/john.pot"
printf 'session\n' > "$SRC/.sqlmap/output/box/session.sqlite"
printf 'apiVersion: v1\n' > "$SRC/.kube/config"
chmod 600 "$SRC/.kube/config"
printf 'extra\n' > "$SRC/.kube/config-files/extra.yaml"

export SECRETS_BACKUP_DIR="$TMP/backups"
SECRETS_BACKUP_ROOT="$SRC" SECRETS_BACKUP_MIRROR="" "$BACKUP" >/dev/null 2>"$TMP/backup.log" ||
    { fail "could not produce an archive to restore: $(cat "$TMP/backup.log")"; exit 1; }
ARCHIVE="$(find "$SECRETS_BACKUP_DIR" -maxdepth 1 -name 'secrets-*.tar.age' | head -n 1)"
[[ -n "$ARCHIVE" ]] || { fail "no archive to restore"; exit 1; }

export SECRETS_BACKUP_MIRROR=""

# --list shows the archive.
if "$RESTORE" --list 2>/dev/null | grep -qF "$ARCHIVE"; then
    pass "--list shows the archive"
else
    fail "--list does not show the archive"
fi

# Without a terminal and without --yes, the restore refuses to touch anything.
if "$RESTORE" </dev/null >/dev/null 2>"$TMP/noyes.log"; then
    fail "a restore without --yes and no terminal exits 0"
else
    grep -q "no terminal to ask on" "$TMP/noyes.log" && pass "without --yes and no terminal it refuses" ||
        fail "the refusal does not say why: $(cat "$TMP/noyes.log")"
fi

# A clean restore into an empty root brings every source back, with ~/.kube/config still 600.
DEST="$TMP/dest"
mkdir -p "$DEST"
if SECRETS_RESTORE_ROOT="$DEST" "$RESTORE" --yes >/dev/null 2>"$TMP/restore.log"; then
    pass "a restore into an empty root succeeds"
else
    fail "a restore failed: $(cat "$TMP/restore.log")"
fi
if [[ -f "$DEST/.john/john.pot" && -f "$DEST/.sqlmap/output/box/session.sqlite" &&
    -f "$DEST/.kube/config" && -f "$DEST/.kube/config-files/extra.yaml" ]]; then
    pass "every configured source is restored"
else
    fail "a source is missing after restore: $(cd "$DEST" && find . -type f | sort | tr '\n' ' ')"
fi
if [[ "$(stat -c '%a' "$DEST/.kube/config")" == 600 ]]; then
    pass "~/.kube/config is restored mode 600"
else
    fail "~/.kube/config restored as mode $(stat -c '%a' "$DEST/.kube/config")"
fi

# A source whose folder already exists is left alone by default, overwritten with --force.
printf 'LOCAL, keep me\n' > "$DEST/.john/john.pot"
if SECRETS_RESTORE_ROOT="$DEST" "$RESTORE" --yes 2>"$TMP/skip.log" &&
    grep -q 'LOCAL, keep me' "$DEST/.john/john.pot" && grep -q "leaving it" "$TMP/skip.log"; then
    pass "an existing source is left alone without --force"
else
    fail "an existing source was overwritten without --force: $(cat "$TMP/skip.log")"
fi
if SECRETS_RESTORE_ROOT="$DEST" "$RESTORE" --yes --force >/dev/null 2>&1 &&
    grep -q 'cracked' "$DEST/.john/john.pot"; then
    pass "--force overwrites an existing source"
else
    fail "--force did not overwrite"
fi

# A planted archive naming something outside the sources is refused before anything is written.
PLANT="$TMP/plant"
mkdir -p "$PLANT/.ssh"
printf 'stolen\n' > "$PLANT/.ssh/id_evil"
tar -C "$PLANT" -cf - .ssh/id_evil | age -e -i "$KEY" -o "$TMP/planted-outside.tar.age"
mkdir -p "$TMP/dest2"
if SECRETS_RESTORE_ROOT="$TMP/dest2" "$RESTORE" --yes "$TMP/planted-outside.tar.age" >/dev/null 2>"$TMP/plant1.log"; then
    fail "a planted archive naming .ssh/ was restored"
else
    if grep -q "outside the configured sources" "$TMP/plant1.log" && [[ ! -e "$TMP/dest2/.ssh" ]]; then
        pass "a planted archive naming .ssh/ is refused, and nothing is written"
    else
        fail "a planted archive was mishandled: $(cat "$TMP/plant1.log")"
    fi
fi

# A planted archive with an absolute path is refused too.
tar -P -cf - /etc/hostname 2>/dev/null | age -e -i "$KEY" -o "$TMP/planted-abs.tar.age"
if SECRETS_RESTORE_ROOT="$TMP/dest3" "$RESTORE" --yes "$TMP/planted-abs.tar.age" >/dev/null 2>"$TMP/plant2.log"; then
    fail "a planted archive with an absolute path was restored"
else
    grep -q "outside the configured sources or escapes them" "$TMP/plant2.log" &&
        pass "a planted archive with an absolute path is refused" ||
        fail "the absolute-path refusal is unclear: $(cat "$TMP/plant2.log")"
fi

# A planted archive whose entry is a symlink -- its name under a source, so the name check passes --
# is refused by the type check before anything is extracted. This is the escape the name allowlist
# alone cannot see: a `.john` symlink to `.ssh` would let a later member write through it.
PLANT_SYM="$TMP/plantsym"
mkdir -p "$PLANT_SYM"
ln -s .ssh "$PLANT_SYM/.john"
tar -C "$PLANT_SYM" -cf - .john | age -e -i "$KEY" -o "$TMP/planted-symlink.tar.age"
if SECRETS_RESTORE_ROOT="$TMP/destsym" "$RESTORE" --yes "$TMP/planted-symlink.tar.age" >/dev/null 2>"$TMP/sym.log"; then
    fail "a planted archive with a symlink entry was restored"
else
    if grep -q "symlink or a special file" "$TMP/sym.log" && [[ ! -e "$TMP/destsym/.john" ]]; then
        pass "a planted symlink entry is refused, and nothing is written"
    else
        fail "a planted symlink was mishandled: $(cat "$TMP/sym.log")"
    fi
fi

# A missing identity fails before anything is read.
if SECRETS_RESTORE_ROOT="$TMP/dest4" SECRETS_BACKUP_IDENTITY="$TMP/nope" "$RESTORE" --yes >/dev/null 2>"$TMP/nokey.log"; then
    fail "a missing identity exits 0"
else
    grep -q "no age identity at" "$TMP/nokey.log" && pass "a missing identity fails with a clear message" ||
        fail "the missing-identity message is unclear: $(cat "$TMP/nokey.log")"
fi

# --device reads another device's folder in the mirror.
mkdir -p "$TMP/mirror/other-device"
cp "$ARCHIVE" "$TMP/mirror/other-device/"
if SECRETS_BACKUP_MIRROR="$TMP/mirror" "$RESTORE" --device other-device --list 2>/dev/null |
    grep -qF "other-device"; then
    pass "--device lists another device's archives from the mirror"
else
    fail "--device does not read the mirror folder"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-secrets-restore] all checks passed" >&2
fi
exit "$EXIT_CODE"
