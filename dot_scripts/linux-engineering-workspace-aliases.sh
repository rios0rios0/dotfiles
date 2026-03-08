# Per-device workspace aliases from 1Password.
# Central item "Active Workspaces" (vault: personal) with REFERENCE fields.
# Referenced items: title "<device-slug>@<alias-name>", field "credential"/"password" = directory path.

source "$HOME/.scripts/linux-engineering-op-loader.sh"

_on_workspace() { alias "${1}=cd ${2}"; }
_op_load_references "workspaces" "Active Workspaces" _on_workspace
unset -f _on_workspace
