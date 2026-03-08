# Per-device shell credentials from 1Password.
# Central item "Active Shell Credentials" (vault: personal) with REFERENCE fields.
# Referenced items: title "<device-slug>@<ENV_VAR_NAME>", field "credential"/"password" = secret value.

_sc_log() { printf '[credentials] %s\n' "$*" >&2; }

if ! command -v op &>/dev/null; then
  _sc_log "SKIP: 'op' command not found"
  unset -f _sc_log
  return 0 2>/dev/null; exit 0
fi
if ! command -v jq &>/dev/null; then
  _sc_log "SKIP: 'jq' command not found"
  unset -f _sc_log
  return 0 2>/dev/null; exit 0
fi

if [[ -n "$CHEZMOI_DEVICE" ]]; then
  _sc_device="$CHEZMOI_DEVICE"
else
  _sc_device="$(hostname)"
fi

_sc_slug=$(printf '%s' "$_sc_device" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/-/g' \
  | tr '[:upper:]' '[:lower:]')

_sc_log "device='$_sc_device' slug='$_sc_slug'"

if ! _sc_json=$(op item get "Active Shell Credentials" --vault personal --account my --format json 2>&1); then
  _sc_log "ERROR: failed to fetch 'Active Shell Credentials': $_sc_json"
  unset _sc_device _sc_slug _sc_json
  unset -f _sc_log
  return 0 2>/dev/null; exit 0
fi

_sc_refs=$(printf '%s' "$_sc_json" | jq -r '.fields[]? | select(.type == "REFERENCE") | .value' 2>/dev/null)
if [[ -z "$_sc_refs" ]]; then
  _sc_log "WARN: no REFERENCE fields found in 'Active Shell Credentials'"
  unset _sc_device _sc_slug _sc_json _sc_refs
  unset -f _sc_log
  return 0 2>/dev/null; exit 0
fi

_sc_loaded=0
_sc_skipped=0
while IFS= read -r _sc_ref; do
  [[ -z "$_sc_ref" ]] && continue

  if ! _sc_item=$(op item get "$_sc_ref" --account my --format json 2>&1); then
    _sc_log "WARN: failed to fetch referenced item '$_sc_ref': $_sc_item"
    _sc_skipped=$((_sc_skipped + 1))
    continue
  fi
  [[ -z "$_sc_item" ]] && { _sc_skipped=$((_sc_skipped + 1)); continue; }

  _sc_title=$(printf '%s' "$_sc_item" | jq -r '.title // empty' 2>/dev/null)
  if [[ "$_sc_title" != *@* ]]; then
    _sc_log "SKIP: item title '$_sc_title' has no '@' separator"
    _sc_skipped=$((_sc_skipped + 1))
    continue
  fi

  # silent skip for items belonging to other devices
  if [[ "${_sc_title%%@*}" != "$_sc_slug" ]]; then
    _sc_skipped=$((_sc_skipped + 1))
    continue
  fi

  _sc_value=$(printf '%s' "$_sc_item" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
  if [[ -n "$_sc_value" ]]; then
    export "${_sc_title#*@}=${_sc_value}"
    _sc_loaded=$((_sc_loaded + 1))
  else
    _sc_log "WARN: no credential/password field in item '${_sc_title#*@}'"
    _sc_skipped=$((_sc_skipped + 1))
  fi
done <<< "$_sc_refs"

_sc_log "done: $_sc_loaded loaded, $_sc_skipped skipped"

unset _sc_device _sc_slug _sc_json _sc_refs _sc_ref _sc_item _sc_title _sc_value _sc_loaded _sc_skipped
unset -f _sc_log
