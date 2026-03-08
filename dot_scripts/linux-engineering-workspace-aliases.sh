# Per-device workspace aliases from 1Password.
# Central item "Active Workspaces" (vault: personal) with REFERENCE fields.
# Referenced items: title "<device-slug>@<alias-name>", field "credential"/"password" = directory path.

_wa_log() { printf '[workspaces] %s\n' "$*" >&2; }

if ! command -v op &>/dev/null; then
  _wa_log "SKIP: 'op' command not found"
  unset -f _wa_log
  return 0 2>/dev/null; exit 0
fi
if ! command -v jq &>/dev/null; then
  _wa_log "SKIP: 'jq' command not found"
  unset -f _wa_log
  return 0 2>/dev/null; exit 0
fi

if [[ -n "$CHEZMOI_DEVICE" ]]; then
  _wa_device="$CHEZMOI_DEVICE"
else
  _wa_device="$(hostname)"
fi

_wa_slug=$(printf '%s' "$_wa_device" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/-/g' \
  | tr '[:upper:]' '[:lower:]')

_wa_log "device='$_wa_device' slug='$_wa_slug'"

if ! _wa_json=$(op item get "Active Workspaces" --vault personal --account my --format json 2>&1); then
  _wa_log "ERROR: failed to fetch 'Active Workspaces': $_wa_json"
  unset _wa_device _wa_slug _wa_json
  unset -f _wa_log
  return 0 2>/dev/null; exit 0
fi

_wa_refs=$(printf '%s' "$_wa_json" | jq -r '.fields[]? | select(.type == "REFERENCE") | .value' 2>/dev/null)
if [[ -z "$_wa_refs" ]]; then
  _wa_log "WARN: no REFERENCE fields found in 'Active Workspaces'"
  unset _wa_device _wa_slug _wa_json _wa_refs
  unset -f _wa_log
  return 0 2>/dev/null; exit 0
fi

_wa_loaded=0
_wa_skipped=0
while IFS= read -r _wa_ref; do
  [[ -z "$_wa_ref" ]] && continue

  if ! _wa_item=$(op item get "$_wa_ref" --account my --format json 2>&1); then
    _wa_log "WARN: failed to fetch referenced item '$_wa_ref': $_wa_item"
    _wa_skipped=$((_wa_skipped + 1))
    continue
  fi
  [[ -z "$_wa_item" ]] && { _wa_skipped=$((_wa_skipped + 1)); continue; }

  _wa_title=$(printf '%s' "$_wa_item" | jq -r '.title // empty' 2>/dev/null)
  if [[ "$_wa_title" != *@* ]]; then
    _wa_log "SKIP: item title '$_wa_title' has no '@' separator"
    _wa_skipped=$((_wa_skipped + 1))
    continue
  fi

  # silent skip for items belonging to other devices
  if [[ "${_wa_title%%@*}" != "$_wa_slug" ]]; then
    _wa_skipped=$((_wa_skipped + 1))
    continue
  fi

  _wa_path=$(printf '%s' "$_wa_item" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
  if [[ -n "$_wa_path" ]]; then
    alias "${_wa_title#*@}=cd ${_wa_path}"
    _wa_loaded=$((_wa_loaded + 1))
  else
    _wa_log "WARN: no credential/password field in item '${_wa_title#*@}'"
    _wa_skipped=$((_wa_skipped + 1))
  fi
done <<< "$_wa_refs"

_wa_log "done: $_wa_loaded loaded, $_wa_skipped skipped"

unset _wa_device _wa_slug _wa_json _wa_refs _wa_ref _wa_item _wa_title _wa_path _wa_loaded _wa_skipped
unset -f _wa_log
