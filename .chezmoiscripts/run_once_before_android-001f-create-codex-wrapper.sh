#!/data/data/com.termux/files/usr/bin/bash

# Creates the 'codex' wrapper for the Codex CLI's aarch64-unknown-linux-musl build.
#
# Why not npm:
#   `npm install -g @openai/codex` cannot work on Termux. The package is a Node
#   launcher plus one optional dependency per platform, and the platform package
#   (`@openai/codex-linux-arm64`) declares `os: linux` in its package.json while
#   Termux's Node reports `android`, so npm skips it silently and the launcher
#   throws "Missing optional dependency @openai/codex-linux-arm64". GitHub
#   publishes the same binary as a statically linked musl executable, which this
#   wrapper downloads and runs directly -- one process fewer than the npm launcher
#   (node -> codex), which matters under Android's phantom-process budget.
#
# Why a wrapper at all (every point verified on a device):
#   - DNS: musl reads /etc/resolv.conf through direct syscalls and Android has no
#     such file, so the binary runs through termux-etc-mount (Tier 3 of
#     rios0rios0/termux-etc-redirect), like the claude wrapper. Tier 2
#     (termux-etc-seccomp) is wrong here: its blanket SIGSYS -> ENOSYS rewrite
#     reaches every descendant, and codex spawns Node for tool calls (npm, test
#     runners), where it surfaces as `ENOSYS: lstat`.
#   - TLS: codex (rustls) probes the usual CA bundle paths with stat(), which
#     Tier 3 does not redirect (openat only), so it starts with an empty root
#     store and every handshake fails with "invalid peer certificate:
#     UnknownIssuer". SSL_CERT_FILE names Termux's bundle directly.
#   - Sandbox: codex's Linux sandbox is bubblewrap, which needs unprivileged user
#     namespaces; Android's SELinux policy denies them (`unshare(CLONE_NEWUSER)`
#     returns EINVAL, and bwrap cannot even read /proc/sys/kernel/overflowuid),
#     so `read-only` and `workspace-write` both panic before running a command.
#     The wrapper defaults `sandbox_mode` to `danger-full-access` -- the only
#     mode that works -- unless CODEX_WRAPPER_KEEP_SANDBOX=1. Approval prompts
#     are unaffected. Claude Code has no sandbox on Termux either.
#   - Tool-call shells: termux-etc-mount removes LD_PRELOAD before the exec, and
#     the shells codex spawns for tool calls therefore start without termux-exec,
#     so anything they exec directly through a `#!/usr/bin/env` shebang -- every
#     npm-installed CLI, `sentry` included -- dies with "bad interpreter". The
#     ~/.zshenv restore cannot reach them: codex never consults $SHELL. It reads
#     the password database (getpwuid_r), whose Termux entry is
#     `$PREFIX/bin/login`; that names no shell it knows, so the Linux fallback
#     order applies and `which bash` wins -- tool calls run
#     `$PREFIX/bin/bash -lc "<cmd>"`, which never sources ~/.zshenv (verified on
#     a device: `LD_PRELOAD=unset`, no termux-exec in /proc/self/maps). So the
#     wrapper hands the parked value to codex's own shell environment policy
#     instead (`-c shell_environment_policy.set.LD_PRELOAD=...`), which is
#     applied to the environment tool commands are spawned with: the library is
#     mapped before the shell's first exec, whichever shell codex picks. Set
#     CODEX_WRAPPER_KEEP_LD_PRELOAD=1 to leave it alone.
#   - Updates: `codex update` refuses a manual install ("Could not detect the
#     Codex installation method"), so the wrapper handles them. Being static, the
#     binary needs no musl loader and no patchelf step, unlike Claude Code.
#   - Code Mode: codex resolves its Code Mode sidecar as a sibling of its own
#     executable, but ships it as a separate release asset
#     (codex-code-mode-host-<target>.tar.gz). Downloading only the codex asset
#     therefore leaves every version directory one file short, and codex reports
#     "failed to spawn code-mode host <dir>/codex-code-mode-host: host
#     executable was not found. Code mode will fail closed". Nothing surfaces
#     until a model actually asks for Code Mode, so this survived several
#     auto-updates unnoticed. install_version now fetches both assets into one
#     staging directory, and ensure_code_mode_host backfills a version that an
#     older wrapper revision installed without it -- on its own 24h stamp, since
#     releases that predate the asset can never succeed and would otherwise
#     re-download on every launch.
#
# Update model (same as the claude wrapper):
#   - check at most once per 24h (timestamp at $XDG_CACHE_HOME/codex-wrapper/)
#   - the check runs in the background; codex startup never blocks on it
#   - new versions land at ~/.local/share/codex/versions/<X.Y.Z>/codex, next to
#     the matching codex-code-mode-host, and are used on the next launch -- the
#     running session keeps its current build
#   - the most recent KEEP_VERSIONS=3 builds are retained; older are pruned,
#     along with staging directories a killed download left behind
#   - with nothing installed, the first launch downloads the latest release in
#     the foreground; that is how the Android dependency installer bootstraps it
#
# Override knobs (read by the emitted wrapper):
#   CODEX_WRAPPER_NO_AUTO_UPDATE  set to "1" to skip the background update check
#                                 (this also hands the startup update nag back to codex)
#   CODEX_WRAPPER_FORCE_VERSION   pin to a specific installed X.Y.Z
#   CODEX_WRAPPER_KEEP_SANDBOX    set to "1" to leave sandbox_mode alone
#   CODEX_WRAPPER_KEEP_LD_PRELOAD set to "1" to leave the tool shells' LD_PRELOAD alone

