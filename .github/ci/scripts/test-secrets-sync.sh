#!/bin/bash
set -euo pipefail

# Tests the home-secrets sync without Windows or a real key: two devices, A and B, each a scratch
# folder of tools with a state folder of its own, share one hub folder, and age runs for real
# against a throwaway key. Each run is given its own time (SECRETS_SYNC_NOW), a day after the files
# were written, and the files whose order matters are stamped, so no assertion depends on how fast
# the runner is. The installer is rendered and run with a WSL kernel file and a bare-metal one, and
# a stub systemctl records what it would do.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-secrets-sync] testing the home-secrets sync and its installer..." >&2

pass() { echo "[test-secrets-sync] PASS: $1" >&2; }
fail() { echo "[test-secrets-sync] FAIL: $1" >&2; EXIT_CODE=1; }

TEMPLATE="$REPO_ROOT/dot_local/bin/executable_secrets-sync.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-020-setup-secrets-sync.sh.tmpl"
SERVICE="$REPO_ROOT/dot_config/systemd/user/secrets-sync.service"
TIMER="$REPO_ROOT/dot_config/systemd/user/secrets-sync.timer"

for tool in age age-keygen chezmoi flock openssl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-secrets-sync] SKIP: $tool is not installed" >&2
        exit 0
    fi
done

cat >"$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "test-device"
EOF

SCRIPT="$TMP/secrets-sync"
if chezmoi execute-template --config "$TMP/chezmoi.yaml" <"$TEMPLATE" >"$SCRIPT"; then
    chmod +x "$SCRIPT"
    pass "the sync script renders"
else
    fail "the sync script does not render"
    exit 1
fi
if [[ "$(basename "$TEMPLATE")" == executable_* ]]; then
    pass "the sync script deploys executable"
else
    fail "the sync script does not deploy executable"
fi

export HOME="$TMP/home"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
KEY="$HOME/.ssh/secrets-backup-key"
age-keygen -o "$KEY" 2>/dev/null
RECIPIENT="$(age-keygen -y "$KEY")"
HUB="$TMP/hub"

# The clock every run is given, a day after the files were written; each run moves it on by ten
# seconds, and LAST_RUN keeps the time the latest one was given.
CLOCK=$(( $(date +%s) + 86400 ))
LAST_RUN=0

# run <device> [args...]: runs the sync as a device, with its folder, state and name.
run() {
    local dev="$1"
    shift
    CLOCK=$((CLOCK + 10))
    LAST_RUN="$CLOCK"
    SECRETS_SYNC_NOW="$CLOCK" SECRETS_SYNC_ROOT="$TMP/$dev" SECRETS_SYNC_STATE="$TMP/state-$dev" \
        SECRETS_SYNC_DEVICE="$dev" SECRETS_SYNC_HUB="${RUN_HUB:-$HUB}" SECRETS_BACKUP_IDENTITY="$KEY" \
        "$SCRIPT" "$@"
}

# kubeconfig <file> <cluster> [<current-context>]: a kubeconfig for one cluster, as az writes them.
kubeconfig() {
    {
        printf 'apiVersion: v1\nclusters:\n- cluster:\n    server: https://%s.invalid\n  name: %s\n' "$2" "$2"
        printf 'contexts:\n- context:\n    cluster: %s\n    user: %s-user\n  name: %s\n' "$2" "$2" "$2"
        if [[ -n "${3:-}" ]]; then
            printf 'current-context: %s\n' "$3"
        fi
        printf 'kind: Config\nusers:\n- name: %s-user\n  user:\n    token: fixture-token-placeholder\n' "$2"
    } >"$1"
}

# stamp <epoch> <file>...: sets the files' modification time.
stamp() {
    local when="$1"
    shift
    touch -d "@$when" -- "$@"
}

# manifest_of <snapshot>: the manifest inside a snapshot in the hub.
manifest_of() {
    age -d -i "$KEY" "$1" | tar -xOf - manifest
}

A_KUBE="$TMP/A/.kube/config-files"
B_KUBE="$TMP/B/.kube/config-files"

# --- The command line --------------------------------------------------------------------------------

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
if SECRETS_BACKUP_IDENTITY="$TMP/nope" SECRETS_SYNC_HUB="$HUB" "$SCRIPT" >/dev/null 2>"$TMP/nokey.log"; then
    fail "a missing identity exits 0"
