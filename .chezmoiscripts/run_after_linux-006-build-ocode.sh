#!/usr/bin/env bash
set -euo pipefail

# Builds the local OpenCode fork checkout into ~/.local/bin/ocode whenever the checkout's HEAD
# differs from the last build, and installs the result as `ocode` -- the personal fork's build,
# carrying its custom features (the OmniRoute provider plugin and the
# OPENCODE_DISABLE_CLAUDE_CODE gate, branch feat/provider-omniroute). It builds as a
# release-grade client on the fork's own channel (see the build-identity note above the build
# command): the Console refuses the free tier for client versions below 1.18.0, and a bare
# branch build's `0.0.0-<branch>-<time>` preview version falls below it.
#
# Without the checkout this script skips: cloning is left to the user
# (git clone https://github.com/rios0rios0/opencode.git into
# ~/Development/github.com/opencode/opencode). Set OCODE_SOURCE to name another checkout.
# bun, the runtime the build needs, comes from `install_bun` into ~/.bun with its PATH line in
# `dot_zshenv.tmpl`; the script also falls back to ~/.bun/bin/bun itself, and skips only when
# neither answers.
# A marker at ~/.cache/ocode-built-commit makes unchanged applies a no-op, which is why this is
# a run_after script that runs on every apply. A build that fails fails the apply, so the next
# one retries it.
#
# A running ocode -- the TUI or the server it spawns -- is executing ~/.local/bin/ocode, a file
# `cp` cannot overwrite while it runs ("Text file busy"), and that error fails the whole apply.
# The script therefore finds the processes running that file and asks before killing them, since
# they are somebody's session; declining, or running unattended with nothing on stdin, skips the
# build and leaves the marker, so the next apply tries again. The install itself stages the new
# binary under a temporary name and renames it into place, so an ocode started *while* the build
# runs cannot fail it either.

source_dir="${OCODE_SOURCE:-$HOME/Development/github.com/opencode/opencode}"
target="$HOME/.local/bin/ocode"
marker="$HOME/.cache/ocode-built-commit"
outdir="$HOME/.cache/ocode-build"

if [ ! -d "$source_dir/.git" ]; then
    echo "[ocode] skipped: no fork checkout at $source_dir (clone rios0rios0/opencode there, branch feat/provider-omniroute)" >&2
    exit 0
fi

# bun is resolved from PATH first and from ~/.bun/bin second: `install_bun` puts it there
# and `dot_zshenv.tmpl` carries the PATH line, but a shell started before that apply still
# has the old PATH, and this script runs with the apply's environment. That gap is how the
# build came to be skipped on a machine whose bun was installed all along.
bun="$(command -v bun || true)"
if [ -z "$bun" ] && [ -x "$HOME/.bun/bin/bun" ]; then
    bun="$HOME/.bun/bin/bun"
fi
if [ -z "$bun" ]; then
    echo "[ocode] skipped: bun is not installed (not on PATH, no ~/.bun/bin/bun)" >&2
    exit 0
fi
# The build may spawn `bun` itself, so its directory goes on PATH for the duration.
bun_dir="$(dirname "$bun")"
export PATH="$bun_dir:$PATH"

head="$(git -C "$source_dir" rev-parse HEAD)"
if [ "$(cat "$marker" 2>/dev/null || true)" = "$head" ] && [ -x "$target" ]; then
    exit 0
fi

# The processes executing the installed binary, matched through /proc/<pid>/exe rather than by
# name: `pgrep ocode` would also catch one started from another path, which holds no file of
# ours and would be killed for nothing. A pid whose exe cannot be read (another user's process,
# a zombie) does not hold this file either.
running_pids() {
    local pid exe
    for pid in /proc/[0-9]*; do
        pid="${pid#/proc/}"
        exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || continue
        if [[ "$exe" == "$target" ]]; then
            printf '%s\n' "$pid"
        fi
    done
}

# Asked before the build rather than caught after it: the build takes minutes, and killing the
# running ocode before it starts is the whole point -- the person knows it is their session.
mapfile -t running < <(running_pids)
if (( ${#running[@]} > 0 )); then
    echo "[ocode] ocode is running (PID ${running[*]}): it executes $target, which the build cannot overwrite, and killing it ends the session it serves" >&2
    printf '%s' "[ocode] kill it and continue with the build? [y/N] " >&2
    answer=""
    read -r answer || true
    if [[ "$answer" =~ ^[Yy] ]]; then
        kill "${running[@]}" 2>/dev/null || true
        for _ in $(seq 1 20); do
            mapfile -t still < <(running_pids)
            if (( ${#still[@]} == 0 )); then
                break
            fi
            sleep 0.25
        done
        mapfile -t still < <(running_pids)
        if (( ${#still[@]} > 0 )); then
            echo "[ocode] WARN: PID ${still[*]} ignored SIGTERM; sending SIGKILL" >&2
            kill -9 "${still[@]}" 2>/dev/null || true
            sleep 1
            mapfile -t still < <(running_pids)
        fi
        if (( ${#still[@]} > 0 )); then
            echo "[ocode] ERROR: PID ${still[*]} still executes $target after SIGKILL; kill it and run 'chezmoi apply' again" >&2
            exit 1
        fi
        echo "[ocode] killed PID ${running[*]}" >&2
    else
        echo "[ocode] skipped the build: ocode is still running; close it and run 'chezmoi apply' again" >&2
        exit 0
    fi
fi

echo "[ocode] building $(git -C "$source_dir" log -1 --format='%h %s')..." >&2
# Build identity: the binary must report a release-grade version, because the Console's free
# tier gate reads it from the User-Agent -- `opencode/<channel>/<version>/<name>` -- and
# refuses clients below 1.18.0, which a bare branch build's `0.0.0-<branch>-<time>` preview
# version is. The channel stays the branch, so the fork keeps its own service registration,
# port and database; the patch tracks the build time so a rebuild replaces the background
# service on the next launch.
OPENCODE_CHANNEL="feat-provider-omniroute"
OPENCODE_VERSION="2.0.$(date -u +%y%m%d%H%M)"
export OPENCODE_CHANNEL OPENCODE_VERSION
# A single, current-platform build; the web UI bundle and the release assets cost minutes each
# and add nothing to a local binary. The fork's build re-creates the outdir itself and emits
# <outdir>/cli-<target>/bin/opencode.
"$bun" run --cwd "$source_dir/packages/cli" build --single --skip-install --skip-web-ui --outdir="$outdir"

built="$(find "$outdir" -path '*/bin/opencode' -type f | head -n 1)"
if [ -z "$built" ]; then
    echo "[ocode] ERROR: the fork build produced no binary under $outdir" >&2
    exit 1
fi

mkdir -p "$(dirname "$target")" "$(dirname "$marker")"
# Staged beside the target and renamed over it: `mv` replaces the file whatever currently
# executes it, where a direct `cp` would fail with "Text file busy" on an ocode started between
# the prompt above and this line (the build takes minutes).
staged="$target.new.$$"
command cp "$built" "$staged"
chmod 0755 "$staged"
command mv -f "$staged" "$target"
echo "$head" >"$marker"
echo "[ocode] installed $(basename "$built") from $head to $target" >&2
