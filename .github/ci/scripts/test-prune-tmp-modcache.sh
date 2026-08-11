#!/bin/bash
set -euo pipefail

# Exercises .chezmoiscripts/run_after_android-005-prune-tmp-modcache.sh. This
# script calls `rm -rf` unattended on every apply, so the $TMPDIR safety rail,
# the refusal to delete a live cache, and the no-op-when-clean behaviour are
# covered explicitly.
#
# The script is invoked through `bash` rather than executed, because its shebang
# points at Termux's bash and CI runs on Linux.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_android-005-prune-tmp-modcache.sh"
EXIT_CODE=0
CASE_INDEX=0

echo "[test-prune-tmp-modcache] testing \$TMPDIR module cache pruning..." >&2

if [ ! -f "$SCRIPT" ]; then
    echo "[test-prune-tmp-modcache] FAIL: script not found at $SCRIPT" >&2
    exit 1
fi

SANDBOX=$(mktemp -d)
# The fixtures deliberately contain read-only directories, so restore write
# permission before cleaning up or the trap cannot remove them either.
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null || true; rm -rf "$SANDBOX"' EXIT

pass() { echo "[test-prune-tmp-modcache] PASS: $1" >&2; }
fail() { echo "[test-prune-tmp-modcache] FAIL: $1" >&2; EXIT_CODE=1; }

check() {
    local description="$1"
    local condition="$2"

    if [ "$condition" = "true" ]; then
        pass "$description"
    else
        fail "$description"
    fi
}

# Builds a leaked Go module cache with Go's real permissions: 0400 files inside
# 0500 directories, which cannot be unlinked until the parent is writable again.
make_cache() {
    local root="$1"

    mkdir -p "$root/pkg/mod/github.com/foo@v1.0.0/sub"
    echo "package foo" > "$root/pkg/mod/github.com/foo@v1.0.0/sub/foo.go"
    chmod 0400 "$root/pkg/mod/github.com/foo@v1.0.0/sub/foo.go"
    chmod 0500 "$root/pkg/mod/github.com/foo@v1.0.0/sub" \
               "$root/pkg/mod/github.com/foo@v1.0.0"
}

new_case() {
    CASE_INDEX=$((CASE_INDEX + 1))
    CASE_DIR="$SANDBOX/case-$CASE_INDEX"
    CASE_TMP="$CASE_DIR/tmp"
    mkdir -p "$CASE_TMP"
}

# --- the fixture must actually reproduce the failure it guards against --------
new_case
make_cache "$CASE_TMP/proj/.go"
if rm -rf "$CASE_TMP/proj/.go/pkg/mod" 2>/dev/null && [ ! -d "$CASE_TMP/proj/.go/pkg/mod" ]; then
    fail "fixture reproduces an undeletable cache (plain rm -rf should fail)"
else
    pass "fixture reproduces an undeletable cache (plain rm -rf fails)"
fi

# --- removes the cache, keeps everything else --------------------------------
new_case
make_cache "$CASE_TMP/proj/.go"
mkdir -p "$CASE_TMP/proj/.go/bin"
echo "binary" > "$CASE_TMP/proj/.go/bin/gotestsum"

if TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1; then
    pass "exits 0 after pruning a cache"
else
    fail "exits 0 after pruning a cache"
fi
check "removes a read-only module cache under \$TMPDIR" \
      "$([ ! -d "$CASE_TMP/proj/.go/pkg/mod" ] && echo true || echo false)"
check "leaves a sibling bin/ untouched" \
      "$([ -f "$CASE_TMP/proj/.go/bin/gotestsum" ] && echo true || echo false)"

# --- refuses to delete the live cache ----------------------------------------
new_case
make_cache "$CASE_TMP/live"

if GOMODCACHE="$CASE_TMP/live/pkg/mod" TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1; then
    check "refuses to remove the active \$GOMODCACHE" \
          "$([ -d "$CASE_TMP/live/pkg/mod" ] && echo true || echo false)"
else
    fail "refuses to remove the active \$GOMODCACHE (script errored)"
fi

# The rail must key on the directory, not on how it was spelled. Each of these
# names the same cache as the one `find` reports, so a raw string comparison
# would fail open and delete it.
new_case
make_cache "$CASE_TMP/live"
GOMODCACHE="$CASE_TMP/live/pkg/mod/" TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1 || true
check "refuses when \$GOMODCACHE carries a trailing slash" \
      "$([ -d "$CASE_TMP/live/pkg/mod" ] && echo true || echo false)"

new_case
make_cache "$CASE_TMP/live"
ln -sfn "$CASE_TMP/live" "$CASE_TMP/live-link"
GOMODCACHE="$CASE_TMP/live-link/pkg/mod" TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1 || true
check "refuses when \$GOMODCACHE reaches the cache through a symlink" \
      "$([ -d "$CASE_TMP/live/pkg/mod" ] && echo true || echo false)"

new_case
make_cache "$CASE_TMP/live"
GOMODCACHE="$CASE_TMP/live/pkg/mod/../mod" TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1 || true
check "refuses when \$GOMODCACHE contains a '..' component" \
      "$([ -d "$CASE_TMP/live/pkg/mod" ] && echo true || echo false)"

# --- does not escape $TMPDIR through a symlink -------------------------------
new_case
mkdir -p "$CASE_DIR/outside/pkg/mod"
echo "precious" > "$CASE_DIR/outside/pkg/mod/precious.txt"
ln -sfn "$CASE_DIR/outside" "$CASE_TMP/escape"

TMPDIR="$CASE_TMP" bash "$SCRIPT" >/dev/null 2>&1 || true
check "does not follow a symlink out of \$TMPDIR" \
      "$([ -f "$CASE_DIR/outside/pkg/mod/precious.txt" ] && echo true || echo false)"

# --- quiet no-ops -------------------------------------------------------------
new_case
output=$(TMPDIR="$CASE_TMP" bash "$SCRIPT" 2>&1) && rc=0 || rc=$?
check "exits 0 when there is nothing to prune" "$([ "$rc" -eq 0 ] && echo true || echo false)"
check "stays silent when there is nothing to prune" "$([ -z "$output" ] && echo true || echo false)"

new_case
if TMPDIR="$CASE_DIR/does-not-exist" bash "$SCRIPT" >/dev/null 2>&1; then
    pass "exits 0 when \$TMPDIR does not exist"
else
    fail "exits 0 when \$TMPDIR does not exist"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-prune-tmp-modcache] all module cache pruning tests passed" >&2
fi

exit $EXIT_CODE
