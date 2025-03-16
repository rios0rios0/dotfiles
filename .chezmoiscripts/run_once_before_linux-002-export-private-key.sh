#!/bin/bash

# TODO: workaround since "op" isn't installed on WSL
op() {
  op.exe "$@"
}

# TODO: workaround to always use the same account first
eval $(op signin --account my)

# define the path to the ".ssh" folder
sshFolderPath="$HOME/.ssh"

# clean and recreate the ".ssh" folder
rm -rf "$sshFolderPath" && mkdir -p "$sshFolderPath"

if [[ ! -f "$sshFolderPath/chezmoi" ]]; then
    echo "Creating Chezmoi encryption key at: \"$sshFolderPath/chezmoi\"..."
    op read "op://personal/Chezmoi Key/private key" > "$sshFolderPath/chezmoi"
    chmod 600 "$sshFolderPath/chezmoi"
fi