elif grep -q "no age identity at" "$TMP/nokey.log"; then
    pass "a missing identity fails the run, and says what is missing"
else
    fail "a missing identity fails without saying why: $(cat "$TMP/nokey.log")"
fi
if SECRETS_SYNC_HUB="" "$SCRIPT" 2>"$TMP/nohub.log" && grep -q "nothing to sync" "$TMP/nohub.log"; then
    pass "an empty hub syncs nothing and exits 0"
else
    fail "an empty hub did not no-op: $(cat "$TMP/nohub.log")"
fi
if SECRETS_SYNC_DEVICE='../escape' SECRETS_SYNC_HUB="$HUB" "$SCRIPT" >/dev/null 2>&1; then
    fail "a device name with a path in it exits 0"
else
    pass "a device name with a path in it is refused"
fi

# --- Two devices join --------------------------------------------------------------------------------

# given: A holds kubeconfigs one and two, B holds two -- the same cluster, another current-context --
# and three; each holds pot lines of its own and one they share; A holds an sqlmap target, B none
mkdir -p "$A_KUBE" "$B_KUBE" "$TMP/A/.john" "$TMP/B/.john" "$TMP/A/.sqlmap/output/box" "$TMP/B/.sqlmap"
kubeconfig "$A_KUBE/one.yaml" one one
kubeconfig "$A_KUBE/two.yaml" two two
kubeconfig "$B_KUBE/two.yaml" two elsewhere
kubeconfig "$B_KUBE/three.yaml" three three
printf 'hash-a:pass-a\nshared:pw\n' >"$TMP/A/.john/john.pot"
printf 'hash-b:pass-b\nshared:pw\n' >"$TMP/B/.john/john.pot"
printf 'session of box\n' >"$TMP/A/.sqlmap/output/box/session.sqlite"

# when
run A 2>"$TMP/join-a1.log" && run B 2>"$TMP/join-b.log" && run A 2>"$TMP/join-a2.log"
join_status=$?

# then
if [[ "$join_status" -eq 0 ]]; then
    pass "a first sync on each device succeeds"
else
    fail "a first sync failed: $(cat "$TMP/join-a1.log" "$TMP/join-b.log" "$TMP/join-a2.log")"
fi
for dev in A B; do
    if [[ "$(find "$TMP/$dev/.kube/config-files" -type f -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')" == "one.yaml three.yaml two.yaml " ]]; then
        pass "$dev holds every device's kubeconfigs after the join"
    else
        fail "$dev holds: $(find "$TMP/$dev/.kube/config-files" -type f -printf '%f ')"
    fi
done
if grep -qx 'current-context: two' "$A_KUBE/two.yaml" && grep -qx 'current-context: elsewhere' "$B_KUBE/two.yaml"; then
    pass "a kubeconfig that differs only in its current-context keeps each device's own"
else
    fail "the current-context of two.yaml crossed devices"
fi
if ! grep -q '^current-context:' "$B_KUBE/one.yaml" && cmp -s <(grep -v '^current-context:' "$A_KUBE/one.yaml") "$B_KUBE/one.yaml"; then
    pass "a kubeconfig new to a device arrives without the sender's current-context"
else
    fail "one.yaml arrived with A's current-context, or changed on the way"
fi
if [[ "$(cat "$TMP/A/.john/john.pot")" == $'hash-a:pass-a\nshared:pw\nhash-b:pass-b' &&
    "$(cat "$TMP/B/.john/john.pot")" == $'hash-b:pass-b\nshared:pw\nhash-a:pass-a' ]]; then
    pass "the pot files merge by line, each keeping its own lines first, in their order"
else
    fail "the pot files did not merge: A=$(tr '\n' '|' <"$TMP/A/.john/john.pot") B=$(tr '\n' '|' <"$TMP/B/.john/john.pot")"
fi
if [[ "$(cat "$TMP/B/.sqlmap/output/box/session.sqlite" 2>/dev/null)" == "session of box" ]]; then
    pass "an sqlmap target joins a device that had none, folder and all"
else
    fail "the sqlmap target did not reach B"
