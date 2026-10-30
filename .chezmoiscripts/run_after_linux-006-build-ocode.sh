#!/usr/bin/env bash
set -euo pipefail

# Builds the local OpenCode fork checkout into ~/.local/bin/ocode whenever the checkout's HEAD
# differs from the last build, and installs the result as `ocode` -- the personal fork's build,
# carrying its custom features (the OmniRoute provider plugin and the
# OPENCODE_DISABLE_CLAUDE_CODE gate, branch reworked). It builds as a
# release-grade client on the fork's own channel (see the build-identity note above the build
# command): the Console refuses the free tier for client versions below 1.18.0, and a bare
# branch build's `0.0.0-<branch>-<time>` preview version falls below it.
#
# The checkout is the script's to obtain, and it never builds the wrong branch: a missing one is
# cloned from the fork and left on `reworked`, and an existing one sitting on
# another branch is switched to it -- the channel below is stamped whatever HEAD happens to hold,
# so a checkout left on `main` would otherwise produce a binary labelled as the fork. The fork's
# remote is found by its URL, whatever it is called, and a branch that remote has never fetched is
# fetched first. A directory that exists without being a checkout is not cloned into, and a failed
# clone, a failed fetch and a checkout with no remote for the fork all warn and skip, so an apply
# without the network still finishes. Set OCODE_SOURCE to name another checkout.
#
# bun, the runtime the build needs, comes from `install_bun` into ~/.bun with its PATH line in
# `dot_zshenv.tmpl`; the script also falls back to ~/.bun/bin/bun itself, and skips only when
# neither answers. That bun is the machine's, though, and the checkout pins its own in
# package.json's `packageManager` (`bun@X.Y.Z`), the field upstream OpenCode's CI reads to
# install exactly that version. The two drift apart (`bun upgrade`, a rebase that moves the
# pin), and a newer bun is no drop-in: 1.4.4 refuses a patch file in the checkout that the 1.4.2
# pin applies. So the build installs the checkout's dependencies, and then builds, with the
# pinned bun: the resolved one when it is that version, otherwise a copy under
# ~/.cache/ocode-bun/<version>/, which the first build that needs it downloads from bun's GitHub
# release and verifies against the release's SHASUMS256.txt. A missing or unreadable pin and a
# failed download warn and fall back to the resolved bun, so an apply without the network still
# finishes. The install itself (`bun install --frozen-lockfile`, upstream CI's command) runs
# before every build because the build takes it for granted: its `--skip-install` skips only its
# own cross-platform install of two native packages, and a fresh clone, which nothing had
# installed, failed with dozens of `Could not resolve: "effect"`.
# A marker at ~/.cache/ocode-built-commit makes unchanged applies a no-op, which is why this is
# a run_after script that runs on every apply. A build that fails -- the dependency install
# included -- fails the apply, so the next one retries it.
#
# A running ocode -- the TUI or the server it spawns -- executes ~/.local/bin/ocode, the file the
# build replaces. The script finds the processes running that file and asks before killing them,
# because they are somebody's session and killing one ends it. The answer never decides whether
# the build happens, though: the install stages the new binary under a temporary name and renames
# it into place, and a rename replaces the directory entry while the running process keeps the old
# inode. Declining, or running unattended with nothing on stdin, therefore leaves the session
# alone and builds anyway -- the session keeps the binary it started with until it restarts -- and
# an ocode started *while* the build runs is safe for the same reason.

source_dir="${OCODE_SOURCE:-$HOME/Development/github.com/rios0rios0/opencode}"
target="$HOME/.local/bin/ocode"
marker="$HOME/.cache/ocode-built-commit"
outdir="$HOME/.cache/ocode-build"
bun_cache="$HOME/.cache/ocode-bun"
branch="reworked"
fork_url="https://github.com/rios0rios0/opencode.git"
upstream_url="https://github.com/sst/opencode.git"
# What a remote URL for the fork looks like: HTTPS, SSH, or an SSH host alias such as the
# github.com-mine that dot_ssh/config.tmpl defines. Anchored on the repository path, so neither
# upstream nor another repository whose name starts with `opencode` matches.
fork_url_pattern='^(https://|ssh://)?([^@/]+@)?github\.com(-[[:alnum:]_-]+)?[:/]rios0rios0/opencode(\.git)?/?$'
bun_releases="https://github.com/oven-sh/bun/releases/download"

