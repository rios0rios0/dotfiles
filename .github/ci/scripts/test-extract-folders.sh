#!/bin/bash
set -euo pipefail

# Exercises .chezmoiscripts/run_once_after_linux-001-extract-compressed-folders.sh against a
# sandboxed $HOME. It looked for archive names the folder watcher no longer writes, so it never
# restored anything and warned four times on every first apply: these cases pin the names and
# layouts it reads, that a folder already there is left alone, that a failure leaves nothing
# half-restored behind, and that a machine with nothing to restore hears nothing.
#
# `pkill` is stubbed on PATH, so the running watcher it stops is a recorded call.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_once_after_linux-001-extract-compressed-folders.sh"
EXIT_CODE=0
CASE_INDEX=0

echo "[test-extract-folders] testing the restore of archived folders..." >&2

if [ ! -f "$SCRIPT" ]; then
    echo "[test-extract-folders] FAIL: script not found at $SCRIPT" >&2
    exit 1
fi

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

pass() { echo "[test-extract-folders] PASS: $1" >&2; }
fail() { echo "[test-extract-folders] FAIL: $1" >&2; EXIT_CODE=1; }

check() {
    local description="$1"
    local condition="$2"

    if [ "$condition" = "true" ]; then
        pass "$description"
    else
        fail "$description"
    fi
}

mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/pkill" <<'EOF'
#!/bin/bash
echo "$*" >> "$PKILL_LOG"
exit 1
EOF
chmod +x "$SANDBOX/bin/pkill"

new_case() {
    CASE_INDEX=$((CASE_INDEX + 1))
    CASE_HOME="$SANDBOX/case-$CASE_INDEX"
    mkdir -p "$CASE_HOME"
    export PKILL_LOG="$CASE_HOME/pkill.log"
}

run_script() {
    OUTPUT=$(HOME="$CASE_HOME" PATH="$SANDBOX/bin:$PATH" bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
}

# Archives a folder the way the watcher does: "<folder>.tar" beside it, holding the folder itself,
# then removes the folder, as on a machine that only has the archive. `z` gzips it, as the archive
# in the repository is.
archive_folder() {
    local dir="$1"
    local compression="${2:-}"

    tar "-c${compression}f" "$dir.tar" -C "$(dirname "$dir")" "$(basename "$dir")"
    rm -rf "$dir"
}

staging_left() {
    [ -n "$(find "$CASE_HOME" -name '*.extract.*' -print -quit)" ] && echo true || echo false
}

# --- nothing to restore: no output, which is what every first apply printed four warnings for --
new_case
mkdir -p "$CASE_HOME/.histdb" "$CASE_HOME/.john" "$CASE_HOME/.sqlmap" "$CASE_HOME/.kube"
run_script
check "exits 0 when no folder has an archive" "$([ "$RC" -eq 0 ] && echo true || echo false)"
check "stays silent when no folder has an archive" "$([ -z "$OUTPUT" ] && echo true || echo false)"
check "leaves the watcher running when nothing was restored" "$([ ! -s "$PKILL_LOG" ] && echo true || echo false)"

# --- the repository's archive: gzipped, ~/.kube/config-files.tar ------------------------------
new_case
mkdir -p "$CASE_HOME/.kube/config-files/nested"
echo "cluster-a" > "$CASE_HOME/.kube/config-files/cluster-a"
echo "cluster-b" > "$CASE_HOME/.kube/config-files/nested/cluster-b"
archive_folder "$CASE_HOME/.kube/config-files" z
run_script
check "exits 0 after restoring from a gzipped archive" "$([ "$RC" -eq 0 ] && echo true || echo false)"
check "restores ~/.kube/config-files beside its archive" \
      "$([ "$(cat "$CASE_HOME/.kube/config-files/cluster-a" 2>/dev/null)" = "cluster-a" ] && echo true || echo false)"
check "restores nested files too" \
      "$([ "$(cat "$CASE_HOME/.kube/config-files/nested/cluster-b" 2>/dev/null)" = "cluster-b" ] && echo true || echo false)"
check "does not nest the folder inside itself" \
      "$([ ! -e "$CASE_HOME/.kube/config-files/config-files" ] && echo true || echo false)"
check "says which folder it restored" \
      "$(grep -q "restored \"$CASE_HOME/.kube/config-files\"" <<<"$OUTPUT" && echo true || echo false)"
check "leaves no staging directory behind" "$([ "$(staging_left)" = false ] && echo true || echo false)"
check "stops the running watcher so the next shell watches the restored folder" \
      "$(grep -q "$CASE_HOME/.scripts/linux-toolbox-watch-compress-folders.sh" "$PKILL_LOG" 2>/dev/null && echo true || echo false)"

