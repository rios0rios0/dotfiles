#!/bin/bash

# Fans out the staged JetBrains themes under ~/.local/share/jetbrains-themes/ into
# every detected JetBrains IDE config directory at ~/.config/JetBrains/<Product><Version>/.
# Idempotent: safe to run on every chezmoi apply.

set -euo pipefail

prefix="jetbrains-themes"
staging="$HOME/.local/share/jetbrains-themes"
jb_root="$HOME/.config/JetBrains"

if [[ ! -d "$staging" ]]; then
    echo "[$prefix] staging dir $staging missing, skipping" >&2
    exit 0
fi

if [[ ! -d "$jb_root" ]]; then
    echo "[$prefix] no JetBrains IDE config found at $jb_root, skipping" >&2
    exit 0
fi

shopt -s nullglob
ide_dirs=("$jb_root"/*/)
shopt -u nullglob

if [[ ${#ide_dirs[@]} -eq 0 ]]; then
    echo "[$prefix] no IDE versions under $jb_root, skipping" >&2
    exit 0
fi

copy_into() {
    local src="$1" dest_dir="$2"
    mkdir -p "$dest_dir"
    cp -f "$src" "$dest_dir/"
    echo "[$prefix] copied $(basename "$src") -> $dest_dir" >&2
}

shopt -s nullglob
for ide in "${ide_dirs[@]}"; do
    ide="${ide%/}"

    # color schemes: <IDE>/colors/
    for scheme in "$staging"/colors/*.icls; do
        copy_into "$scheme" "$ide/colors"
    done

    # code styles: <IDE>/codestyles/
    for style in "$staging"/codestyles/*.xml; do
        copy_into "$style" "$ide/codestyles"
    done

    # Material Theme UI plugin custom themes: <IDE>/materialCustomThemes/
    for mt in "$staging"/*.xml; do
        copy_into "$mt" "$ide/materialCustomThemes"
    done
done
shopt -u nullglob