set -e

echo "[codex-wrapper] creating codex in ~/.local/bin..." >&2

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/codex" << 'CODEX_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Wraps the Codex CLI (aarch64-unknown-linux-musl, static) through
# termux-etc-mount with a non-blocking, rate-limited auto-update check.
# `codex update` cannot update a manual install, so this wrapper does.
#
# Generated by .chezmoiscripts/run_once_before_android-001f-create-codex-wrapper.sh
# in rios0rios0/dotfiles; that script's header explains every knob below.

set -u

# Identity + HOME for libc fallbacks (Android /etc/passwd is sparse).
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/data/data/com.termux/files/home}"

# Park Termux's bionic LD_PRELOAD shims in TERMUX_ETC_LD_PRELOAD instead of
# dropping them. The static codex binary ignores LD_PRELOAD either way, but
# termux-etc-mount removes it before the exec, and the bionic shells behind
# codex's tool calls need it back or every `#!/usr/bin/env` script they run
# fails with "bad interpreter". The parked value is what the OVERRIDES block
# below hands to those shells; parking it here as well keeps a wrapper and a
# redirector of different vintages agreeing, and still feeds the ~/.zshenv
# restore in any zsh that inherits the variable.
if [ -n "${LD_PRELOAD:-}" ]; then
    export TERMUX_ETC_LD_PRELOAD="$LD_PRELOAD"
fi
unset LD_PRELOAD

# Default PREFIX so `set -u` doesn't trip when launched from a non-Termux
# environment that didn't export it.
: "${PREFIX:=/data/data/com.termux/files/usr}"
export PREFIX

# rustls finds no CA roots on Android (see the generating script), so name
# Termux's bundle explicitly. A value already in the environment wins.
: "${SSL_CERT_FILE:=$PREFIX/etc/tls/cert.pem}"
export SSL_CERT_FILE

VERSIONS_DIR="$HOME/.local/share/codex/versions"
RELEASES_URL="https://github.com/openai/codex/releases"
ASSET="codex-aarch64-unknown-linux-musl"
# Code Mode's sidecar. Codex ships it as its own release asset and looks for it
# next to the codex binary, so a version directory holding only `codex` has Code
# Mode fail closed. See install_code_mode_host below.
HOST_ASSET="codex-code-mode-host-aarch64-unknown-linux-musl"
HOST_BIN="codex-code-mode-host"
STAMP_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/codex-wrapper/last-update-check"
LOGFILE="${XDG_CACHE_HOME:-$HOME/.cache}/codex-wrapper/update.log"
CHECK_INTERVAL_SECONDS=$((24 * 3600))
KEEP_VERSIONS=3
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

