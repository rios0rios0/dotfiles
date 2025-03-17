#!/bin/bash

# list of directories to process
WATCH_DIRS=("$HOME/.histdb" "$HOME/.john" "$HOME/.kube/config-files" "$HOME/.sqlmap")

for DIR in "${WATCH_DIRS[@]}"; do
    echo "Killing all watchers for \"$DIR\"..."
    pkill -f "inotifywait -m -r -e create,modify,delete --format %w%f $DIR"

    # construct TAR file name by replacing slashes with dashes and appending .tar.gz
    TAR_FILE="${DIR//\//-}.tar.gz"

    if [[ -f "$TAR_FILE" ]]; then
        echo "Extracting \"$TAR_FILE\" files..."
        tar --extract --overwrite --gzip --file "$TAR_FILE" --directory "$DIR"
    else
        echo "TAR file \"$TAR_FILE\" does not exist. Skipping extraction for \"$DIR\"."
    fi
done