fi
if [[ ! -e "$TMP/state-A/conflicts" && ! -e "$TMP/state-B/conflicts" ]]; then
    pass "a join of matching copies keeps no conflicts"
else
    fail "a join kept conflicts: $(find "$TMP"/state-*/conflicts -type f)"
fi
if [[ -f "$HUB/kube/A.tar.age" && -f "$HUB/kube/B.tar.age" && -f "$HUB/john/A.tar.age" && -f "$HUB/sqlmap/B.tar.age" ]]; then
    pass "each device publishes one snapshot per tool, under the tool, by its own name"
else
    fail "the hub holds: $(cd "$HUB" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
fi
if ! find "$HUB" -name '*.tmp' | grep -q .; then
    pass "the hub holds no partial snapshot"
else
    fail "the hub holds a partial snapshot"
fi

# The MAC is HMAC-SHA256 under a key derived from the identity, computed without a command line:
# openssl, given that key on its own command line here, must agree with it.
mac_key="$(printf 'secrets-sync manifest key v1\n%s' "$(grep -m 1 '^AGE-SECRET-KEY-1' "$KEY")" | sha256sum | cut -c1-64)"
manifest_of "$HUB/kube/A.tar.age" >"$TMP/manifest"
head -n -1 "$TMP/manifest" >"$TMP/manifest.body"
expected="$(openssl dgst -sha256 -mac HMAC -macopt "hexkey:$mac_key" "$TMP/manifest.body" | awk '{print $NF}')"
if [[ "$(tail -n 1 "$TMP/manifest")" == "mac	$expected" ]]; then
    pass "the manifest's MAC is the HMAC-SHA256 openssl computes"
else
    fail "the manifest's MAC differs from openssl's: $(tail -n 1 "$TMP/manifest") vs $expected"
fi
if ! grep -q 'current-context' <(age -d -i "$KEY" "$HUB/kube/A.tar.age" | tar -xOf - data); then
    pass "no current-context is published"
else
    fail "a current-context reached the hub"
fi

# --- Nothing new, nothing written ------------------------------------------------------------------

# given
cp "$HUB/kube/A.tar.age" "$TMP/kube-a.before"
sed -i 's/^current-context: .*/current-context: one/' "$A_KUBE/two.yaml"

# when: a run with nothing new, but a current-context switched
run A 2>"$TMP/idle.log"

# then
if cmp -s "$TMP/kube-a.before" "$HUB/kube/A.tar.age"; then
    pass "a run with nothing new, a current-context switch included, rewrites no snapshot"
else
    fail "an idle run rewrote A's snapshot: $(cat "$TMP/idle.log")"
fi

# --- A change reaches the other device -----------------------------------------------------------

# given: B moves cluster two
sed -i 's|https://two.invalid|https://two-moved.invalid|' "$B_KUBE/two.yaml"
stamp "$((CLOCK + 1))" "$B_KUBE/two.yaml"

# when
run B 2>/dev/null && run A 2>"$TMP/edit.log"

# then
if grep -q 'two-moved.invalid' "$A_KUBE/two.yaml" && grep -qx 'current-context: one' "$A_KUBE/two.yaml"; then
    pass "a change reaches the other device, which keeps its own current-context"
else
    fail "the change to two.yaml did not arrive whole: $(cat "$TMP/edit.log")"
fi
if grep -q 'took two.yaml from B' "$TMP/edit.log"; then
    pass "the run says what it took, and from where"
else
    fail "the run did not say what it took: $(cat "$TMP/edit.log")"
fi

# --- A delete reaches the other device -----------------------------------------------------------

# given
rm "$A_KUBE/one.yaml"

# when
run A 2>/dev/null && run B 2>"$TMP/delete.log"

# then
if [[ ! -e "$B_KUBE/one.yaml" ]] && grep -q 'deleted one.yaml, as A did' "$TMP/delete.log"; then
    pass "a delete reaches the other device"
else
    fail "one.yaml survived on B: $(cat "$TMP/delete.log")"
fi
if [[ ! -e "$TMP/state-B/conflicts" ]]; then
    pass "a delete of an unchanged copy keeps no conflict"
else
    fail "a delete of an unchanged copy kept a conflict"
fi

# --- Concurrent changes: the newest wins, and the other is kept ----------------------------------