# HTTPS-only download, as the installer scripts do it: a redirect to plain
# HTTP is refused instead of followed.
download_https_only() {
    curl -fsSL --proto '=https' --proto-redir '=https' "$@"
}

# Print every installed version -- a directory under $VERSIONS_DIR named X.Y.Z
# that holds an executable `codex` -- in ascending semver order. Anything else
# under the directory (an interrupted download, a stray file) is ignored.
list_installed_versions() {
    local entry name
    local versions=()
    for entry in "$VERSIONS_DIR"/*/codex; do
        [ -f "$entry" ] && [ -x "$entry" ] || continue
        name=${entry%/codex}
        name=${name##*/}
        [[ "$name" =~ $SEMVER_REGEX ]] || continue
        versions+=("$name")
    done
    [ "${#versions[@]}" -eq 0 ] && return 0
    printf '%s\n' "${versions[@]}" | sort -V
}

# Resolve the newest release. GitHub answers /releases/latest with a redirect
# to the tag page, so one HEAD request that follows it suffices without the
# rate-limited API. Stable releases only: a pre-release never becomes "latest".
resolve_latest_version() {
    local location
    location=$(download_https_only --max-time 10 -I -o /dev/null -w '%{url_effective}' "$RELEASES_URL/latest") || return 1
    location=${location##*/rust-v}
    [[ "$location" =~ $SEMVER_REGEX ]] || return 1
    printf '%s\n' "$location"
}

# Download release X.Y.Z's Code Mode host into <dir>/codex-code-mode-host.
#
# Codex resolves the host as a sibling of its own executable -- with the binary
# missing it reports "failed to spawn code-mode host <dir>/codex-code-mode-host:
# host executable was not found" and Code Mode fails closed. The host is a
# separate release asset, so downloading only codex-<target>.tar.gz leaves every
# version directory one file short; nothing surfaces until a model actually asks
# for Code Mode, which is why this went unnoticed through several auto-updates.
#
# Deliberately non-fatal everywhere it is called: Code Mode is an optional
# feature, and a codex that runs without it beats no codex at all. A version left
# without the host is backfilled by ensure_code_mode_host on a later launch.
# Statically linked like codex itself, so no loader or patchelf step.
install_code_mode_host() {
    local version="$1" dir="$2" tmp

    tmp=$(mktemp -d "$VERSIONS_DIR/.host-XXXXXX") || return 1
    if ! download_https_only --max-time 600 -o "$tmp/$HOST_ASSET.tar.gz" \
            "$RELEASES_URL/download/rust-v$version/$HOST_ASSET.tar.gz" \
        || ! tar -xzf "$tmp/$HOST_ASSET.tar.gz" -C "$tmp" "$HOST_ASSET" \
        || ! mv "$tmp/$HOST_ASSET" "$tmp/$HOST_BIN" \
        || ! chmod +x "$tmp/$HOST_BIN"; then
        rm -rf "$tmp"
        return 1
    fi

    # Land it with a rename so a concurrent launch never sees a partial file;
    # the host takes no --version, so there is no run check to make here.
    if ! mv "$tmp/$HOST_BIN" "$dir/$HOST_BIN"; then
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
}

# Backfill the Code Mode host for an installed version that lacks it -- a version
# downloaded by a wrapper revision from before the host was fetched at all, or
# one whose host download failed. Cheap when nothing is missing: one file test.
#
# Rate-limited on a per-version stamp, and deliberately stamped BEFORE the
# attempt rather than after a success like run_update_check, because the two want
# opposite things. A missed release is worth retrying on the next launch; a
# version whose host asset does not exist at all can never succeed -- older
# releases publish no codex-code-mode-host asset (rust-v0.140.0, for one) and
# CODEX_WRAPPER_FORCE_VERSION can select one -- so stamping only on success would
# fork a doomed download on every single launch, forever. Per version rather than
# shared, so an upgrade still repairs itself on its first launch: a fresh version
# carries no stamp.
#
# A failure is logged rather than silent. The whole point of this function is a
# gap that surfaces only when a model asks for Code Mode, and an empty $LOGFILE
# beside a still-broken Code Mode would reproduce that one layer up.
ensure_code_mode_host() {
    local version="$1" dir="$VERSIONS_DIR/$1" stamp last now

    [ -x "$dir/$HOST_BIN" ] && return 0
    [ -x "$dir/codex" ] || return 0

    stamp="${STAMP_FILE%/*}/last-host-check-$version"
    if [ -f "$stamp" ]; then
        last=$(stat -c '%Y' "$stamp" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - last)) -lt "$CHECK_INTERVAL_SECONDS" ] && return 0
    fi
    mkdir -p "${stamp%/*}" 2>/dev/null && touch "$stamp"

    if install_code_mode_host "$version" "$dir"; then
        echo "[codex-wrapper] installed the Code Mode host for $version (used on next launch)" >&2
    else
        echo "[codex-wrapper] WARN: could not fetch the Code Mode host for $version; Code Mode stays unavailable, retrying in 24h" >&2
    fi
}

