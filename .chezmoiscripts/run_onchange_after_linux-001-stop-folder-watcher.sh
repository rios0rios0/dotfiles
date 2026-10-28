#!/bin/bash

# Stops the retired folder watcher on a machine that still runs one. The watcher
# (dot_scripts/executable_linux-toolbox-watch-compress-folders.sh) and its launcher were removed
# in PR #276, and `.chezmoiremove` deletes the deployed script, but a copy already started with
# `nohup` from a long-lived interactive shell keeps running: its `inotifywait` loop re-runs
# `chezmoi add --encrypt` on every change under ~/.john, ~/.kube/config-files and ~/.sqlmap,
# which puts the very files that PR back into the chezmoi source. The deleted first-apply
# extractor used to kill it (its line 49); this does the same, once.
#
# run_onchange_: keyed on this file's content, so it fires on the apply that introduces it and
# not again. A machine with no watcher running is a silent no-op.

set -euo pipefail

watcher="$HOME/.scripts/linux-toolbox-watch-compress-folders.sh"
if pkill -f "$watcher" 2>/dev/null; then
    echo "[stop-folder-watcher] stopped a running folder watcher" >&2
fi

# Clear its single-instance state so nothing trips over a stale lock or PID later.
rm -f /tmp/linux-toolbox-watch-compress-folders.lock \
      /tmp/linux-toolbox-watch-compress-folders.pid \
      /tmp/linux-toolbox-watch-compress-folders.log
