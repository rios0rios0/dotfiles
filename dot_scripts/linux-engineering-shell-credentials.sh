# Per-device shell credentials from 1Password.
# Central item "Active Shell Credentials" (vault: personal) with titles in notesPlain.
# Referenced items: title "<device-slug>@<ENV_VAR_NAME>", field "credential"/"password" = secret value.
# Credentials are also cached to ~/.cache/op-credentials.env (chmod 600, 24h TTL)
# so that non-interactive shells (MCPs, IDE subshells) can source them from .zshenv.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

reload-credentials() {
  rm -f "$HOME/.cache/op-credentials.env" "$HOME/.cache/op-workspaces.env"
  source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
  source "$HOME/.scripts/linux-engineering-workspace-aliases.sh"
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
  if [[ -z "${!1+x}" ]]; then
    export "${1}=${2}"
    printf 'export %s=%q\n' "$1" "$2" >> "$_cred_cache"
  fi
}

# create fresh cache file with restricted permissions
mkdir -p "$(dirname "$_cred_cache")"
rm -f "$_cred_cache"
install -m 600 /dev/null "$_cred_cache"

_op_load_references "credentials" "Active Shell Credentials" _on_credential

# remove empty cache (loader failed to populate)
[[ -f "$_cred_cache" && ! -s "$_cred_cache" ]] && rm -f "$_cred_cache"

unset -f _on_credential
unset _cred_cache
