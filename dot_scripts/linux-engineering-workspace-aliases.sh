# Per-device workspace aliases from 1Password.
# Central item "Active Workspaces" (vault: personal) with REFERENCE fields.
# Referenced items: title "<device-slug>@<alias-name>", field "credential"/"password" = directory path.

command -v op &>/dev/null || { return 0 2>/dev/null; exit 0; }
command -v jq &>/dev/null || { return 0 2>/dev/null; exit 0; }

if [[ -n "$CHEZMOI_DEVICE" ]]; then
  _wa_device="$CHEZMOI_DEVICE"
else
  _wa_device="$(hostname)"
fi

_wa_slug=$(printf '%s' "$_wa_device" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/-/g' \
  | tr '[:upper:]' '[:lower:]')

_wa_json=$(op item get "Active Workspaces" --vault personal --account my --format json 2>/dev/null)
if [[ -n "$_wa_json" ]]; then
  while IFS= read -r _wa_ref; do
    [[ -z "$_wa_ref" ]] && continue
    _wa_item=$(op item get "$_wa_ref" --account my --format json 2>/dev/null)
    [[ -z "$_wa_item" ]] && continue
    _wa_title=$(printf '%s' "$_wa_item" | jq -r '.title // empty' 2>/dev/null)
    [[ "$_wa_title" != *@* ]] && continue
    [[ "${_wa_title%%@*}" != "$_wa_slug" ]] && continue
    _wa_path=$(printf '%s' "$_wa_item" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
    [[ -n "$_wa_path" ]] && alias "${_wa_title#*@}=cd ${_wa_path}"
  done <<< "$(printf '%s' "$_wa_json" | jq -r '.fields[]? | select(.type == "REFERENCE") | .value' 2>/dev/null)"
fi

unset _wa_device _wa_slug _wa_json _wa_ref _wa_item _wa_title _wa_path
