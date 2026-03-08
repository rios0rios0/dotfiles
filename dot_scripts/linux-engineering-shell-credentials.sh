# Per-device shell credentials from 1Password.
# Central item "Active Shell Credentials" (vault: personal) with titles in notesPlain.
# Referenced items: title "<device-slug>@<ENV_VAR_NAME>", field "credential"/"password" = secret value.
# Credentials are also cached to ~/.cache/op-credentials.env (chmod 600, 24h TTL)
# so that non-interactive shells (MCPs, IDE subshells) can source them from .zshenv.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

_cred_cache="$HOME/.cache/op-credentials.env"

_on_credential() {
  export "${1}=${2}"
  # append to cache file (created fresh each interactive session)
  printf 'export %s=%q\n' "$1" "$2" >> "$_cred_cache"
}

# create fresh cache file with restricted permissions
mkdir -p "$(dirname "$_cred_cache")"
rm -f "$_cred_cache"
install -m 600 /dev/null "$_cred_cache"

_op_load_references "credentials" "Active Shell Credentials" _on_credential

unset -f _on_credential
unset _cred_cache
