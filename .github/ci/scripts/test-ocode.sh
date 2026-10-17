#!/bin/bash
set -euo pipefail

# Tests the ocode fork-builder without bun, git or a real fork checkout: `git` and `bun` are
# stubs, the checkout is a fake directory whose `.git` exists, and the build fabricates the
# artifact the fork's build would emit. Covers the skip paths, the first build, the no-op
# rebuild, the rebuild on a new head and the rebuild that restores a missing binary.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-ocode] testing the ocode fork-builder..." >&2

pass() { echo "[test-ocode] PASS: $1" >&2; }
fail() { echo "[test-ocode] FAIL: $1" >&2; EXIT_CODE=1; }

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_linux-006-build-ocode.sh"

export HOME="$TMP/home"
mkdir -p "$HOME"

export CHECKOUT="$HOME/Development/github.com/opencode/opencode"
STUB="$TMP/stub"
mkdir -p "$STUB" "$CHECKOUT/.git"

# git stub: HEAD comes from the checkout's .git/HEAD file; log echoes a fake subject.
cat >"$STUB/git" <<'STUB'
#!/bin/bash
case "$*" in
    *"rev-parse"*) cat "${CHECKOUT:?}/.git/HEAD" ;;
    *"log"*) echo "fake0123 chore: fake fork commit" ;;
    *) echo "stub git: unexpected args: $*" >&2; exit 1 ;;
esac
STUB

# bun stub: records every invocation and fabricates the artifact under --outdir.
cat >"$STUB/bun" <<'STUB'
#!/bin/bash
echo "$*" >>"${BUN_CALLS:?}"
for arg in "$@"; do
    case "$arg" in
        --outdir=*) out="${arg#--outdir=}" ;;
    esac
done
mkdir -p "$out/cli-linux-x64/bin"
printf '#!/bin/bash\necho fake ocode\n' >"$out/cli-linux-x64/bin/opencode"
chmod +x "$out/cli-linux-x64/bin/opencode"
STUB
chmod +x "$STUB/git" "$STUB/bun"

export BUN_CALLS="$TMP/bun-calls"
: >"$BUN_CALLS"

run_script() { (cd "$TMP" && PATH="$STUB:$PATH" bash "$SCRIPT") >"$TMP/out" 2>&1; echo $? >"$TMP/rc"; }
rc() { cat "$TMP/rc"; }
calls() { wc -l <"$BUN_CALLS"; }

# 1) No checkout: skip, no binary, no marker, and the message says why.
rm -rf "$CHECKOUT"
run_script
[ "$(rc)" -eq 0 ] || fail "skip without checkout must exit 0"
[ ! -e "$HOME/.local/bin/ocode" ] || fail "skip must not install a binary"
grep -q "no fork checkout" "$TMP/out" || fail "skip must say why"
pass "no checkout skips"

# 2) First build installs an executable ocode and records the head.
mkdir -p "$CHECKOUT/.git"
printf 'fake0123\n' >"$CHECKOUT/.git/HEAD"
run_script
[ "$(rc)" -eq 0 ] || fail "first build must exit 0"
[ -x "$HOME/.local/bin/ocode" ] || fail "first build must install an executable ocode"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake0123" ] || fail "marker must hold the built head"
[ "$(calls)" -eq 1 ] || fail "first build must invoke bun once"
pass "first build installs ocode and records the head"

# 3) Unchanged head: no rebuild.
run_script
[ "$(rc)" -eq 0 ] || fail "unchanged apply must exit 0"
[ "$(calls)" -eq 1 ] || fail "unchanged head must not rebuild"
pass "unchanged head does not rebuild"

# 4) New head: rebuild and move the marker.
printf 'fake4567\n' >"$CHECKOUT/.git/HEAD"
run_script
[ "$(rc)" -eq 0 ] || fail "rebuild must exit 0"
[ "$(calls)" -eq 2 ] || fail "new head must rebuild"
[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake4567" ] || fail "marker must move with the head"
pass "new head rebuilds"

# 5) Binary deleted but head unchanged: the rebuild restores it.
rm -f "$HOME/.local/bin/ocode"
run_script
[ "$(rc)" -eq 0 ] || fail "missing binary must rebuild"
[ -x "$HOME/.local/bin/ocode" ] || fail "missing binary must be reinstalled"
pass "missing binary is reinstalled"

# 6) bun missing: skip, even with a checkout present. Isolate from the real bun on the
#    machine by running with only the stub directory on PATH.
mv "$STUB/bun" "$STUB/bun.away"
(cd "$TMP" && PATH="$STUB" /bin/bash "$SCRIPT") >"$TMP/out" 2>&1
echo $? >"$TMP/rc"
[ "$(rc)" -eq 0 ] || fail "missing bun must skip"
grep -q "bun is not on PATH" "$TMP/out" || fail "missing bun must say why"
mv "$STUB/bun.away" "$STUB/bun"
pass "missing bun skips"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-ocode] all ocode fork-builder tests passed" >&2
fi
exit $EXIT_CODE
