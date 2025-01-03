#!/bin/bash

# list of directories to watch
WATCH_DIRS=("$HOME/.histdb" "$HOME/.john" "$HOME/.kube/config-files" "$HOME/.sqlmap")

for DIR in "${WATCH_DIRS[@]}"; do
    # check if inotifywait is already running for the specified directory
    if pgrep -f "inotifywait -m -r -e create,modify,delete --format %w%f $DIR" > /dev/null; then
        echo "Watcher already running for $DIR"
    else
        inotifywait -m -r -e create,modify,delete --format '%w%f' "$DIR" | while read FILE
        do
            echo "Archiving \"$DIR\" files..."
            TAR_FILE="${DIR//\//-}.tar.gz"
            tar --create --gzip --file "$TAR_FILE" --directory "$DIR" .
            chezmoi add --encrypt "$TAR_FILE"
        done &
    fi
done
