#!/bin/bash
set -euo pipefail

# Exercises dot_local/bin/executable_xclip and dot_local/bin/executable_clipshot,
# the Termux shim that lets Claude Code's Ctrl+V attach a screenshot.
#
# The cases drive the *literal* command lines Claude Code issues rather than the
# shim's own interface, because that command table is the contract: a change to
# how the arguments are parsed, or to the exit status the pipeline sees, breaks
# paste even when the shim still behaves correctly when called by hand.
#
# The consumed marker makes checkImage and saveImage behave differently on the
# same state, and the freshness window is an off-by-one away from attaching a
# week-old capture, so both get explicit coverage in each direction.
#
# The scripts are invoked through `bash` rather than executed, because their
# shebang points at Termux's bash and CI runs on Linux.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SHIM="$REPO_ROOT/dot_local/bin/executable_xclip"
STAGER="$REPO_ROOT/dot_local/bin/executable_clipshot"
LIB="$REPO_ROOT/dot_local/lib/claude-clipboard.sh"
EXIT_CODE=0

echo "[test-clipboard-shim] testing the Claude Code clipboard shim..." >&2

for required in "$SHIM" "$STAGER" "$LIB"; do
    if [ ! -f "$required" ]; then
        echo "[test-clipboard-shim] FAIL: not found at $required" >&2
        exit 1
    fi
done

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

pass() { echo "[test-clipboard-shim] PASS: $1" >&2; }
fail() { echo "[test-clipboard-shim] FAIL: $1" >&2; EXIT_CODE=1; }

check() {
    if [ "$2" = "true" ]; then pass "$1"; else fail "$1"; fi
}

# A real 1x1 PNG, so the bytes the shim emits can be compared exactly.
PNG_FIXTURE="$SANDBOX/fixture.png"
base64 -d >"$PNG_FIXTURE" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
B64

# Launchers named exactly as the commands under test, so the literal pipelines
# below resolve them through PATH the way Claude Code's `shell: true` does.
FAKE_BIN="$SANDBOX/bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/bash\nexec bash %q "$@"\n' "$SHIM" >"$FAKE_BIN/xclip"
printf '#!/bin/bash\nexec bash %q "$@"\n' "$STAGER" >"$FAKE_BIN/clipshot"
chmod +x "$FAKE_BIN/xclip" "$FAKE_BIN/clipshot"

SHOTS="$SANDBOX/shots"
mkdir -p "$SHOTS"

export CLAUDE_CLIPBOARD_LIB="$LIB"
export CLAUDE_CLIPBOARD_DIRS="$SHOTS"
export XDG_CACHE_HOME="$SANDBOX/cache"
export PATH="$FAKE_BIN:$PATH"

CHECK_IMAGE='xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"'
SAVED="$SANDBOX/saved.png"

reset_state() {
    rm -rf "$XDG_CACHE_HOME" "$SHOTS" "$SAVED"
    mkdir -p "$SHOTS"
    unset CLAUDE_CLIPBOARD_REPEAT CLAUDE_CLIPBOARD_IMAGE
}

# Exit status of the checkImage pipeline exactly as Claude Code evaluates it.
clipboard_has_image() {
    /bin/sh -c "$CHECK_IMAGE" >/dev/null 2>&1
}

save_image() {
    /bin/sh -c "xclip -selection clipboard -t image/png -o > $(printf '%q' "$SAVED") 2>/dev/null"
}

add_shot() {
    cp "$PNG_FIXTURE" "$SHOTS/$1"
    touch -d "${2:-now}" "$SHOTS/$1"
}

# --- a fresh capture is offered, saved intact, then consumed -----------------
reset_state
add_shot "fresh.png"
clipboard_has_image && r=true || r=false
check "offers a screenshot taken inside the freshness window" "$r"

save_image && r=true || r=false
check "saveImage exits 0 for a fresh screenshot" "$r"

cmp -s "$SAVED" "$PNG_FIXTURE" && r=true || r=false
check "saveImage writes the image bytes unchanged" "$r"

clipboard_has_image && r=false || r=true
check "reports an empty clipboard on the second paste (consumed)" "$r"

# --- consumption is opt-out --------------------------------------------------
reset_state
add_shot "fresh.png"
save_image
CLAUDE_CLIPBOARD_REPEAT=1 clipboard_has_image && r=true || r=false
check "keeps re-offering the same image under CLAUDE_CLIPBOARD_REPEAT" "$r"
unset CLAUDE_CLIPBOARD_REPEAT

# --- the freshness window, in both directions --------------------------------
reset_state
add_shot "old.png" "2 hours ago"
clipboard_has_image && r=false || r=true
check "ignores a capture older than CLAUDE_CLIPBOARD_MAX_AGE" "$r"

CLAUDE_CLIPBOARD_MAX_AGE=99999 clipboard_has_image && r=true || r=false
check "offers that same capture when the window is widened" "$r"

# --- checkImage must not consume, or the saveImage that follows attaches nothing
reset_state
add_shot "fresh.png"
clipboard_has_image
save_image && r=true || r=false
check "saveImage still succeeds after checkImage ran first" "$r"

# --- clipshot stages what the window excludes --------------------------------
reset_state
add_shot "old.png" "2 hours ago"
clipshot >/dev/null 2>&1
clipboard_has_image && r=true || r=false
check "clipshot stages an image the freshness window excludes" "$r"

clipshot -c >/dev/null 2>&1
clipboard_has_image && r=false || r=true
check "clipshot -c clears the staged image" "$r"

# --- clipshot must agree with the shim about where to look -------------------
# Regression guard: clipshot once carried its own copy of the watch-dir list,
# so `-s` could report a different pick than Ctrl+V would attach.
reset_state
add_shot "fresh.png"
status_out=$(clipshot -s 2>&1 || true)
case "$status_out" in
    *"$SHOTS/fresh.png"*) r=true ;;
    *) r=false ;;
esac
check "clipshot -s honours CLAUDE_CLIPBOARD_DIRS like the shim does" "$r"

# --- the shared default list, which both consumers now read from one place ---
reset_state
unset CLAUDE_CLIPBOARD_DIRS
# shellcheck source=/dev/null
( . "$LIB"
  clipboard_set_watch_dirs
  printf '%s\n' "${CLAUDE_CLIPBOARD_WATCH_DIRS[@]}" ) >"$SANDBOX/dirs.txt"
grep -qx "$HOME/storage/pictures/Screenshot" "$SANDBOX/dirs.txt" && r=true || r=false
check "the default watch dirs keep the singular Screenshot variant" "$r"
grep -qx "$HOME/storage/downloads" "$SANDBOX/dirs.txt" && r=true || r=false
check "the default watch dirs keep the downloads folder" "$r"
export CLAUDE_CLIPBOARD_DIRS="$SHOTS"

# --- an explicit override outranks both the stage and the window -------------
reset_state
add_shot "old.png" "2 hours ago"
CLAUDE_CLIPBOARD_IMAGE="$SHOTS/old.png" clipboard_has_image && r=true || r=false
check "CLAUDE_CLIPBOARD_IMAGE ignores the freshness window" "$r"

# --- nothing to offer --------------------------------------------------------
reset_state
clipboard_has_image && r=false || r=true
check "reports an empty clipboard when no image exists" "$r"

/bin/sh -c 'xclip -selection clipboard -t application/pdf -o' >/dev/null 2>&1 && r=false || r=true
check "exits non-zero for a target it does not implement" "$r"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-clipboard-shim] all clipboard shim tests passed" >&2
fi
exit "$EXIT_CODE"
