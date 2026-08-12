# shellcheck shell=bash
# Per-device shell credentials from 1Password.
# Device note "Device: <slug>" (vault: personal) stores credentials as fields
# with "cred:<NAME>" labels. Values are read directly from the device note.
# Credentials are also cached to ~/.cache/op-credentials.env (chmod 600, 24h TTL)
# so that non-interactive shells (MCPs, IDE subshells) can source them from .zshenv.
#
# Deleting a credential from 1Password has to remove it from the shell too, and
# rewriting the cache cannot do that on its own: the variable is already exported,
# so it outlives the cache in this shell and in every shell forked from it. Each
# load therefore records the names it exported in $_OP_CRED_NAMES, which travels
# with the environment; any name carried in but absent from a later successful
# load is unset. dot_zshenv.tmpl runs the same prune for non-interactive shells.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

reload-credentials() {
  # The TTL fast path is bypassed with a flag rather than by deleting the caches,
  # so the reload below can still read the names the current cache exported. That
  # is what lets credentials written by an older revision — which recorded no
  # $_OP_CRED_NAMES — be recognised as ours and unset when they disappear.
  #
  # Deliberately not exported: both scripts are sourced into this same shell, so
  # nothing else needs to see it, and an interrupted reload would otherwise leave
  # every child shell bypassing the cache and calling 1Password on each start.
  _OP_RELOAD=1
  if [[ "$1" == "--force" ]]; then
    export _OP_FORCE_RELOAD=1
  fi
  source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
  source "$HOME/.scripts/linux-engineering-workspace-aliases.sh"
  unset _OP_RELOAD _OP_FORCE_RELOAD
  echo "[credentials] reloaded from 1Password" >&2
}

_cred_cache="$HOME/.cache/op-credentials.env"

# Every credential this loader is known to have exported: the manifest inherited
# through the environment, plus the names the cache on disk still assigns (which
# covers caches written before the manifest existed).
_op_read_cache_names "$_cred_cache" "export"
_cred_previous="${_OP_CRED_NAMES-} $_OP_CACHE_NAMES"

# use cache if fresh (< 24h) and non-empty — avoids all proot/op calls on most shell opens
if [[ -s "$_cred_cache" && -z "$_OP_RELOAD" ]]; then
  _mtime=$(stat -c %Y "$_cred_cache" 2>/dev/null)
  _now=$(date +%s)
  if (( _now - _mtime < 86400 )); then
    source "$_cred_cache"
    # the cache was produced by a successful fetch, so what it assigns is the
    # authoritative set — anything inherited beyond it was deleted from the vault
    export _OP_CRED_NAMES="$_OP_CACHE_NAMES"
    _op_prune_removed "credentials" "$_cred_previous" "$_OP_CACHE_NAMES" _op_forget_variable
    unset _mtime _now _cred_cache _cred_previous _OP_CACHE_NAMES
    return 0 2>/dev/null || true
  fi
  unset _mtime _now
fi

_cred_names=""

_on_credential() {
  # Always write to cache — other shells (non-interactive, child) source it via
  # .zshenv without calling 1Password. Skipping the write when the var is already
  # set leaks across shells: the var is inherited, the cache stays empty, and
  # the next shell has to re-fetch from 1Password.
  printf 'export %s=%q\n' "$1" "$2" >> "$_cred_cache"
  _cred_names="${_cred_names:+$_cred_names }$1"
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

if _op_load_references "credentials" "cred" _on_credential; then
  # Recording the manifest in the cache lets .zshenv prune inherited credentials
  # by sourcing the file alone, without re-reading it to work out what it owns.
  printf 'export _OP_CRED_NAMES=%q\n' "$_cred_names" >> "$_cred_cache"
  export _OP_CRED_NAMES="$_cred_names"
  _op_prune_removed "credentials" "$_cred_previous" "$_cred_names" _op_forget_variable
else
  # 1Password was unreachable: discard the half-written cache and keep whatever
  # the environment already holds — a failed fetch is not evidence of a removal
  rm -f "$_cred_cache"
fi

unset -f _on_credential
unset _cred_cache _cred_names _cred_previous _OP_CACHE_NAMES
