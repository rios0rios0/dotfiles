#!/usr/bin/env bash
set -euo pipefail

# Builds the local OpenCode fork checkout into ~/.local/bin/ocode whenever the checkout's HEAD
# differs from the last build, and installs the result as `ocode` -- the personal fork's build,
# carrying its custom features (the OmniRoute provider plugin and the
# OPENCODE_DISABLE_CLAUDE_CODE gate, branch feat/provider-omniroute).
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

echo "[ocode] building $(git -C "$source_dir" log -1 --format='%h %s')..." >&2
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
command cp "$built" "$target"
chmod 0755 "$target"
echo "$head" >"$marker"
echo "[ocode] installed $(basename "$built") from $head to $target" >&2