# given: A changes three.yaml and publishes it; B, which never saw that, changes it later
sed -i 's|three.invalid|three-by-a.invalid|' "$A_KUBE/three.yaml"
stamp "$((CLOCK + 1))" "$A_KUBE/three.yaml"
run A 2>/dev/null
sed -i 's|three.invalid|three-by-b.invalid|' "$B_KUBE/three.yaml"
stamp "$((CLOCK + 5))" "$B_KUBE/three.yaml"

# when
run B 2>"$TMP/rival.log" && run A 2>/dev/null

# then
if grep -q 'three-by-b' "$A_KUBE/three.yaml" && grep -q 'three-by-b' "$B_KUBE/three.yaml"; then
    pass "of two concurrent changes, the newer wins on both devices"
else
    fail "the newer change to three.yaml did not win everywhere"
fi
if grep -rqs 'three-by-a' "$TMP/state-B/conflicts/kube" && grep -q 'kept theirs' "$TMP/rival.log"; then
    pass "the device whose change won keeps the concurrent one it beat"
else
    fail "A's concurrent change was lost: $(cat "$TMP/rival.log")"
fi

# given: both change two.yaml before either syncs; B's is newer and published first
sed -i 's|two-moved.invalid|two-by-a.invalid|' "$A_KUBE/two.yaml"
stamp "$((CLOCK + 1))" "$A_KUBE/two.yaml"
sed -i 's|two-moved.invalid|two-by-b.invalid|' "$B_KUBE/two.yaml"
stamp "$((CLOCK + 2))" "$B_KUBE/two.yaml"
run B 2>/dev/null

# when
run A 2>"$TMP/lost.log"

# then
if grep -q 'two-by-b' "$A_KUBE/two.yaml" && grep -rqs 'two-by-a' "$TMP/state-A/conflicts/kube" &&
    grep -q 'lost to a newer one from B' "$TMP/lost.log"; then
    pass "a local change that loses to a newer one is kept in the state folder's conflicts"
else
    fail "A's losing change to two.yaml was not kept: $(cat "$TMP/lost.log")"
fi

# --- A delete never wipes a change made since -----------------------------------------------------

# given: A deletes three.yaml; B changes it after A last synced, and only then do they sync
rm "$A_KUBE/three.yaml"
sed -i 's|three-by-b.invalid|three-again.invalid|' "$B_KUBE/three.yaml"
stamp "$((LAST_RUN + 5))" "$B_KUBE/three.yaml"

# when
run A 2>/dev/null && run B 2>/dev/null && run A 2>"$TMP/resurrect.log"

# then
if grep -q 'three-again' "$A_KUBE/three.yaml" 2>/dev/null && grep -q 'three-again' "$B_KUBE/three.yaml"; then
    pass "a delete loses to a change the deleting device never saw"
else
    fail "a delete wiped a concurrent change: $(cat "$TMP/resurrect.log")"
fi

# --- Lines: a delete, and a line added back -------------------------------------------------------

# given
sed -i '/^hash-b:/d' "$TMP/B/.john/john.pot"

# when
run B 2>/dev/null && run A 2>/dev/null

# then
if ! grep -q '^hash-b:' "$TMP/A/.john/john.pot" && grep -q '^hash-a:' "$TMP/A/.john/john.pot"; then
    pass "a line deleted on one device is deleted on the other"
else
    fail "the deleted line survived on A: $(tr '\n' '|' <"$TMP/A/.john/john.pot")"
fi

# given: A cracks the same hash again, after the delete
printf 'hash-b:pass-b\n' >>"$TMP/A/.john/john.pot"
stamp "$((CLOCK + 5))" "$TMP/A/.john/john.pot"

# when
run A 2>/dev/null && run B 2>/dev/null

# then
if grep -q '^hash-b:' "$TMP/B/.john/john.pot" && grep -q '^hash-b:' "$TMP/A/.john/john.pot"; then
    pass "a line added back after its delete comes back everywhere"
else
    fail "the line added back did not stay: A=$(tr '\n' '|' <"$TMP/A/.john/john.pot") B=$(tr '\n' '|' <"$TMP/B/.john/john.pot")"
fi

# --- The delete guard -------------------------------------------------------------------------------