# Remove staging directories left by an install that died before its own cleanup
# could run. Every failure path in install_version and install_code_mode_host
# removes its mktemp directory, but a SIGKILL has no such path -- and on Android
# the phantom-process killer reaps background children exactly like the ones
# these downloads run in, leaving tens of megabytes behind (a 51 MB .install-*
# directory was found by hand on a device). Only this wrapper's own mktemp
# patterns are considered, and only past the check interval, so a download still
# running in a concurrent launch -- capped at --max-time 600 -- is never removed.
prune_stale_staging() {
    local entry now last
    now=$(date +%s)
    for entry in "$VERSIONS_DIR"/.install-* "$VERSIONS_DIR"/.host-*; do
        [ -d "$entry" ] || continue
        last=$(stat -c '%Y' "$entry" 2>/dev/null || echo "$now")
        if [ $((now - last)) -gt "$CHECK_INTERVAL_SECONDS" ]; then
            rm -rf "$entry"
            echo "[codex-wrapper] removed the stale staging directory $entry" >&2
        fi
    done
}

# Download release X.Y.Z to $VERSIONS_DIR/X.Y.Z/codex. The archive is unpacked
# in a temporary directory on the same filesystem and moved into place only
# after the binary has proven it runs, so list_installed_versions never sees a
# half-written version. Stderr is intentionally not suppressed: the callers
# either show it to the user (bootstrap) or send it to $LOGFILE (updater).
install_version() {
    local version="$1"
    local tmp

    mkdir -p "$VERSIONS_DIR" || return 1
    tmp=$(mktemp -d "$VERSIONS_DIR/.install-XXXXXX") || return 1

    if ! download_https_only --max-time 600 -o "$tmp/$ASSET.tar.gz" \
            "$RELEASES_URL/download/rust-v$version/$ASSET.tar.gz" \
        || ! tar -xzf "$tmp/$ASSET.tar.gz" -C "$tmp" "$ASSET" \
        || ! mv "$tmp/$ASSET" "$tmp/codex" \
        || ! chmod +x "$tmp/codex" \
        || ! "$tmp/codex" --version >/dev/null; then
        rm -rf "$tmp"
        return 1
    fi
    rm -f "$tmp/$ASSET.tar.gz"

    # Fetch the Code Mode host into the same staging directory so both binaries
    # become visible in one rename. Failure is not fatal (see the function):
    # ensure_code_mode_host retries it on a later launch.
    install_code_mode_host "$version" "$tmp" \
        || echo "[codex-wrapper] WARN: could not fetch the Code Mode host for $version; Code Mode stays unavailable until a later launch retries it" >&2

    # A concurrent launch may have installed the same version meanwhile; a
    # leftover directory without a working binary is replaced.
    if [ -x "$VERSIONS_DIR/$version/codex" ]; then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "${VERSIONS_DIR:?}/$version"
    mv "$tmp" "$VERSIONS_DIR/$version" || { rm -rf "$tmp"; return 1; }
}

