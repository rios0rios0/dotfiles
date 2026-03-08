# Per-device shell credentials from 1Password.
# Central item "Active Shell Credentials" (vault: personal) with REFERENCE fields.
# Referenced items: title "<device-slug>@<ENV_VAR_NAME>", field "credential"/"password" = secret value.

command -v op &>/dev/null || { return 0 2>/dev/null; exit 0; }
command -v jq &>/dev/null || { return 0 2>/dev/null; exit 0; }

if [[ -n "$CHEZMOI_DEVICE" ]]; then
  _sc_device="$CHEZMOI_DEVICE"
else
  _sc_device="$(hostname)"
fi

_sc_slug=$(printf '%s' "$_sc_device" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/-/g' \
  | tr '[:upper:]' '[:lower:]')

_sc_json=$(op item get "Active Shell Credentials" --vault personal --account my --format json 2>/dev/null)
if [[ -n "$_sc_json" ]]; then
  while IFS= read -r _sc_ref; do
    [[ -z "$_sc_ref" ]] && continue
    _sc_item=$(op item get "$_sc_ref" --account my --format json 2>/dev/null)
    [[ -z "$_sc_item" ]] && continue
    _sc_title=$(printf '%s' "$_sc_item" | jq -r '.title // empty' 2>/dev/null)
    [[ "$_sc_title" != *@* ]] && continue
    [[ "${_sc_title%%@*}" != "$_sc_slug" ]] && continue
    _sc_value=$(printf '%s' "$_sc_item" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
    [[ -n "$_sc_value" ]] && export "${_sc_title#*@}=${_sc_value}"
  done <<< "$(printf '%s' "$_sc_json" | jq -r '.fields[]? | select(.type == "REFERENCE") | .value' 2>/dev/null)"
fi

unset _sc_device _sc_slug _sc_json _sc_ref _sc_item _sc_title _sc_value
