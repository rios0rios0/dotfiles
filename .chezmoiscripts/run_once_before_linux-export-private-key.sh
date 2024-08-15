#!/bin/bash

# define the path to the .ssh folder
sshFolderPath="$HOME\.ssh"

# ensure the ".ssh" folder exists
mkdir -p $sshFolderPath

if [[ ! -f "$sshFolderPath/chezmoi" ]]; then
    echo "Creating Chezmoi encryption key at: \"$sshFolderPath\chezmoi\"..."
    op read "op://personal/Chezmoi Key/private key" > "$sshFolderPath/chezmoi"
    chmod 600 "$sshFolderPath/chezmoi"
fi