# given: four kubeconfigs on both devices, three of which A then deletes
for name in four five six; do
    kubeconfig "$A_KUBE/$name.yaml" "$name"
done
run A 2>/dev/null && run B 2>/dev/null
rm "$A_KUBE/four.yaml" "$A_KUBE/five.yaml" "$A_KUBE/six.yaml"
cp "$HUB/kube/A.tar.age" "$TMP/kube-a.guarded"

# when
if run A 2>"$TMP/guard.log"; then
    guard_status=0
else
    guard_status=$?
fi

# then
if [[ "$guard_status" -ne 0 ]] && grep -q 'would delete 3 of' "$TMP/guard.log" &&
    cmp -s "$TMP/kube-a.guarded" "$HUB/kube/A.tar.age"; then
    pass "a run that would delete most of a tool's entries stops, says so, and publishes nothing"
else
    fail "the guard did not stop the mass delete: $(cat "$TMP/guard.log")"
fi
run B 2>/dev/null || true
if [[ -f "$B_KUBE/four.yaml" && -f "$B_KUBE/five.yaml" && -f "$B_KUBE/six.yaml" ]]; then
    pass "a stopped delete never reaches the other device"
else
    fail "a stopped delete reached B"
fi

# when: the deletes were meant
run A --allow-deletes 2>/dev/null && run B 2>"$TMP/allowed.log"

# then: the other device applies them without --allow-deletes of its own
if [[ ! -e "$B_KUBE/four.yaml" && ! -e "$B_KUBE/five.yaml" && ! -e "$B_KUBE/six.yaml" ]]; then
    pass "--allow-deletes lets the deletes through, and the other device applies them as they are"
else
    fail "the allowed deletes did not reach B: $(cat "$TMP/allowed.log")"
fi

# --- A vanished folder is not a delete --------------------------------------------------------------

# given
mv "$B_KUBE" "$TMP/b-kube-aside"

# when
if run B 2>"$TMP/vanish.log"; then
    vanish_status=0
else
    vanish_status=$?
fi

# then
if [[ "$vanish_status" -ne 0 ]] && grep -q 'is gone, though it held entries' "$TMP/vanish.log"; then
    pass "a tool folder that vanished stops the run instead of deleting everything"
else
    fail "a vanished folder was not stopped: $(cat "$TMP/vanish.log")"
fi
run A 2>/dev/null
if [[ -f "$A_KUBE/two.yaml" && -f "$A_KUBE/three.yaml" ]]; then
    pass "the other device keeps everything a vanished folder held"
else
    fail "A lost entries to B's vanished folder"
fi
mv "$TMP/b-kube-aside" "$B_KUBE"

# --- A device that starts over gets everything back ------------------------------------------------

# given: A's folder and state are gone, as on a reinstalled machine, but ~/.kube is there
rm -r "$A_KUBE" "$TMP/state-A"
mkdir -p "$A_KUBE"

# when
run A 2>"$TMP/rejoin.log"

# then
if [[ -f "$A_KUBE/two.yaml" && -f "$A_KUBE/three.yaml" ]]; then
    pass "a device that starts over joins again and takes everything back"
else
    fail "a fresh A did not get its kubeconfigs back: $(cat "$TMP/rejoin.log")"
fi

# --- What is not synced -------------------------------------------------------------------------------

# given: a symlink among the kubeconfigs on B, and a device without ~/.sqlmap
ln -s /etc/hostname "$B_KUBE/link.yaml"
mkdir -p "$TMP/C/.kube"

# when
run B 2>"$TMP/symlink.log" && run C 2>"$TMP/c.log"

# then
if grep -q 'skipping link.yaml, a symlink' "$TMP/symlink.log" && [[ ! -e "$TMP/C/.kube/config-files/link.yaml" ]]; then
    pass "a symlink is skipped with a warning, and never published"
else
    fail "the symlink was not skipped: $(cat "$TMP/symlink.log")"
fi
if grep -q '.sqlmap does not exist here, so it is not synced' "$TMP/c.log" && [[ ! -e "$HUB/sqlmap/C.tar.age" ]]; then
    pass "a tool whose folder a device does not have is not synced there"
else
    fail "C synced a tool it does not have: $(cat "$TMP/c.log")"
fi
rm "$B_KUBE/link.yaml"

