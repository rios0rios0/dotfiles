# shellcheck shell=bash
# Per-device workspace aliases from 1Password.
# Central item "Active Workspaces" (vault: personal) with titles in notesPlain.
# Referenced items: title "<device-slug>@<alias-name>", field "credential"/"password" = directory path.
# Aliases are also cached to ~/.cache/op-workspaces.env (chmod 600, 24h TTL)
# so that non-interactive shells and subsequent interactive shells can skip 1Password calls.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

_ws_cache="$HOME/.cache/op-workspaces.env"

# use cache if fresh (< 24h) and non-empty — avoids all proot/op calls on most shell opens
if [[ -s "$_ws_cache" ]]; then
  _mtime=$(stat -c %Y "$_ws_cache" 2>/dev/null)
  _now=$(date +%s)
  if (( _now - _mtime < 86400 )); then
    source "$_ws_cache"
    unset _mtime _now _ws_cache
    return 0 2>/dev/null || true
  fi
  unset _mtime _now
fi

# shellcheck disable=SC2317
_on_workspace() {
  if alias "$1" &>/dev/null && [[ -z "$_OP_FORCE_RELOAD" ]]; then
    printf '[workspaces] SKIP: alias "%s" (already set)\n' "$1" >&2
  else
    printf '[workspaces] creating alias "%s"\n' "$1" >&2
    # shellcheck disable=SC2139
    alias "${1}=cd ${2}"
    printf 'alias %s=%q\n' "$1" "cd ${2}" >> "$_ws_cache"
  fi
}

# create fresh cache file with restricted permissions
mkdir -p "$(dirname "$_ws_cache")"
rm -f "$_ws_cache"
install -m 600 /dev/null "$_ws_cache"

_op_load_references "workspaces" "Active Workspaces" _on_workspace

# remove empty cache (loader failed to populate)
[[ -f "$_ws_cache" && ! -s "$_ws_cache" ]] && rm -f "$_ws_cache"

unset -f _on_workspace
unset _ws_cache
