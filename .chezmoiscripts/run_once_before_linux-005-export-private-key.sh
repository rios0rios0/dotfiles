#!/bin/bash

set -euo pipefail

# TODO: workaround since "op" isn't installed on WSL
op() {
  op.exe "$@"
}

# sign into the personal 1Password account ('my' shorthand refers to my.1password.com)
# when multiple accounts are configured, --account my ensures the personal account is used
# if 'my' shorthand is missing, add the personal account first with:
#   op account add --address my.1password.com --shorthand my
if ! signin_output=$(op signin --account my); then
    echo "[export-key] ERROR: could not sign into 1Password personal account (shorthand 'my')" >&2
    echo "[export-key] if you have multiple accounts, ensure the personal account uses the 'my' shorthand:" >&2
    echo "[export-key]   op account add --address my.1password.com --shorthand my" >&2
    exit 1
fi
eval "$signin_output"

# define the path to the ".ssh" folder
sshFolderPath="$HOME/.ssh"

# clean and recreate the ".ssh" folder
rm -rf "$sshFolderPath" && mkdir -p "$sshFolderPath"

if [[ ! -f "$sshFolderPath/chezmoi" ]]; then
    echo "[export-key] creating Chezmoi encryption key at: \"$sshFolderPath/chezmoi\"..." >&2
    op read "op://personal/Chezmoi Key/private key" > "$sshFolderPath/chezmoi"
    chmod 600 "$sshFolderPath/chezmoi"
fi