# --- A dry run changes nothing -------------------------------------------------------------------------

# given: a device joining, with the hub full
mkdir -p "$TMP/D/.kube"

# when
run D --dry-run 2>"$TMP/dry.log"

# then
if grep -q 'would take two.yaml' "$TMP/dry.log" && [[ ! -e "$TMP/D/.kube/config-files" && ! -e "$TMP/state-D/kube" &&
    ! -e "$HUB/kube/D.tar.age" ]]; then
    pass "--dry-run says what it would take, and changes nothing"
else
    fail "--dry-run changed something or said nothing: $(cat "$TMP/dry.log")"
fi

# --- Snapshots that do not authenticate -----------------------------------------------------------

# forge <hub> <device> <mac key>: a kube snapshot of one kubeconfig, MAC'd with the key given and
# encrypted to this key's public recipient -- what anyone who can write to the OneDrive can make.
forge() {
    local dir="$TMP/forge/$2"
    rm -rf "$dir"
    mkdir -p "$dir/data" "$1/kube"
    kubeconfig "$dir/data/planted.yaml" planted
    stamp "$((CLOCK + 50))" "$dir/data/planted.yaml"
    {
        printf 'secrets-sync-manifest\t1\ntool\tkube\nmerge\tentries\ndevice\t%s\nwritten\t%s\n' "$2" "$CLOCK"
        printf 'r\tlive\t%s\t%s\tplanted.yaml\n' "$((CLOCK + 50))" "$(sha256sum <"$dir/data/planted.yaml" | cut -c1-64)"
    } >"$dir/manifest.body"
    { cat "$dir/manifest.body"; printf 'mac\t%s\n' "$(openssl dgst -sha256 -mac HMAC -macopt "hexkey:$3" "$dir/manifest.body" | awk '{print $NF}')"; } >"$dir/manifest"
    tar -C "$dir" -cf "$dir/snapshot.tar" manifest data
    age -e -r "$RECIPIENT" -o "$1/kube/$2.tar.age" "$dir/snapshot.tar"
}

# given: a genuine change from A, and beside it a snapshot encrypted to the public recipient but
# MAC'd without the private key
kubeconfig "$A_KUBE/seven.yaml" seven
run A 2>/dev/null
forge "$HUB" intruder "$(printf '%064d' 0)"

# when
if run B 2>"$TMP/planted.log"; then
    planted_status=0
else
    planted_status=$?
fi

# then
if [[ "$planted_status" -ne 0 && ! -e "$B_KUBE/planted.yaml" ]] && grep -q 'fails its authentication check' "$TMP/planted.log"; then
    pass "a planted snapshot is refused, nothing of it is written, and the run fails to say so"
else
    fail "a planted snapshot was not refused: $(cat "$TMP/planted.log")"
fi
if [[ -f "$B_KUBE/seven.yaml" ]]; then
    pass "a planted snapshot does not stop the sync with the genuine ones"
else
    fail "a planted snapshot stopped the sync with A: $(cat "$TMP/planted.log")"
fi
rm "$HUB/kube/intruder.tar.age"

# given: a snapshot encrypted to another key altogether
age-keygen -o "$TMP/other-key" 2>/dev/null
printf 'not ours\n' | age -e -r "$(age-keygen -y "$TMP/other-key")" -o "$HUB/kube/stranger.tar.age"

# when
if run B 2>"$TMP/stranger.log"; then
    stranger_status=0
else
    stranger_status=$?
fi

# then
if [[ "$stranger_status" -ne 0 ]] && grep -q 'encrypted to another key' "$TMP/stranger.log"; then
    pass "a snapshot encrypted to another key is refused, and the run fails to say so"
else
    fail "a snapshot for another key was not refused: $(cat "$TMP/stranger.log")"
fi
rm "$HUB/kube/stranger.tar.age"

# given: a snapshot MAC'd with the key derived from the identity, in a hub of its own
forge "$TMP/hub2" genuine "$mac_key"
mkdir -p "$TMP/E/.kube"

# when
RUN_HUB="$TMP/hub2" run E 2>"$TMP/genuine.log"

# then
if [[ -f "$TMP/E/.kube/config-files/planted.yaml" ]]; then
    pass "a snapshot with a MAC from the identity's key is taken, so openssl's HMAC and the sync's agree"