# Keep the newest $KEEP_VERSIONS builds; non-semver entries are never touched.
prune_old_versions() {
    local total
    total=$(list_installed_versions | wc -l)
    if [ "$total" -gt "$KEEP_VERSIONS" ]; then
        list_installed_versions \
            | head -n "$((total - KEEP_VERSIONS))" \
            | while IFS= read -r old; do rm -rf "${VERSIONS_DIR:?}/$old"; done
    fi
}

run_update_check() {
    [ "${CODEX_WRAPPER_NO_AUTO_UPDATE:-0}" = "1" ] && return 0

    mkdir -p "$(dirname "$STAMP_FILE")" || return 0

    if [ -f "$STAMP_FILE" ]; then
        local last_check now
        last_check=$(stat -c '%Y' "$STAMP_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - last_check)) -lt "$CHECK_INTERVAL_SECONDS" ] && return 0
    fi

    local latest
    latest=$(resolve_latest_version) || return 0

    # Already on the latest published build -- record the successful check
    # and return without touching disk.
    if [ -x "$VERSIONS_DIR/$latest/codex" ]; then
        touch "$STAMP_FILE"
        return 0
    fi

    install_version "$latest" || return 0
    # The stamp is written only after the install succeeds so that a failed
    # download retries on the next launch instead of silently waiting out the
    # 24h interval with no new binary on disk.
    touch "$STAMP_FILE"
    echo "[codex-wrapper] auto-updated to $latest (used on next launch)" >&2
    prune_old_versions
}

mkdir -p "$VERSIONS_DIR" "$(dirname "$LOGFILE")" 2>/dev/null || true

if [ -z "$(list_installed_versions)" ]; then
    # Nothing installed yet: fetch the latest release in the foreground. This
    # is the path the Android dependency installer takes on a fresh machine.
    echo "[codex-wrapper] no Codex CLI version installed in $VERSIONS_DIR" >&2
    if ! latest=$(resolve_latest_version); then
        echo "[codex-wrapper] ERROR: could not resolve the latest release from $RELEASES_URL/latest" >&2
        exit 1
    fi
    echo "[codex-wrapper] downloading Codex CLI $latest ($ASSET plus the Code Mode host, about 115 MB)..." >&2
    if ! install_version "$latest"; then
        echo "[codex-wrapper] ERROR: failed to install Codex CLI $latest" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$STAMP_FILE")" 2>/dev/null && touch "$STAMP_FILE"
    echo "[codex-wrapper] installed Codex CLI $latest" >&2
    BOOTSTRAPPED=1
fi

# Pin or pick the newest installed version. CODEX_WRAPPER_FORCE_VERSION must
# name an installed version; otherwise the newest one is used, with a warning.
if [ -n "${CODEX_WRAPPER_FORCE_VERSION:-}" ]; then
    if [ -x "$VERSIONS_DIR/$CODEX_WRAPPER_FORCE_VERSION/codex" ]; then
        CODEX_VERSION="$CODEX_WRAPPER_FORCE_VERSION"
    else
        echo "[codex-wrapper] WARN: CODEX_WRAPPER_FORCE_VERSION=$CODEX_WRAPPER_FORCE_VERSION is not installed; using the newest version" >&2
        CODEX_VERSION=$(list_installed_versions | tail -1)
    fi
else
    CODEX_VERSION=$(list_installed_versions | tail -1)
fi
CODEX_BIN="$VERSIONS_DIR/$CODEX_VERSION/codex"

# Fire-and-forget background work, skipped right after a bootstrap that already
# did both (a fork is not free under Android's phantom-process budget). Output
# goes to a logfile so the terminal stays clean, and any failure is silent --
# codex startup never blocks or fails because of an update issue.
#
# The backfill runs before the update check and is scoped to the version this
# launch selected, so a version left hostless by an older wrapper revision is
# repaired rather than waiting for the next release. It lands after this
# process has exec'd, so like an update it takes effect on the next launch.
# Both network steps carry their own 24h stamp, so this fork stays bounded even
# when neither can ever succeed.
if [ "${BOOTSTRAPPED:-0}" != "1" ]; then
    ( prune_stale_staging; ensure_code_mode_host "$CODEX_VERSION"; run_update_check ) >> "$LOGFILE" 2>&1 &
    disown 2>/dev/null || true
fi

if ! command -v termux-etc-mount >/dev/null 2>&1; then
    echo "[codex-wrapper] ERROR: termux-etc-mount not found in PATH" >&2
    echo "[codex-wrapper]        install rios0rios0/termux-etc-redirect (provides" >&2
    echo "[codex-wrapper]        termux-etc-mount used to redirect /etc/* to \$PREFIX/etc/*)" >&2
    exit 1
fi

# Take Termux's wake lock before handing off to codex. Once the screen is off
# Android pauses the CPU of a backgrounded app, which mid-task looks like a
# hang and, past a grace period, a kill. The lock is NOT scoped to this
# session: the `exec` below leaves no process to release it, so it persists
# until `termux-wake-unlock` is run by hand. It is idempotent, and it comes
# from termux-tools, so its absence is not an error.
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
fi

# The sandbox cannot work on Termux (see the generating script), so default
# sandbox_mode to the only mode that runs. `-c` is a global option that every
# subcommand accepts, and `--sandbox` on the command line still wins. Note that
# `-c` is per parse level: a `-c` given AFTER the subcommand replaces this whole
# list rather than merging with it, so pass overrides of your own before the
# subcommand (`codex -c key=value exec ...`) to keep these defaults. Codex's own
# startup update check is silenced only while this wrapper's updater is active:
# codex reports "install method: other" and would only ever suggest a manual
# download.
OVERRIDES=()
if [ "${CODEX_WRAPPER_KEEP_SANDBOX:-0}" != "1" ]; then
    OVERRIDES+=(-c 'sandbox_mode="danger-full-access"')
fi
if [ "${CODEX_WRAPPER_NO_AUTO_UPDATE:-0}" != "1" ]; then
    OVERRIDES+=(-c 'check_for_update_on_startup=false')
fi

# Give the shells behind codex's tool calls the LD_PRELOAD shims back. They are
# spawned by codex itself, not by a login shell, so ~/.zshenv never runs for
# them: codex ignores $SHELL and resolves the shell from the password database,
# whose Termux entry ($PREFIX/bin/login) names none it knows, so it falls back to
# `which bash` and runs `bash -lc "<cmd>"`. An rc file could not fix this anyway
# -- an export from inside a running shell reaches only its children, while a
# `#!/usr/bin/env` script exec'd straight from a tool call needs termux-exec
# mapped before the shell starts. `shell_environment_policy.set` is exactly that:
# codex applies it to the environment it spawns tool commands with, so the shims
# are in place at exec time for whichever shell it picks. The value is the parked
# one, with the same termux-exec fallback ~/.zshenv uses when nothing was parked.
if [ "${CODEX_WRAPPER_KEEP_LD_PRELOAD:-0}" != "1" ]; then
    TOOL_SHELL_LD_PRELOAD="${TERMUX_ETC_LD_PRELOAD:-}"
    if [ -z "$TOOL_SHELL_LD_PRELOAD" ] && [ -r "$PREFIX/lib/libtermux-exec.so" ]; then
        TOOL_SHELL_LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"
    fi
    if [ -n "$TOOL_SHELL_LD_PRELOAD" ]; then
        OVERRIDES+=(-c "shell_environment_policy.set.LD_PRELOAD=\"$TOOL_SHELL_LD_PRELOAD\"")
    fi
fi

exec termux-etc-mount "$CODEX_BIN" ${OVERRIDES[@]+"${OVERRIDES[@]}"} "$@"
CODEX_EOF

chmod +x "$HOME/.local/bin/codex"

echo "[codex-wrapper] codex wrapper created successfully" >&2
