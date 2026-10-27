#!/bin/bash

# Restores the folders the watcher in dot_scripts/executable_linux-toolbox-watch-compress-folders.sh
# backs up as archives. The watcher writes "<folder>.tar" beside each folder and adds it to chezmoi
# encrypted, so a new machine gets the archive from `chezmoi apply` -- ~/.kube/config-files.tar is
# the one in the repository -- and this unpacks it beside itself. A folder chezmoi deploys file by
# file (.histdb, .john and .sqlmap) has no archive, which is nothing to report.
#
# Until 2026-10 this looked for "-home-<user>-<folder>.tar.gz" in its working directory, the name
# the watcher wrote in 2025, so it never found an archive: every first apply warned four times and
# ~/.kube/config-files was never restored.
#
# Only a folder that does not exist is restored, so nothing newer than the archive is overwritten.
# It is unpacked beside its target and renamed into place, so a failed extraction leaves no
# half-restored folder that the next run would take for a finished one.

set -euo pipefail

# The folders the watcher archives (its WATCH_DIRS).
WATCH_DIRS=("$HOME/.histdb" "$HOME/.john" "$HOME/.kube/config-files" "$HOME/.sqlmap")

restored=0
failed=0
for dir in "${WATCH_DIRS[@]}"; do
    archive="$dir.tar"
    if [[ ! -f "$archive" || -e "$dir" ]]; then
        continue
    fi

    parent="$(dirname "$dir")"
    name="$(basename "$dir")"
    staging="$(mktemp -d "$parent/.$name.extract.XXXXXX")"
    # tar recognises the compression by itself: the archive in the repository is gzipped, and the
    # watcher writes plain tar.
    if tar --extract --file "$archive" --directory "$staging" && [[ -d "$staging/$name" ]] \
        && mv "$staging/$name" "$dir"; then
        echo "[extract-folders] restored \"$dir\" from \"$archive\"" >&2
        restored=$((restored + 1))
    else
        echo "[extract-folders] WARN: could not restore \"$dir\" from \"$archive\"" >&2
        failed=$((failed + 1))
    fi
    rm -rf "$staging"
done

# A running watcher watches only the folders that existed when it started, so it would not back up
# a restored one. Stopped, it is started again by the next interactive zsh, which sees them all.
if (( restored > 0 )); then
    pkill -f "$HOME/.scripts/linux-toolbox-watch-compress-folders.sh" || true
fi

# A failure exits non-zero, so chezmoi runs this again on the next apply instead of recording it
# as done.
if (( failed > 0 )); then
    echo "[extract-folders] ERROR: the next 'chezmoi apply' runs this again" >&2
    exit 1
fi