# bun is resolved from PATH first and from ~/.bun/bin second: `install_bun` puts it there
# and `dot_zshenv.tmpl` carries the PATH line, but a shell started before that apply still
# has the old PATH, and this script runs with the apply's environment. That gap is how the
# build came to be skipped on a machine whose bun was installed all along.
bun="$(command -v bun || true)"
if [[ -z "$bun" ]] && [[ -x "$HOME/.bun/bin/bun" ]]; then
    bun="$HOME/.bun/bin/bun"
fi
if [[ -z "$bun" ]]; then
    echo "[ocode] skipped: bun is not installed (not on PATH, no ~/.bun/bin/bun)" >&2
    exit 0
fi

# Cloned onto the fork's branch directly, so the checkout the build sees is the fork's even on
# its first apply. `--origin fork` keeps `origin` for sst upstream, so it names the same
# repository in every clone this script makes. The branch switch below does not rely on that
# name: a plain `git clone` of the fork, made by hand, calls the fork `origin`.
# `-e` rather than `-d`: a worktree's `.git` is a file.
if [[ ! -e "$source_dir/.git" ]]; then
    if [[ -e "$source_dir" ]]; then
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
# then the fork's remote-tracking one, under whichever remote points at the fork. A branch that
# remote has never fetched is fetched first, from the fork's public HTTPS URL rather than the
# remote's own: the remote may be an SSH alias that waits on a 1Password approval, which nobody
# gives an unattended apply. A failed fetch warns and skips like a failed clone, so an apply that
# cannot reach GitHub still finishes.

# Prints the first remote whose URL is the fork's, and fails when there is none.
fork_remote() {
    local remote url
    while IFS= read -r remote; do
        url="$(git -C "$source_dir" remote get-url "$remote" 2>/dev/null || true)"
        if [[ "$url" =~ $fork_url_pattern ]]; then
            printf '%s\n' "$remote"
            return 0
        fi
    done < <(git -C "$source_dir" remote 2>/dev/null || true)
    return 1
}

current_branch="$(git -C "$source_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ "$current_branch" != "$branch" ]]; then
    echo "[ocode] checkout is on ${current_branch:-an unknown branch}, switching to $branch" >&2
    if git -C "$source_dir" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
        git -C "$source_dir" checkout "$branch" >&2
    else
        if ! remote="$(fork_remote)"; then
            echo "[ocode] WARN: $source_dir has no $branch branch and no remote for $fork_url; leaving it alone, so nothing is built (git -C $source_dir remote add fork $fork_url adds one)" >&2
            exit 0
        fi
        if ! git -C "$source_dir" rev-parse --verify --quiet "refs/remotes/$remote/$branch" >/dev/null; then
            echo "[ocode] $source_dir has no $remote/$branch yet; fetching it from $fork_url" >&2
            if ! GIT_TERMINAL_PROMPT=0 git -C "$source_dir" fetch --no-tags "$fork_url" "+refs/heads/$branch:refs/remotes/$remote/$branch" >&2; then
                echo "[ocode] WARN: failed to fetch $branch from $fork_url, so nothing is built; the next apply tries again" >&2
                exit 0
            fi
        fi
        git -C "$source_dir" checkout -b "$branch" --track "$remote/$branch" >&2
    fi
fi

head="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$(cat "$marker" 2>/dev/null || true)" = "$head" ]] && [[ -x "$target" ]]; then
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

# The release asset bun's own installer (bun.sh/install) picks for this machine: by architecture,
# and on x64 the `-baseline` build when the CPU lacks AVX2, which the default x64 build requires.
# Fails, printing nothing, on an architecture bun publishes no Linux build for.
bun_asset() {
    case "$(uname -m)" in
        x86_64 | amd64)
            if grep -qw avx2 /proc/cpuinfo 2>/dev/null; then
                echo "bun-linux-x64"
            else
                echo "bun-linux-x64-baseline"
            fi
            ;;
        aarch64 | arm64)
            echo "bun-linux-aarch64"
            ;;
        *)
            return 1
            ;;
    esac
}