# --- the watcher's own archive: plain tar ------------------------------------------------------
new_case
mkdir -p "$CASE_HOME/.john"
echo "pot" > "$CASE_HOME/.john/john.pot"
archive_folder "$CASE_HOME/.john"
run_script
check "restores from an uncompressed archive" \
      "$([ "$RC" -eq 0 ] && [ "$(cat "$CASE_HOME/.john/john.pot" 2>/dev/null)" = "pot" ] && echo true || echo false)"

# ~/.histdb is no longer one of the watched folders: Atuin keeps the shell history. An archive an
# older watcher left behind is not unpacked.
new_case
mkdir -p "$CASE_HOME/.histdb"
echo "history" > "$CASE_HOME/.histdb/zsh-history.db"
archive_folder "$CASE_HOME/.histdb"
run_script
check "leaves an old ~/.histdb.tar alone" \
      "$([ "$RC" -eq 0 ] && [ ! -e "$CASE_HOME/.histdb" ] && [ -z "$OUTPUT" ] && echo true || echo false)"

# --- a folder that already exists is left as it is ---------------------------------------------
new_case
mkdir -p "$CASE_HOME/.kube/config-files"
echo "old" > "$CASE_HOME/.kube/config-files/cluster-a"
echo "only in the archive" > "$CASE_HOME/.kube/config-files/cluster-b"
archive_folder "$CASE_HOME/.kube/config-files"
mkdir -p "$CASE_HOME/.kube/config-files"
echo "newer" > "$CASE_HOME/.kube/config-files/cluster-a"
run_script
check "exits 0 when the folder already exists" "$([ "$RC" -eq 0 ] && echo true || echo false)"
check "keeps a file newer than the archive" \
      "$([ "$(cat "$CASE_HOME/.kube/config-files/cluster-a")" = "newer" ] && echo true || echo false)"
check "adds nothing from the archive to an existing folder" \
      "$([ ! -e "$CASE_HOME/.kube/config-files/cluster-b" ] && echo true || echo false)"
check "stays silent when the folder already exists" "$([ -z "$OUTPUT" ] && echo true || echo false)"

# --- a damaged archive fails the run and leaves nothing behind --------------------------------
new_case
mkdir -p "$CASE_HOME/.kube"
echo "not an archive" > "$CASE_HOME/.kube/config-files.tar"
run_script
check "exits non-zero when an archive cannot be extracted, so the next apply retries" \
      "$([ "$RC" -ne 0 ] && echo true || echo false)"
check "warns about the archive it could not extract" \
      "$(grep -q "WARN: could not restore \"$CASE_HOME/.kube/config-files\"" <<<"$OUTPUT" && echo true || echo false)"
check "creates no folder from a damaged archive" "$([ ! -e "$CASE_HOME/.kube/config-files" ] && echo true || echo false)"
check "leaves no staging directory behind a damaged archive" "$([ "$(staging_left)" = false ] && echo true || echo false)"

# An archive of the folder's contents rather than of the folder (the 2025 watcher's `-C dir .`)
# has no top-level folder to move into place.
new_case
mkdir -p "$CASE_HOME/.john"
echo "pot" > "$CASE_HOME/.john/john.pot"
tar -cf "$CASE_HOME/.john.tar" -C "$CASE_HOME/.john" .
rm -rf "$CASE_HOME/.john"
run_script
check "exits non-zero when the archive does not hold the folder" "$([ "$RC" -ne 0 ] && echo true || echo false)"
check "creates no folder from an archive that does not hold it" "$([ ! -e "$CASE_HOME/.john" ] && echo true || echo false)"
check "leaves no staging directory behind such an archive" "$([ "$(staging_left)" = false ] && echo true || echo false)"

# --- one failure does not stop the folders after it --------------------------------------------
new_case
mkdir -p "$CASE_HOME/.kube" "$CASE_HOME/.sqlmap/output"
echo "not an archive" > "$CASE_HOME/.kube/config-files.tar"
echo "session" > "$CASE_HOME/.sqlmap/output/session"
archive_folder "$CASE_HOME/.sqlmap"
run_script
check "restores the folders after a failed one" \
      "$([ "$(cat "$CASE_HOME/.sqlmap/output/session" 2>/dev/null)" = "session" ] && echo true || echo false)"
check "still exits non-zero for the failed one" "$([ "$RC" -ne 0 ] && echo true || echo false)"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-extract-folders] all archived folder tests passed" >&2
fi

exit $EXIT_CODE
