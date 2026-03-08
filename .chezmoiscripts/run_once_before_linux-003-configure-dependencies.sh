#!/bin/bash

set -euo pipefail

# https://github.com/sharkdp/bat/issues/982
echo "[configure-deps] symlinking batcat to bat..." >&2
mkdir -p ~/.local/bin
ln -sf /usr/bin/batcat ~/.local/bin/bat
echo "[configure-deps] done" >&2
