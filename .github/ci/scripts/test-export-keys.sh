#!/bin/bash
set -euo pipefail

# Tests run_before_linux-005-export-private-key.sh.tmpl: the age keys it puts in ~/.ssh before
# every apply. The template is rendered with two throwaway identities in place of the real
# public keys, `op.exe` is a stub that serves those identities, and /proc/version is swapped for a
# file the cases write, so nothing here reaches 1Password and the WSL-only backup key is testable
# anywhere. Covers the silent pass while every key matches, the first fetch, replacing an older
# key (the SSH key the repository encrypted to before), a failed or wrong chezmoi key failing the
# apply without touching the file, a failed backup key only warning, the backup key staying off
# bare metal, ~/.ssh never being emptied, and the aisync key: fetched only when missing, never
# replaced, recognised without age-keygen's comment, and only warning when it cannot be fetched.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TEMPLATE="$REPO_ROOT/.chezmoiscripts/run_before_linux-005-export-private-key.sh.tmpl"
EXIT_CODE=0

pass() { echo "[test-export-keys] PASS: $1" >&2; }
fail() { echo "[test-export-keys] FAIL: $1" >&2; EXIT_CODE=1; }

echo "[test-export-keys] testing the age key export..." >&2

for tool in age-keygen chezmoi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-export-keys] SKIP: needs $tool" >&2
        exit 0
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Two identities standing in for the chezmoi key and the backup key, and the references the stub
# serves them under.
age-keygen -o "$TMP/chezmoi.id" 2>/dev/null
age-keygen -o "$TMP/backup.id" 2>/dev/null
age-keygen -o "$TMP/other.id" 2>/dev/null
age-keygen -o "$TMP/aisync.id" 2>/dev/null
CHEZMOI_REF="op://Private/test-chezmoi/private key"
BACKUP_REF="op://Private/test-backup/private key"
AISYNC_REF="op://Private/test-aisync/private key"
override="$(jq -nc --arg c "$(age-keygen -y "$TMP/chezmoi.id")" --arg b "$(age-keygen -y "$TMP/backup.id")" \
    --arg a "$(age-keygen -y "$TMP/aisync.id")" --arg cr "$CHEZMOI_REF" --arg br "$BACKUP_REF" --arg ar "$AISYNC_REF" \
    '{ageKeys: {chezmoi: {recipient: $c, privateKey: $cr}, omnirouteBackup: {recipient: $b, privateKey: $br},
      aisync: {recipient: $a, privateKey: $ar}}}')"
printf 'sourceDir: "%s"\n' "$REPO_ROOT" >"$TMP/chezmoi.yaml"
chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "$override" <"$TEMPLATE" |
    sed "s|/proc/version|$TMP/proc-version|" >"$TMP/export.sh"
bash -n "$TMP/export.sh" || fail "the rendered script is not valid bash"

# op.exe stub: logs each call; `signin` fails with $OP_SIGNIN_FAIL; `read` prints the identity file
# its reference maps to ($OP_SERVE_<KIND> overrides it), or fails for the reference in $OP_READ_FAIL.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/op.exe" <<'STUB'
#!/bin/bash
echo "$*" >>"$OP_LOG"
case "$1" in
    signin) exit "${OP_SIGNIN_FAIL:-0}" ;;
    read)
        ref=""
        for arg in "$@"; do
            case "$arg" in op://*) ref="$arg" ;; esac
        done
        [[ "$ref" == "${OP_READ_FAIL:-none}" ]] && exit 1
        case "$ref" in
            *test-chezmoi*) cat "${OP_SERVE_CHEZMOI:-$CHEZMOI_ID}" ;;
            *test-backup*) cat "${OP_SERVE_BACKUP:-$BACKUP_ID}" ;;
            *test-aisync*) cat "${OP_SERVE_AISYNC:-$AISYNC_ID}" ;;
            *) exit 1 ;;
        esac
        ;;
esac
STUB
chmod +x "$TMP/bin/op.exe"
export OP_LOG="$TMP/op.log" CHEZMOI_ID="$TMP/chezmoi.id" BACKUP_ID="$TMP/backup.id" AISYNC_ID="$TMP/aisync.id"

# reset <wsl|metal> [no-aisync]: a fresh home, with the bridge's socket standing in ~/.ssh and,
# unless asked otherwise, aisync's key already in place, so the cases about the other two keys see
# only those.
reset() {
    local kernel="$1" option="${2:-}"
    rm -rf "${TMP:?}/home" "$OP_LOG"
    mkdir -p "$TMP/home/.ssh"
    : >"$TMP/home/.ssh/agent.sock"
    if [[ "$option" != no-aisync ]]; then
        mkdir -p "$TMP/home/.config/aisync"
        cp "$AISYNC_ID" "$TMP/home/.config/aisync/key.txt"
    fi
    : >"$OP_LOG"
    if [[ "$kernel" == wsl ]]; then
        echo "Linux version 6.6.87.2-microsoft-standard-WSL2" >"$TMP/proc-version"
    else
        echo "Linux version 6.11.0-generic" >"$TMP/proc-version"
    fi
}

