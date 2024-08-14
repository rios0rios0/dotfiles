#!/bin/sh

echo "Extracting \"$HOME/.kube/config-files.tar\" config files..."
tar --extract --overwrite --gzip --file "$HOME/.kube/config-files.tar" --directory "$HOME/.kube"
