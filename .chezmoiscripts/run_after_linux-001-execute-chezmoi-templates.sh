#!/bin/bash

TEMPLATES=(".scripts/linux-engineering-workspace-information-template.sh")
for template in "${TEMPLATES[@]}"; do
  echo "Executing Chezmoi template on \"$template\"..."
  file=$(echo "$template" | sed "s*-template**")
  cat "$HOME/$template" | chezmoi execute-template > "$HOME/$file"
done
