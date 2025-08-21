#!/bin/bash

# TODO: workaround since "op" isn't installed on WSL
op() {
  op.exe "$@"
}

# Function to find the correct 1Password account
find_op_account() {
  local target_account="${1:-my}"
  
  # Get list of configured accounts
  local accounts
  if ! accounts=$(op account list --format=json 2>/dev/null); then
    echo "Warning: Unable to list 1Password accounts. Using default account." >&2
    echo "my"
    return 0
  fi
  
  # If the target account exists in the list, use it
  if echo "$accounts" | jq -r '.[].shorthand' | grep -q "^${target_account}$"; then
    echo "$target_account"
    return 0
  fi
  
  # Try to find by URL containing the target
  local found_account
  found_account=$(echo "$accounts" | jq -r --arg target "$target_account" '.[] | select(.url | contains($target)) | .shorthand' | head -n1)
  if [[ -n "$found_account" ]]; then
    echo "$found_account"
    return 0
  fi
  
  # Try to find by email containing the target
  found_account=$(echo "$accounts" | jq -r --arg target "$target_account" '.[] | select(.email | contains($target)) | .shorthand' | head -n1)
  if [[ -n "$found_account" ]]; then
    echo "$found_account"
    return 0
  fi
  
  # Fallback to first available account
  local first_account
  if first_account=$(echo "$accounts" | jq -r '.[0].shorthand' 2>/dev/null); then
    echo "Warning: Target account '$target_account' not found. Using first available account: $first_account" >&2
    echo "$first_account"
    return 0
  fi
  
  # Last resort fallback
  echo "my"
}

# Determine which 1Password account to use
OP_ACCOUNT=$(find_op_account "${ONEPASSWORD_ACCOUNT:-my}")

# Sign in to the correct 1Password account
eval $(op signin --account "$OP_ACCOUNT")

# define the path to the ".ssh" folder
sshFolderPath="$HOME/.ssh"

# clean and recreate the ".ssh" folder
rm -rf "$sshFolderPath" && mkdir -p "$sshFolderPath"

if [[ ! -f "$sshFolderPath/chezmoi" ]]; then
    echo "Creating Chezmoi encryption key at: \"$sshFolderPath/chezmoi\"..."
    op read "op://personal/Chezmoi Key/private key" > "$sshFolderPath/chezmoi"
    chmod 600 "$sshFolderPath/chezmoi"
fi
