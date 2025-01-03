#!/bin/bash

# list of directories to process
WATCH_DIRS=("$HOME/.histdb" "$HOME/.john" "$HOME/.kube/config-files" "$HOME/.sqlmap")

for DIR in "${WATCH_DIRS[@]}"; do
    echo "Killing all watchers for \"$DIR\"..."
    pkill -f "inotifywait -m -r -e create,modify,delete --format %w%f $DIR"

    TAR_FILE="${DIR//\//-}.tar.gz"
    echo "Extracting \"$TAR_FILE\" files..."
    tar --extract --overwrite --gzip --file "$TAR_FILE" --directory "$DIR"
done