# Fetches bun $1 from its GitHub release into $bun_cache/$1/bun. Not through bun.sh/install: that
# script replaces ~/.bun, the machine's own bun, and edits a shell rc file chezmoi owns. The zip is
# checked against the SHASUMS256.txt published with the release before anything is extracted, and
# the binary must start and report the version asked for before it takes its final name, so the
# cache only ever holds a working copy of the pinned bun. Anything else warns, leaves the cache as
# it was, and fails, which the caller answers by falling back to the resolved bun.
fetch_bun() {
    local version="$1"
    local dest="$bun_cache/$1"
    local asset base workdir expected staged reported tool

    if ! asset="$(bun_asset)"; then
        echo "[ocode] WARN: bun publishes no Linux build for $(uname -m), so bun $version cannot be fetched" >&2
        return 1
    fi
    for tool in curl unzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "[ocode] WARN: $tool is not installed, so bun $version cannot be fetched" >&2
            return 1
        fi
    done

    base="$bun_releases/bun-v$version"
    workdir="$(mktemp -d)"
    local -a https_only=(--proto '=https' --proto-redir '=https')
    echo "[ocode] downloading $asset.zip from $base..." >&2
    if ! curl "${https_only[@]}" -fsSL --connect-timeout 20 --retry 2 -o "$workdir/$asset.zip" "$base/$asset.zip" ||
        ! curl "${https_only[@]}" -fsSL --connect-timeout 20 --retry 2 -o "$workdir/SHASUMS256.txt" "$base/SHASUMS256.txt"; then
        echo "[ocode] WARN: failed to download bun $version from $base" >&2
        rm -rf "$workdir"
        return 1
    fi

    # Matched on the file name as a whole string, not as a pattern: the x64 asset's name is a
    # prefix of the `-baseline` one's, and its dots would match any character.
    expected="$(awk -v name="$asset.zip" '$2 == name { print $1; exit }' "$workdir/SHASUMS256.txt")"
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo "[ocode] WARN: the SHASUMS256.txt of bun $version lists no checksum for $asset.zip, so it is not used" >&2
        rm -rf "$workdir"
        return 1
    fi
    if ! echo "$expected  $workdir/$asset.zip" | sha256sum --check --status; then
        echo "[ocode] WARN: $asset.zip does not match the checksum in the SHASUMS256.txt of bun $version, so it is not used" >&2
        rm -rf "$workdir"
        return 1
    fi
    if ! unzip -oq "$workdir/$asset.zip" "$asset/bun" -d "$workdir" || [[ ! -f "$workdir/$asset/bun" ]]; then
        echo "[ocode] WARN: $asset.zip of bun $version holds no $asset/bun" >&2
        rm -rf "$workdir"
        return 1
    fi

    # Staged beside its final name and renamed into place, as the install below does with ocode,
    # and asked for its version there rather than in the temporary directory, which may be
    # mounted noexec. A binary that cannot start on this CPU fails here, not halfway into the
    # dependency install.
    staged="$dest/bun.new.$$"
    if ! mkdir -p "$dest" || ! command cp "$workdir/$asset/bun" "$staged" || ! chmod 0755 "$staged"; then
        echo "[ocode] WARN: could not stage bun $version under $dest" >&2
        rm -rf "$workdir"
        rm -f "$staged"
        rmdir "$dest" 2>/dev/null || true
        return 1
    fi
    rm -rf "$workdir"
    reported="$("$staged" --version 2>/dev/null || true)"
    if [[ "$reported" != "$version" ]]; then
        echo "[ocode] WARN: the downloaded bun reports ${reported:-no version} rather than $version, so it is not used" >&2
        rm -f "$staged"
        rmdir "$dest" 2>/dev/null || true
        return 1
    fi
    if ! command mv -f "$staged" "$dest/bun"; then
        echo "[ocode] WARN: could not move bun $version into place at $dest/bun" >&2
        rm -f "$staged"
        return 1
    fi
    echo "[ocode] cached bun $version at $dest/bun" >&2
}

# The bun the checkout pins (see the header), read with jq as the root package.json's
# `packageManager`. Only a plain release version counts as a pin: a range, a tag such as
# `canary` and another package manager name nothing a release download can fetch. The resolved
# bun is kept whenever that version is unknown or cannot be had.
bun_version="$("$bun" --version 2>/dev/null || true)"
manifest="$source_dir/package.json"
pinned=""
if ! package_manager="$(jq -r '.packageManager // empty' "$manifest" 2>/dev/null)"; then
    echo "[ocode] WARN: could not read packageManager from $manifest (jq missing, or the file missing or not JSON), so the build uses $bun, which reports ${bun_version:-no version}" >&2
