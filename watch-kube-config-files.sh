#!/bin/bash

inotifywait -m -r -e create,modify,delete --format '%w%f' "$HOME/.kube/config-files" | while read FILE
do
    echo "Archiving \"$HOME/.kube/config-files\" config files..."
    tar --create --gzip --file "$HOME/.kube/config-files.tar" --directory "$HOME/.kube" config-files
done
