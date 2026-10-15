#!/bin/bash

# Moves claude-local's profile to claude-omni's, once, so its transcripts, audits, trust answers
# and saved /model choice carry over to the launcher that replaced it. It runs before chezmoi
# writes the look into ~/.claude-omni/settings.json, which would otherwise create the new profile
# empty first. See CLAUDE.md, "Claude Code Through OmniRoute (claude-omni)".
#
# Nothing is merged: when both directories exist, the new one stays as it is and the old one is
# left in place for a person to compare, with a line saying so.

set -euo pipefail

prefix="claude-omni"
old="$HOME/.claude-local"
new="$HOME/.claude-omni"

[[ -d "$old" ]] || exit 0
if [[ -e "$new" ]]; then
    echo "[$prefix] WARN: both $old and $new exist; left $old in place for you to compare" >&2
    exit 0
fi
mv "$old" "$new"
echo "[$prefix] moved $old to $new" >&2