elif [[ "$package_manager" =~ ^bun@([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    pinned="${BASH_REMATCH[1]}"
else
    echo "[ocode] WARN: $manifest pins no bun release (packageManager is ${package_manager:-missing}), so the build uses $bun, which reports ${bun_version:-no version}" >&2
fi
if [[ -n "$pinned" ]]; then
    cached="$bun_cache/$pinned/bun"
    if [[ "$bun_version" = "$pinned" ]]; then
        echo "[ocode] $bun is bun $pinned, the version the checkout pins" >&2
    elif [[ -x "$cached" ]] && [[ "$("$cached" --version 2>/dev/null || true)" = "$pinned" ]]; then
        echo "[ocode] the checkout pins bun $pinned and $bun reports ${bun_version:-no version}; using the cached $cached" >&2
        bun="$cached"
        bun_version="$pinned"
    else
        echo "[ocode] the checkout pins bun $pinned and $bun reports ${bun_version:-no version}; fetching bun $pinned" >&2
        if fetch_bun "$pinned"; then
            bun="$cached"
            bun_version="$pinned"
        else
            echo "[ocode] WARN: bun $pinned is not available, so the build uses $bun, which reports ${bun_version:-no version} and may reject what bun $pinned accepts; the next build tries the download again" >&2
        fi
    fi
fi

# The install and the build both spawn `bun` themselves -- the root postinstall is a `bun run`,
# and so is the build script -- so the chosen bun's directory goes first on PATH for the
# duration: every bun involved must be the one that resolved the lockfile.
bun_dir="$(dirname "$bun")"
export PATH="$bun_dir:$PATH"

# The workspace install the build takes for granted (see the header). `--frozen-lockfile`
# installs exactly bun.lock, as upstream's CI does, and fails rather than rewrite the lockfile of
# somebody's checkout. Lifecycle scripts stay enabled: the root postinstall restores the execute
# bit on node-pty's prebuilt spawn-helper, without which no terminal can be spawned.
echo "[ocode] installing the checkout's dependencies with bun ${bun_version:-of unknown version} ($bun)..." >&2
if ! (cd "$source_dir" && "$bun" install --frozen-lockfile); then
    echo "[ocode] ERROR: bun install --frozen-lockfile failed in $source_dir, so nothing was built; the next apply tries again" >&2
    exit 1
fi

# Build identity: the binary must report a release-grade version, because the Console's free
# tier gate reads it from the User-Agent -- `opencode/<channel>/<version>/<name>` -- and
# refuses clients below 1.18.0, which a bare branch build's `0.0.0-<branch>-<time>` preview
# version is. The version is the upstream release the checkout is built on -- the CLI
# package's `version`, which upstream's release commit sets -- marked as this fork's build of
# it: `<release>-<branch>.<build time>`, e.g. `2.1.4-reworked.2610241230`. The build time keeps
# every build's version distinct, because a launch replaces the background service only when the
# service reports a version other than the binary's own, so a rebuild would otherwise go on
# talking to the service the previous build started. A CLI package that names no release
# version stamps 2.0.0 instead, with a warning, so the build stays release-grade. The channel
# stays `feat-provider-omniroute`, the fork's original branch, so the fork keeps its own service
# registration, port and database.
cli_manifest="$source_dir/packages/cli/package.json"
if ! release="$(jq -r '.version // empty' "$cli_manifest" 2>/dev/null)"; then
    echo "[ocode] WARN: could not read the release version from $cli_manifest (jq missing, or the file missing or not JSON), so the build is stamped 2.0.0" >&2
    release="2.0.0"
elif [[ ! "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ocode] WARN: $cli_manifest names no release version (version is ${release:-missing}), so the build is stamped 2.0.0" >&2
    release="2.0.0"
fi
OPENCODE_CHANNEL="feat-provider-omniroute"
# A semver pre-release identifier allows only [0-9A-Za-z-], and a branch can hold a `/`.
OPENCODE_VERSION="$release-${branch//[^0-9A-Za-z-]/-}.$(date -u +%y%m%d%H%M)"
export OPENCODE_CHANNEL OPENCODE_VERSION
echo "[ocode] stamping the build as $OPENCODE_CHANNEL $OPENCODE_VERSION" >&2
# A single, current-platform build; the web UI bundle and the release assets cost minutes each
# and add nothing to a local binary. `--skip-install` stays: the install above brought this
# platform's native packages, and what the flag skips is the build's own install of those
# packages for every platform, which only a cross-platform release needs. The fork's build
# re-creates the outdir itself and emits <outdir>/cli-<target>/bin/opencode.
"$bun" run --cwd "$source_dir/packages/cli" build --single --skip-install --skip-web-ui --outdir="$outdir"

built="$(find "$outdir" -path '*/bin/opencode' -type f | head -n 1)"
if [[ -z "$built" ]]; then
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