else
    fail "a genuinely MAC'd snapshot was refused: $(cat "$TMP/genuine.log")"
fi

# --- Deletes are forgotten after tombstoneDays -----------------------------------------------------

# given: A's snapshot remembers the deletes made above
if manifest_of "$HUB/kube/A.tar.age" | grep -q $'^r\tdead\t'; then
    pass "a delete is published as a tombstone"
else
    fail "A's snapshot holds no tombstone"
fi

# when: a run 400 days later
CLOCK=$((CLOCK + 400 * 86400))
run A 2>/dev/null

# then
if ! manifest_of "$HUB/kube/A.tar.age" | grep -q $'^r\tdead\t'; then
    pass "a tombstone older than tombstoneDays is forgotten"
else
    fail "a tombstone outlived tombstoneDays"
fi

# --- The personal OneDrive ----------------------------------------------------------------------------

mkdir -p "$TMP/stub"
# Windows' side of the personal OneDrive: cmd.exe answers %NAME% from FAKE_WIN_<NAME> and logs every
# variable asked for; wslpath maps C:\ under $FAKE_C.
cat >"$TMP/stub/cmd.exe" <<'STUB_CMD'
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
cat >"$TMP/stub/wslpath" <<'STUB_WSLPATH'
#!/bin/bash
path="${@: -1}"
path="${path//\\//}"
printf '%s\n' "${FAKE_C:?}/${path#C:/}"
STUB_WSLPATH
chmod +x "$TMP/stub/cmd.exe" "$TMP/stub/wslpath"
export FAKE_C="$TMP/c" FAKE_CMD_LOG="$TMP/cmd.log"
mkdir -p "$TMP/c/Users/Test/OneDrive" "$TMP/c/Users/Test/OneDrive - Work"
: >"$FAKE_CMD_LOG"

# when
if PATH="$TMP/stub:$PATH" RUN_HUB=onedrive-personal FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' \
    FAKE_WIN_OneDrive='C:\Users\Test\OneDrive - Work' run A 2>"$TMP/onedrive.log"; then
    onedrive_status=0
else
    onedrive_status=$?
fi

# then
if [[ "$onedrive_status" -eq 0 && -f "$TMP/c/Users/Test/OneDrive/Backup/sync/kube/A.tar.age" ]]; then
    pass "'onedrive-personal' syncs through %OneDriveConsumer%\\Backup\\sync\\<tool>"
else
    fail "'onedrive-personal' did not reach the personal OneDrive: $(cat "$TMP/onedrive.log")"
fi
if [[ -z "$(find "$TMP/c/Users/Test/OneDrive - Work" -mindepth 1)" ]] && ! grep -qx OneDrive "$FAKE_CMD_LOG"; then
    pass "%OneDrive% is never read, and the work account's folder stays empty"
else
    fail "the work OneDrive was read or written"
fi
if PATH="$TMP/stub:$PATH" RUN_HUB=onedrive-personal run A >/dev/null 2>"$TMP/noconsumer.log"; then
    fail "a missing personal OneDrive exits 0"
elif grep -q "OneDriveConsumer" "$TMP/noconsumer.log"; then
    pass "a missing personal OneDrive fails the run, and says why"
else
    fail "a missing personal OneDrive fails without saying why: $(cat "$TMP/noconsumer.log")"
fi

# --- The units ---------------------------------------------------------------------------------------------

if grep -qx 'ExecStart=%h/.local/bin/secrets-sync' "$SERVICE" && grep -qx 'Type=oneshot' "$SERVICE"; then
    pass "the service runs the sync once per start"
else
    fail "the service does not run ~/.local/bin/secrets-sync as a oneshot"
fi
if grep -qx 'OnCalendar=hourly' "$TIMER" && grep -qx 'Persistent=true' "$TIMER" && grep -qx 'WantedBy=timers.target' "$TIMER"; then
    pass "the timer runs hourly, catches up after the machine was off, and is enabled through timers.target"
else
    fail "the timer is not hourly, persistent and wanted by timers.target"
fi

# --- The installer: the WSL gate and the systemd handoff ---------------------------------------------

