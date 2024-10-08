#!/bin/bash

# check if inotifywait is already running for the specified directory
if pgrep -f "inotifywait -m -r -e create,modify,delete --format %w%f $HOME/.kube/config-files" > /dev/null; then
    echo "Watcher already running for $HOME/.kube/config-files"
else
    inotifywait -m -r -e create,modify,delete --format '%w%f' "$HOME/.kube/config-files" | while read FILE
    do
        echo "Archiving \"$HOME/.kube/config-files\" config files..."
        tar --create --gzip --file "$HOME/.kube/config-files.tar" --directory "$HOME/.kube" config-files
        chezmoi add --encrypt "$HOME/.kube/config-files.tar"
    done
fi
