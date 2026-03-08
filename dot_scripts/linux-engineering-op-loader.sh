# Shared 1Password reference loader for per-device items.
# Iterates REFERENCE fields in a central 1Password item, filters by device slug,
# and calls a user-provided callback for each matching entry.
#
# Usage:
#   source "$HOME/.scripts/linux-engineering-op-loader.sh"
#   _on_match() { export "${1}=${2}"; }
#   _op_load_references "credentials" "Active Shell Credentials" _on_match
#   unset -f _on_match

_op_load_references() {
  local _ol_prefix="$1"
  local _ol_item="$2"
  local _ol_callback="$3"

  _ol_log() { printf '[%s] %s\n' "$_ol_prefix" "$*" >&2; }

  if ! command -v op &>/dev/null; then
    _ol_log "SKIP: 'op' command not found"
    unset -f _ol_log
    return 0
  fi
  if ! command -v jq &>/dev/null; then
    _ol_log "SKIP: 'jq' command not found"
    unset -f _ol_log
    return 0
  fi

  local _ol_device
  if [[ -n "$CHEZMOI_DEVICE" ]]; then
    _ol_device="$CHEZMOI_DEVICE"
  else
    _ol_device="$(hostname)"
  fi

  local _ol_slug
  _ol_slug=$(printf '%s' "$_ol_device" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/-/g' \
    | tr '[:upper:]' '[:lower:]')

  _ol_log "device='$_ol_device' slug='$_ol_slug'"

  local _ol_json
  if ! _ol_json=$(op item get "$_ol_item" --vault personal --account my --format json 2>&1); then
    _ol_log "ERROR: failed to fetch '$_ol_item': $_ol_json"
    unset -f _ol_log
    return 0
  fi

  local _ol_refs
  _ol_refs=$(printf '%s' "$_ol_json" | jq -r '.fields[]? | select(.type == "REFERENCE") | .value' 2>/dev/null)
  if [[ -z "$_ol_refs" ]]; then
    _ol_log "WARN: no REFERENCE fields found in '$_ol_item'"
    unset -f _ol_log
    return 0
  fi

  local _ol_loaded=0
  local _ol_skipped=0
  local _ol_ref _ol_entry _ol_title _ol_value

  while IFS= read -r _ol_ref; do
    [[ -z "$_ol_ref" ]] && continue

    if ! _ol_entry=$(op item get "$_ol_ref" --account my --format json 2>&1); then
      _ol_log "WARN: failed to fetch referenced item '$_ol_ref': $_ol_entry"
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi
    [[ -z "$_ol_entry" ]] && { _ol_skipped=$((_ol_skipped + 1)); continue; }

    _ol_title=$(printf '%s' "$_ol_entry" | jq -r '.title // empty' 2>/dev/null)
    if [[ "$_ol_title" != *@* ]]; then
      _ol_log "SKIP: item title '$_ol_title' has no '@' separator"
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi

    # silent skip for items belonging to other devices
    if [[ "${_ol_title%%@*}" != "$_ol_slug" ]]; then
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi

    _ol_value=$(printf '%s' "$_ol_entry" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
    if [[ -n "$_ol_value" ]]; then
      "$_ol_callback" "${_ol_title#*@}" "$_ol_value"
      _ol_loaded=$((_ol_loaded + 1))
    else
      _ol_log "WARN: no credential/password field in item '${_ol_title#*@}'"
      _ol_skipped=$((_ol_skipped + 1))
    fi
  done <<< "$_ol_refs"

  _ol_log "done: $_ol_loaded loaded, $_ol_skipped skipped"
  unset -f _ol_log
}
