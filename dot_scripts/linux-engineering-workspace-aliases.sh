# shellcheck shell=bash
# Per-device workspace aliases from 1Password.
# Device note "Device: <slug>" (vault: personal) stores workspace paths as fields
# with "ws:<NAME>" labels. Values are read directly from the device note.
# Aliases are also cached to ~/.cache/op-workspaces.env (chmod 600, 24h TTL)
# so that non-interactive shells and subsequent interactive shells can skip 1Password calls.
#
# Deleting a workspace from 1Password has to remove its alias too, which a
# rewritten cache cannot do on its own — the alias is already defined in this
# shell. Each load records the names it defined in $_OP_WS_NAMES, and any name
# carried in but absent from a later successful load is unaliased. See
# linux-engineering-shell-credentials.sh for the same mechanism on credentials.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

_ws_cache="$HOME/.cache/op-workspaces.env"

# every workspace this loader is known to have defined: the manifest inherited
# through the environment, plus the names the cache on disk still assigns
_op_read_cache_names "$_ws_cache" "alias"
_ws_previous="${_OP_WS_NAMES-} $_OP_CACHE_NAMES"

# use cache if fresh (< 24h) and non-empty — avoids all proot/op calls on most shell opens
if [[ -s "$_ws_cache" && -z "$_OP_RELOAD" ]]; then
  _mtime=$(stat -c %Y "$_ws_cache" 2>/dev/null)
  _now=$(date +%s)
  if (( _now - _mtime < 86400 )); then
    source "$_ws_cache"
    export _OP_WS_NAMES="$_OP_CACHE_NAMES"
    _op_prune_removed "workspaces" "$_ws_previous" "$_OP_CACHE_NAMES" _op_forget_alias
    unset _mtime _now _ws_cache _ws_previous _OP_CACHE_NAMES
    return 0 2>/dev/null || true
  fi
  unset _mtime _now
fi

_ws_names=""

# shellcheck disable=SC2317
_on_workspace() {
  # Always write to cache — keeps behavior consistent with shell-credentials.sh
  # and guarantees the file is populated whether or not the alias exists.
  printf 'alias %s=%q\n' "$1" "cd ${2}" >> "$_ws_cache"
  _ws_names="${_ws_names:+$_ws_names }$1"
  if alias "$1" &>/dev/null && [[ -z "$_OP_FORCE_RELOAD" ]]; then
    printf '[workspaces] SKIP: alias "%s" (already set)\n' "$1" >&2
  else
    printf '[workspaces] creating alias "%s"\n' "$1" >&2
    # shellcheck disable=SC2139
    alias "${1}=cd ${2}"
  fi
}

# create fresh cache file with restricted permissions
mkdir -p "$(dirname "$_ws_cache")"
rm -f "$_ws_cache"
install -m 600 /dev/null "$_ws_cache"

if _op_load_references "workspaces" "ws" _on_workspace; then
  printf 'export _OP_WS_NAMES=%q\n' "$_ws_names" >> "$_ws_cache"
  export _OP_WS_NAMES="$_ws_names"
  _op_prune_removed "workspaces" "$_ws_previous" "$_ws_names" _op_forget_alias
else
  # 1Password was unreachable: discard the half-written cache and keep the
  # aliases this shell already has
  rm -f "$_ws_cache"
fi

unset -f _on_workspace
unset _ws_cache _ws_names _ws_previous _OP_CACHE_NAMES