mkdir -p "$TMP/systemd" "$TMP/stubctl" "$TMP/emptyhome"
printf 'Linux version 5.15.167.4-microsoft-standard-WSL2 (x86_64)\n' >"$TMP/proc-version-wsl"
printf 'Linux version 6.8.0-45-generic (x86_64)\n' >"$TMP/proc-version-bare"
cat >"$TMP/stubctl/systemctl" <<'STUB_SYSTEMCTL'
#!/bin/bash
set -euo pipefail
if [[ -n "${SYSTEMCTL_LOG:-}" ]]; then
    echo "systemctl $*" >> "$SYSTEMCTL_LOG"
fi
exit 0
STUB_SYSTEMCTL
chmod +x "$TMP/stubctl/systemctl"
export SYSTEMCTL_LOG="$TMP/systemctl.log"
: >"$SYSTEMCTL_LOG"

render_installer() {
    sed -e "s|/run/systemd/system|$1|g" -e "s|/proc/version|$2|g" "$INSTALLER" |
        chezmoi execute-template --config "$TMP/chezmoi.yaml"
}

if rendered="$(render_installer "$TMP/systemd" "$TMP/proc-version-wsl")"; then
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

printf '%s\n' "$rendered" >"$TMP/installer.sh"
if PATH="$TMP/stubctl:$TMP/stub:$PATH" FAKE_WIN_OneDriveConsumer='C:\Users\Test\OneDrive' \
    bash "$TMP/installer.sh" 2>"$TMP/install.log"; then
    pass "the installer runs where systemd is up"
else
    fail "the installer failed where systemd is up: $(cat "$TMP/install.log")"
fi
for call in "daemon-reload" "enable secrets-sync.timer" "start secrets-sync.timer"; do
    if grep -qF -- "$call" "$SYSTEMCTL_LOG"; then
        pass "the installer calls: $call"
    else
        fail "the installer never calls: $call"
    fi
done
if grep -qF "meet in $TMP/c/Users/Test/OneDrive/Backup/sync/<tool>/, this one's as test-device.tar.age" "$TMP/install.log"; then
    pass "the installer names where the snapshots meet"
else
    fail "the installer does not name the hub: $(cat "$TMP/install.log")"
fi
if HOME="$TMP/emptyhome" PATH="$TMP/stubctl:$TMP/stub:$PATH" bash "$TMP/installer.sh" 2>"$TMP/install-keywarn.log"; then
    if grep -q "fetches it from 1Password (op://" "$TMP/install-keywarn.log"; then
        pass "the installer warns when the key is missing, and names the item"
    else
        fail "the installer does not warn when the key is missing"
    fi
else
    fail "the installer fails when the key is missing (it should only warn)"
fi

if rendered_nosystemd="$(render_installer "$TMP/no-systemd" "$TMP/proc-version-wsl")"; then
    printf '%s\n' "$rendered_nosystemd" >"$TMP/installer-nosystemd.sh"
    : >"$SYSTEMCTL_LOG"
    if grep -qx '#   systemd not running' "$TMP/installer-nosystemd.sh" &&
        PATH="$TMP/stubctl:$TMP/stub:$PATH" bash "$TMP/installer-nosystemd.sh" 2>"$TMP/install-nosystemd.log" &&
        grep -q 'systemd is not running' "$TMP/install-nosystemd.log" && [[ ! -s "$SYSTEMCTL_LOG" ]]; then
        pass "without systemd the installer warns, calls no systemctl, and exits 0"
    else
        fail "without systemd the installer did not stop cleanly: $(cat "$TMP/install-nosystemd.log")"
    fi
else
    fail "the installer failed to render without systemd"
fi

if rendered_bare="$(render_installer "$TMP/systemd" "$TMP/proc-version-bare")"; then
    printf '%s\n' "$rendered_bare" >"$TMP/installer-bare.sh"
    : >"$SYSTEMCTL_LOG"
    if PATH="$TMP/stubctl:$TMP/stub:$PATH" bash "$TMP/installer-bare.sh" 2>/dev/null && [[ ! -s "$SYSTEMCTL_LOG" ]]; then
        pass "off WSL the installer does nothing"
    else
        fail "off WSL the installer called systemctl or failed"
    fi
else
    fail "the installer failed to render for bare metal"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-secrets-sync] all home-secrets sync tests passed" >&2
fi

exit $EXIT_CODE
