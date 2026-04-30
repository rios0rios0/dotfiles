#!/data/data/com.termux/files/usr/bin/bash

# Creates the 'claude' wrapper for Claude Code's linux-arm64-musl build.
#
# Why a wrapper at all:
#   The musl binary needs PT_INTERP set to the Termux-local musl loader
#   (~/.local/musl-loader/lib/ld-musl-aarch64.so.1) via patchelf, and it
#   needs termux-etc-mount to redirect /etc/resolv.conf, /etc/hosts, and
#   the SSL CA bundle to their $PREFIX/etc/ equivalents at runtime. The
#   in-binary auto-updater does not know about either step, so it stays
#   disabled (DISABLE_AUTOUPDATER=1) and this wrapper handles updates
#   itself, in the background, with the correct patchelf step.
#
# Update model:
#   - check at most once per 24h (timestamp at $XDG_CACHE_HOME/claude-code/)
#   - the check runs in the background; claude startup never blocks on it
#   - new versions land in ~/.local/share/claude/versions/<X.Y.Z>/ and are
#     used on the next launch — the running session keeps its current build
#   - the most recent KEEP_VERSIONS=3 builds are retained; older are pruned
#
# Override knobs (read by the emitted wrapper):
#   CLAUDE_UPDATE_CHANNEL  channel suffix (default: stable; latest accepted)
#   CLAUDE_NO_AUTO_UPDATE  set to "1" to skip the background update check
#   CLAUDE_FORCE_VERSION   pin to a specific installed X.Y.Z directory

set -e

echo "[claude-wrapper] creating claude in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/claude" << 'CLAUDE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Wraps Claude Code (linux-arm64-musl) through termux-etc-mount with a
# non-blocking, rate-limited auto-update check. The in-binary updater
# stays disabled because it cannot patchelf the new binary.
#
# See ~/Development/github.com/rios0rios0/termux-etc-redirect/examples/claude-code.md
# for the full install path (musl loader seed + patchelf).

set -u

# Identity + HOME for libc fallbacks (Android /etc/passwd is sparse).
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

# Termux's bionic LD_PRELOAD shim cannot load into musl processes.
unset LD_PRELOAD

# Point Node at Termux's CA bundle so TLS works without /etc/ssl/certs.
export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"

# Disable the in-binary auto-updater. It would replace this wrapper with
# a symlink to a non-patchelf'd binary that crashes the kernel's PT_INTERP
# lookup with "No such file or directory". This wrapper handles updates
# itself, with the correct patchelf step, in the background.
export DISABLE_AUTOUPDATER=1

VERSIONS_DIR="$HOME/.local/share/claude/versions"
MUSL_LOADER="$HOME/.local/musl-loader/lib/ld-musl-aarch64.so.1"
GCS_BASE="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
CHANNEL="${CLAUDE_UPDATE_CHANNEL:-stable}"
STAMP_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code/last-update-check"
CHECK_INTERVAL_SECONDS=$((24 * 3600))
KEEP_VERSIONS=3
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

# Print the names of every entry in $VERSIONS_DIR that matches X.Y.Z, in
# ascending semver order. Filtering happens via a bash regex on the basename
# so non-semver entries (e.g. legacy ".patched-by-..." dirs) are ignored.
list_installed_versions() {
    local entry name
    local versions=()
    for entry in "$VERSIONS_DIR"/*; do
        [ -e "$entry" ] || continue
        name=${entry##*/}
        [[ "$name" =~ $SEMVER_REGEX ]] || continue
        versions+=("$name")
    done
    [ "${#versions[@]}" -eq 0 ] && return 0
    printf '%s\n' "${versions[@]}" | sort -V
}

run_update_check() {
    [ "${CLAUDE_NO_AUTO_UPDATE:-0}" = "1" ] && return 0
    command -v patchelf >/dev/null 2>&1 || return 0
    [ -f "$MUSL_LOADER" ] || return 0

    mkdir -p "$(dirname "$STAMP_FILE")" || return 0

    if [ -f "$STAMP_FILE" ]; then
        local last_check now
        last_check=$(stat -c '%Y' "$STAMP_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - last_check)) -lt "$CHECK_INTERVAL_SECONDS" ] && return 0
    fi

    local latest tmp
    latest=$(curl --max-time 10 -fsSL "$GCS_BASE/$CHANNEL" 2>/dev/null) || return 0
    [ -z "$latest" ] && return 0
    [[ "$latest" =~ $SEMVER_REGEX ]] || return 0
    touch "$STAMP_FILE"

    [ -x "$VERSIONS_DIR/$latest" ] && return 0

    mkdir -p "$VERSIONS_DIR" || return 0
    tmp=$(mktemp "$VERSIONS_DIR/.update-XXXXXX.tmp") || return 0
    if ! curl --max-time 120 -fsSL -o "$tmp" "$GCS_BASE/$latest/linux-arm64-musl/claude"; then
        rm -f "$tmp"; return 0
    fi
    chmod +x "$tmp"

    if ! patchelf --set-interpreter "$MUSL_LOADER" --remove-rpath "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 0
    fi

    mv "$tmp" "$VERSIONS_DIR/$latest"
    echo "[claude-wrapper] auto-updated to $latest (used on next launch)" >&2

    # Prune older versions, keeping the newest $KEEP_VERSIONS — non-semver
    # entries (e.g. legacy ".patched-by-..." dirs) are intentionally ignored
    # by list_installed_versions and never pruned.
    local total
    total=$(list_installed_versions | wc -l)
    if [ "$total" -gt "$KEEP_VERSIONS" ]; then
        list_installed_versions \
            | head -n "$((total - KEEP_VERSIONS))" \
            | while IFS= read -r old; do rm -f "$VERSIONS_DIR/$old"; done
    fi
}

mkdir -p "$VERSIONS_DIR"

# Fire-and-forget background update check. Output goes to a logfile so the
# terminal stays clean, and any failure is silent — claude startup never
# blocks or fails because of an update issue.
LOGFILE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code/update.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
( run_update_check ) >> "$LOGFILE" 2>&1 &
disown 2>/dev/null || true

# Pin or pick newest installed version.
if [ -n "${CLAUDE_FORCE_VERSION:-}" ] && [ -x "$VERSIONS_DIR/$CLAUDE_FORCE_VERSION" ]; then
    CLAUDE_BIN="$CLAUDE_FORCE_VERSION"
else
    CLAUDE_BIN=$(list_installed_versions | tail -1)
fi

if [ -z "${CLAUDE_BIN:-}" ]; then
    echo "[claude-wrapper] ERROR: no Claude Code version installed in $VERSIONS_DIR" >&2
    echo "[claude-wrapper]        bootstrap with examples/claude-code.md in" >&2
    echo "[claude-wrapper]        rios0rios0/termux-etc-redirect, then re-run claude" >&2
    exit 1
fi

exec termux-etc-mount "$VERSIONS_DIR/$CLAUDE_BIN" "$@"
CLAUDE_EOF

chmod +x "$HOME/.local/bin/claude"

echo "[claude-wrapper] claude wrapper created successfully" >&2
