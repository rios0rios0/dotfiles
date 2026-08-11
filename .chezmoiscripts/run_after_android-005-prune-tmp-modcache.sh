#!/data/data/com.termux/files/usr/bin/bash

# Deletes Go module caches that were created under $TMPDIR.
#
# Go writes module cache entries as 0400 files inside 0500 directories, and
# unlinking a child requires its *parent* to be writable, so a plain `rm -rf`
# fails with EACCES on every one of them. Termux's TermuxService.onDestroy()
# calls clearTermuxTMPDIR(), which walks $TMPDIR, collects one stack trace per
# entry it could not delete, and then stringifies the whole batch. A single
# leaked cache is ~8k undeletable entries; at roughly 1.5k characters per trace
# the StringBuilder crosses the 256 MB heap growth limit and Termux dies with
# an OutOfMemoryError every time it is closed.
#
# `dot_zshenv.tmpl` pins GOMODCACHE to $HOME so Go can no longer place a cache
# here, which is the actual fix. This script is the safety net for what the pin
# cannot reach: caches left behind by an earlier revision of this repo, and
# tools that export a GOMODCACHE of their own. Prevention and cleanup are
# separate jobs and both are needed.
#
# Only the `pkg/mod` directory is removed, never its parent, so a sibling `bin/`
# holding `go install`ed tools survives.
#
# This is a `run_after_` (not `run_once_after_`) script so it re-runs on every
# `chezmoi apply`.

set -euo pipefail

prefix="tmp-modcache"

tmpDir="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

[ -d "$tmpDir" ] || exit 0

# Resolve to a canonical path so the containment check below cannot be defeated
# by a symlink or a trailing slash.
tmpDir="$(cd "$tmpDir" && pwd -P)"

prune_cache() {
    local cache="$1"

    # Safety rail: this runs unattended on every apply, so it must never delete
    # outside $TMPDIR. The `?*` guard also rejects a bare "$tmpDir" itself.
    case "$cache" in
        "$tmpDir"/?*) ;;
        *)
            echo "[$prefix] WARN: refusing to remove '$cache' (outside \$TMPDIR)" >&2
            return 0
            ;;
    esac

    # No `..` component, which would satisfy the prefix check above yet still
    # escape $TMPDIR. Wrapping the path in slashes means a real component always
    # shows up as "/../", so a legitimate name like "foo..bar" is not caught.
    case "/$cache/" in
        */../*)
            echo "[$prefix] WARN: refusing to remove '$cache' (path escapes \$TMPDIR)" >&2
            return 0
            ;;
    esac

    # Never touch the live module cache, however it was configured.
    if [ -n "${GOMODCACHE:-}" ] && [ "$cache" = "$GOMODCACHE" ]; then
        echo "[$prefix] WARN: skipping '$cache' (it is the active \$GOMODCACHE)" >&2
        return 0
    fi

    echo "[$prefix] removing Go module cache under \$TMPDIR: $cache" >&2

    # Restore write permission before deleting. Without this `rm -rf` fails on
    # every entry, which is the same wall Termux hits on shutdown.
    chmod -R u+w "$cache" 2>/dev/null || true

    if ! rm -rf "$cache"; then
        echo "[$prefix] WARN: failed to remove '$cache'" >&2
    fi
}

found=0

# `-prune` stops the descent so the thousands of entries inside a cache are
# never enumerated. The loop body runs in the current shell (no pipeline), so
# `found` survives it.
while IFS= read -r cache; do
    found=1
    prune_cache "$cache"
done < <(find "$tmpDir" -type d -path '*/pkg/mod' -prune -print 2>/dev/null)

if [ "$found" -ne 0 ]; then
    echo "[$prefix] done" >&2
fi
