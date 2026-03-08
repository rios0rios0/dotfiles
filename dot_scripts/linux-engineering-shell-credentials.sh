# Per-device shell credentials from 1Password.
# Central item "Active Shell Credentials" (vault: personal) with titles in notesPlain.
# Referenced items: title "<device-slug>@<ENV_VAR_NAME>", field "credential"/"password" = secret value.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

_on_credential() { export "${1}=${2}"; }
_op_load_references "credentials" "Active Shell Credentials" _on_credential
unset -f _on_credential