# run: the rendered script with the stub ahead of PATH and the sandbox as HOME.
run() {
    local rc=0
    HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$TMP/export.sh" >"$TMP/out" 2>&1 || rc=$?
    echo "$rc"
}
reads() { grep -c '^read' "$OP_LOG" || true; }
same() {
    local first="$1" second="$2"
    cmp -s "$first" "$second"
}
strays() { find "$TMP/home/.ssh" -name '*.??????' | wc -l; }

# given a WSL machine with neither key
reset wsl
# when / then: both are fetched, private, and exactly the identities 1Password holds
rc="$(run)"
if [[ "$rc" == 0 ]] && same "$TMP/home/.ssh/chezmoi" "$CHEZMOI_ID" && same "$TMP/home/.ssh/omniroute-backup-key" "$BACKUP_ID" &&
    [[ "$(stat -c '%a' "$TMP/home/.ssh/chezmoi")" == 600 && "$(stat -c '%a' "$TMP/home/.ssh/omniroute-backup-key")" == 600 ]] &&
    [[ "$(stat -c '%a' "$TMP/home/.ssh")" == 700 ]] && grep -q -- '--account my' "$OP_LOG"; then
    pass "a WSL machine without keys gets both, 0600 in a 0700 ~/.ssh"
else
    fail "first fetch on WSL: rc=$rc, $(cat "$TMP/out")"
fi
if [[ -e "$TMP/home/.ssh/agent.sock" ]]; then
    pass "the run leaves the rest of ~/.ssh alone"
else
    fail "the run deleted ~/.ssh/agent.sock"
fi

# given both keys already in place
# when / then: nothing reaches 1Password, not even a sign-in, and each key is reported as in place
: >"$OP_LOG"
rc="$(run)"
if [[ "$rc" == 0 && ! -s "$OP_LOG" && "$(grep -c 'is already in place' "$TMP/out")" == 3 ]]; then
    pass "matching keys are left alone without 1Password, each reported as already in place"
else
    fail "matching keys: rc=$rc, op calls: $(cat "$OP_LOG")"
fi

# given the older key -- an OpenSSH private key, as the repository used before
reset wsl
cp "$BACKUP_ID" "$TMP/home/.ssh/omniroute-backup-key"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' >"$TMP/home/.ssh/chezmoi"
# when / then: it is replaced, and the matching backup key is not fetched again
rc="$(run)"
if [[ "$rc" == 0 ]] && same "$TMP/home/.ssh/chezmoi" "$CHEZMOI_ID" && [[ "$(reads)" == 1 ]]; then
    pass "an older chezmoi key is replaced, and only it is fetched"
else
    fail "older key: rc=$rc, reads=$(reads), $(cat "$TMP/out")"
fi

# given the older key and a 1Password that cannot return the new one
reset wsl
printf 'old\n' >"$TMP/home/.ssh/chezmoi"
# when / then: the apply fails, the old file stays as it was, and nothing is left staged
rc="$(OP_READ_FAIL="$CHEZMOI_REF" run)"
if [[ "$rc" != 0 && "$(cat "$TMP/home/.ssh/chezmoi")" == old && "$(strays)" == 0 ]] && grep -q 'ERROR' "$TMP/out"; then
    pass "a failed chezmoi key read fails the apply and touches nothing"
else
    fail "failed read: rc=$rc, file=$(cat "$TMP/home/.ssh/chezmoi"), strays=$(strays)"
fi

# given a 1Password item that holds some other key
reset wsl
# when / then: the wrong key is refused rather than written
rc="$(OP_SERVE_CHEZMOI="$TMP/other.id" run)"
if [[ "$rc" != 0 && ! -e "$TMP/home/.ssh/chezmoi" && "$(strays)" == 0 ]]; then
    pass "a key for another recipient is refused"
else
    fail "wrong key: rc=$rc, $(cat "$TMP/out")"
fi

# given a backup key that cannot be fetched
reset wsl
# when / then: the chezmoi key still arrives, the apply goes on, and the warning names the item
rc="$(OP_READ_FAIL="$BACKUP_REF" run)"
if [[ "$rc" == 0 && ! -e "$TMP/home/.ssh/omniroute-backup-key" && "$(strays)" == 0 ]] &&
    same "$TMP/home/.ssh/chezmoi" "$CHEZMOI_ID" && grep -q "WARN: .*$BACKUP_REF" "$TMP/out"; then
    pass "a failed backup key only warns"
