#!/bin/bash

echo "Killing all watchers for \"$HOME/.kube/config-files\"..."
pkill -f "inotifywait -m -r -e create,modify,delete --format %w%f $HOME/.kube/config-files"

echo "Extracting \"$HOME/.kube/config-files.tar\" config files..."
tar --extract --overwrite --gzip --file "$HOME/.kube/config-files.tar" --directory "$HOME/.kube"
