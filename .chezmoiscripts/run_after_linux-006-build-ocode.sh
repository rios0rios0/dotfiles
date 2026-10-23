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
# The checkout is the script's to obtain, and it never builds the wrong branch: a missing one is
# cloned from the fork and left on `feat/provider-omniroute`, and an existing one sitting on
# another branch is switched to it -- the channel below is stamped whatever HEAD happens to hold,
# so a checkout left on `main` would otherwise produce a binary labelled as the fork. A directory
# that exists without being a checkout is not cloned into, and both a failed clone and a branch
# the checkout does not have warn and skip, so an apply without the network still finishes.
# Set OCODE_SOURCE to name another checkout.
# bun, the runtime the build needs, comes from `install_bun` into ~/.bun with its PATH line in
# `dot_zshenv.tmpl`; the script also falls back to ~/.bun/bin/bun itself, and skips only when
# neither answers.
# A marker at ~/.cache/ocode-built-commit makes unchanged applies a no-op, which is why this is
# a run_after script that runs on every apply. A build that fails fails the apply, so the next
# one retries it.
#
# A running ocode -- the TUI or the server it spawns -- executes ~/.local/bin/ocode, the file the
# build replaces. The script finds the processes running that file and asks before killing them,
# because they are somebody's session and killing one ends it. The answer never decides whether
# the build happens, though: the install stages the new binary under a temporary name and renames
# it into place, and a rename replaces the directory entry while the running process keeps the old
# inode. Declining, or running unattended with nothing on stdin, therefore leaves the session
# alone and builds anyway -- the session keeps the binary it started with until it restarts -- and
# an ocode started *while* the build runs is safe for the same reason.

source_dir="${OCODE_SOURCE:-$HOME/Development/github.com/opencode/opencode}"
target="$HOME/.local/bin/ocode"
marker="$HOME/.cache/ocode-built-commit"
outdir="$HOME/.cache/ocode-build"
branch="feat/provider-omniroute"
fork_url="https://github.com/rios0rios0/opencode.git"
upstream_url="https://github.com/sst/opencode.git"

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

# Cloned onto the fork's branch directly, so the checkout the build sees is the fork's even on
# its first apply. `--origin fork` names the remote the way the hand-made checkouts on this
# machine do, and sst upstream becomes `origin`, so a command typed on one machine means the
# same on another. `-e` rather than `-d`: a worktree's `.git` is a file.
if [ ! -e "$source_dir/.git" ]; then
    if [ -e "$source_dir" ]; then
        echo "[ocode] skipped: $source_dir exists but is not a git checkout, so it is not cloned into (remove it, or set OCODE_SOURCE to another path)" >&2
        exit 0
    fi
    echo "[ocode] cloning $fork_url (branch $branch) into $source_dir..." >&2
    mkdir -p "$(dirname "$source_dir")"
    if ! git clone --origin fork --branch "$branch" "$fork_url" "$source_dir" >&2; then
        echo "[ocode] WARN: failed to clone $fork_url, so there is nothing to build yet; the next apply tries again" >&2
        exit 0
    fi
    if ! git -C "$source_dir" remote get-url origin >/dev/null 2>&1; then
        git -C "$source_dir" remote add origin "$upstream_url" >&2 || true
    fi
fi

# The build stamps the channel below onto whatever HEAD is, so a checkout left on another branch
# would produce a binary labelled as the fork and carrying none of its code. Local branch first,
# then the fork's remote-tracking one (which the clone above has), and otherwise nothing: no
# network fetch of the branch, because an apply that cannot reach GitHub must still finish.
current_branch="$(git -C "$source_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$current_branch" != "$branch" ]; then
    echo "[ocode] checkout is on ${current_branch:-an unknown branch}, switching to $branch" >&2
    if git -C "$source_dir" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
        git -C "$source_dir" checkout "$branch" >&2
    elif git -C "$source_dir" rev-parse --verify --quiet "refs/remotes/fork/$branch" >/dev/null; then
        git -C "$source_dir" checkout -b "$branch" --track "fork/$branch" >&2
    else
        echo "[ocode] WARN: $source_dir has no $branch branch and no fork/$branch to track; leaving it alone, so nothing is built" >&2
        exit 0
    fi
fi

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

# Asked before the build rather than caught after it: the build takes minutes, and whether to end
# somebody's session is their call. Both answers build; they differ only in whether the running
# session is ended first.
mapfile -t running < <(running_pids)
if (( ${#running[@]} > 0 )); then
    echo "[ocode] ocode is running (PID ${running[*]}), executing $target; killing it ends the session it serves, and the build runs either way" >&2
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
            echo "[ocode] WARN: PID ${still[*]} survived SIGKILL; the build replaces $target anyway and the process keeps the binary it started with" >&2
        else
            echo "[ocode] killed PID ${running[*]}" >&2
        fi
    else
        echo "[ocode] leaving PID ${running[*]} running: the build replaces $target without disturbing it, and the session keeps the binary it started with until it restarts" >&2
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