else
    fail "failed backup key: rc=$rc, $(cat "$TMP/out")"
fi

# given only the backup key missing, and a sign-in that fails
reset wsl
cp "$CHEZMOI_ID" "$TMP/home/.ssh/chezmoi"
# when / then: the apply goes on with a warning
rc="$(OP_SIGNIN_FAIL=1 run)"
if [[ "$rc" == 0 ]] && grep -q 'WARN: .*was not fetched' "$TMP/out"; then
    pass "a failed sign-in for the backup key alone only warns"
else
    fail "sign-in failure, backup key only: rc=$rc, $(cat "$TMP/out")"
fi

# given a bare-metal machine without keys
reset metal
# when / then: only the chezmoi key is fetched; the backups do not run there
rc="$(run)"
if [[ "$rc" == 0 && ! -e "$TMP/home/.ssh/omniroute-backup-key" && "$(reads)" == 1 ]]; then
    pass "bare metal gets the chezmoi key and no backup key"
else
    fail "bare metal: rc=$rc, reads=$(reads)"
fi

# given a machine without aisync's key
reset metal no-aisync
cp "$CHEZMOI_ID" "$TMP/home/.ssh/chezmoi"
# when / then: it is fetched into aisync's own directory, private, and nothing else is
rc="$(run)"
key="$TMP/home/.config/aisync/key.txt"
if [[ "$rc" == 0 && "$(reads)" == 1 ]] && same "$key" "$AISYNC_ID" &&
    [[ "$(stat -c '%a' "$key")" == 600 && "$(stat -c '%a' "${key%/*}")" == 700 ]]; then
    pass "a missing aisync key is fetched to ~/.config/aisync/key.txt, 0600 in a 0700 directory"
else
    fail "aisync key: rc=$rc, reads=$(reads), $(cat "$TMP/out")"
fi

# given another key where aisync's should be -- one aisync's own init may have generated
reset metal no-aisync
cp "$CHEZMOI_ID" "$TMP/home/.ssh/chezmoi"
mkdir -p "$TMP/home/.config/aisync"
cp "$TMP/other.id" "$TMP/home/.config/aisync/key.txt"
# when / then: it is kept, nothing is fetched, and the apply goes on with a warning
rc="$(run)"
if [[ "$rc" == 0 && ! -s "$OP_LOG" ]] && same "$TMP/home/.config/aisync/key.txt" "$TMP/other.id" &&
    grep -q 'WARN: .*key.txt holds another key' "$TMP/out"; then
    pass "another aisync key is kept and warned about, never replaced"
else
    fail "other aisync key: rc=$rc, op calls: $(cat "$OP_LOG"), $(cat "$TMP/out")"
fi

# given aisync's key without the comment age-keygen writes, as aisync can import one
reset metal no-aisync
cp "$CHEZMOI_ID" "$TMP/home/.ssh/chezmoi"
mkdir -p "$TMP/home/.config/aisync"
grep '^AGE-SECRET-KEY-1' "$AISYNC_ID" >"$TMP/home/.config/aisync/key.txt"
# when / then: age-keygen recognises it, and 1Password is left alone
rc="$(run)"
if [[ "$rc" == 0 && ! -s "$OP_LOG" ]] && grep -q 'aisync age key .* is already in place' "$TMP/out"; then
    pass "a key without age-keygen's comment is recognised"
else
    fail "bare aisync key: rc=$rc, op calls: $(cat "$OP_LOG"), $(cat "$TMP/out")"
fi

# given an aisync key that cannot be fetched, then a sign-in that fails
reset metal no-aisync
cp "$CHEZMOI_ID" "$TMP/home/.ssh/chezmoi"
# when / then: both only warn, and leave nothing staged
rc="$(OP_READ_FAIL="$AISYNC_REF" run)"
rc2="$(OP_SIGNIN_FAIL=1 run)"
if [[ "$rc" == 0 && "$rc2" == 0 && ! -e "$TMP/home/.config/aisync/key.txt" ]] &&
    [[ -z "$(find "$TMP/home/.config/aisync" -name 'key.txt.*')" ]] && grep -q 'WARN: .*key.txt was not fetched' "$TMP/out"; then
    pass "an aisync key that cannot be fetched only warns"
else
    fail "failed aisync key: rc=$rc/$rc2, $(cat "$TMP/out")"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-export-keys] all key export tests passed" >&2
fi
exit "$EXIT_CODE"
