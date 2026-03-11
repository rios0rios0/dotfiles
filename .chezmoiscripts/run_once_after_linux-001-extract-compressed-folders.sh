#!/bin/bash

set -euo pipefail

# list of directories to process
WATCH_DIRS=("$HOME/.histdb" "$HOME/.john" "$HOME/.kube/config-files" "$HOME/.sqlmap")

for DIR in "${WATCH_DIRS[@]}"; do
    echo "[extract-folders] killing watchers for \"$DIR\"..." >&2
    pkill -f "inotifywait -m -r -e create,modify,delete --format %w%f $DIR" || true

    # construct TAR file name by replacing slashes with dashes and appending .tar.gz
    TAR_FILE="${DIR//\//-}.tar.gz"

    if [[ -f "$TAR_FILE" ]]; then
        echo "[extract-folders] extracting \"$TAR_FILE\"..." >&2
        tar --extract --overwrite --gzip --file "$TAR_FILE" --directory "$DIR"
    else
        echo "[extract-folders] WARN: \"$TAR_FILE\" does not exist, skipping \"$DIR\"" >&2
    fi
done
