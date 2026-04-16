# shellcheck shell=bash
# Per-device shell credentials from 1Password.
# Device note "Device: <slug>" (vault: personal) stores credentials as fields
# with "cred:<NAME>" labels. Values are read directly from the device note.
# Credentials are also cached to ~/.cache/op-credentials.env (chmod 600, 24h TTL)
# so that non-interactive shells (MCPs, IDE subshells) can source them from .zshenv.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

reload-credentials() {
  if [[ "$1" == "--force" ]]; then
    export _OP_FORCE_RELOAD=1
  fi
  rm -f "$HOME/.cache/op-credentials.env" "$HOME/.cache/op-workspaces.env"
  source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
  source "$HOME/.scripts/linux-engineering-workspace-aliases.sh"
  unset _OP_FORCE_RELOAD
  echo "[credentials] reloaded from 1Password" >&2
}

_cred_cache="$HOME/.cache/op-credentials.env"

# use cache if fresh (< 24h) and non-empty — avoids all proot/op calls on most shell opens
if [[ -s "$_cred_cache" ]]; then
  _mtime=$(stat -c %Y "$_cred_cache" 2>/dev/null)
  _now=$(date +%s)
  if (( _now - _mtime < 86400 )); then
    source "$_cred_cache"
    unset _mtime _now _cred_cache
    return 0 2>/dev/null || true
  fi
  unset _mtime _now
fi

_on_credential() {
  # Always write to cache — other shells (non-interactive, child) source it via
  # .zshenv without calling 1Password. Skipping the write when the var is already
  # set leaks across shells: the var is inherited, the cache stays empty, and
  # the next shell has to re-fetch from 1Password.
  printf 'export %s=%q\n' "$1" "$2" >> "$_cred_cache"
  if [[ -v $1 ]] && [[ -z "$_OP_FORCE_RELOAD" ]]; then
    printf '[credentials] SKIP: "%s" (already set)\n' "$1" >&2
  else
    printf '[credentials] exporting "%s"\n' "$1" >&2
    export "${1}=${2}"
  fi
}

# create fresh cache file with restricted permissions
mkdir -p "$(dirname "$_cred_cache")"
rm -f "$_cred_cache"
install -m 600 /dev/null "$_cred_cache"

_op_load_references "credentials" "cred" _on_credential

# remove empty cache (loader failed to populate)
[[ -f "$_cred_cache" && ! -s "$_cred_cache" ]] && rm -f "$_cred_cache"

unset -f _on_credential
unset _cred_cache
