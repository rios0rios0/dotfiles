# Shared 1Password notes-based loader for per-device items.
# Reads item titles from the notesPlain field of a central 1Password item,
# filters by device slug locally (no API call), then fetches only matching items.
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

  # ensure 1Password is authenticated before making API calls
  if ! op whoami --account my &>/dev/null; then
    if [[ -z "$_OP_SIGNIN_ATTEMPTED" ]]; then
      export _OP_SIGNIN_ATTEMPTED=1
      _ol_log "not signed in, attempting signin..."
      local _ol_signin_output
      if ! _ol_signin_output=$(op signin --account my); then
        _ol_log "ERROR: could not sign in to 1Password (unlock the desktop app or run 'op signin --account my')"
        unset -f _ol_log
        return 0
      fi
      eval "$_ol_signin_output"
    else
      _ol_log "ERROR: 1Password not authenticated (signin already attempted)"
      unset -f _ol_log
      return 0
    fi
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

  local _ol_notes
  _ol_notes=$(printf '%s' "$_ol_json" | jq -r '.fields[]? | select(.label == "notesPlain") | .value // empty' 2>/dev/null)
  if [[ -z "$_ol_notes" ]]; then
    _ol_log "WARN: no notesPlain field found in '$_ol_item'"
    unset -f _ol_log
    return 0
  fi

  local _ol_loaded=0
  local _ol_skipped=0
  local _ol_title _ol_entry _ol_value

  while IFS= read -r _ol_title; do
    # trim whitespace
    _ol_title="${_ol_title#"${_ol_title%%[![:space:]]*}"}"
    _ol_title="${_ol_title%"${_ol_title##*[![:space:]]}"}"
    [[ -z "$_ol_title" ]] && continue

    if [[ "$_ol_title" != *@* ]]; then
      _ol_log "SKIP: title '$_ol_title' has no '@' separator"
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi

    # skip items belonging to other devices (no API call needed)
    if [[ "${_ol_title%%@*}" != "$_ol_slug" ]]; then
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi

    if ! _ol_entry=$(op item get "$_ol_title" --vault private --account my --format json 2>&1); then
      _ol_log "WARN: failed to fetch item '$_ol_title': $_ol_entry"
      _ol_skipped=$((_ol_skipped + 1))
      continue
    fi
    [[ -z "$_ol_entry" ]] && { _ol_skipped=$((_ol_skipped + 1)); continue; }

    _ol_value=$(printf '%s' "$_ol_entry" | jq -r '(.fields[]? | select(.id == "credential" or .id == "password") | .value) // empty' 2>/dev/null | head -1)
    if [[ -n "$_ol_value" ]]; then
      "$_ol_callback" "${_ol_title#*@}" "$_ol_value"
      _ol_loaded=$((_ol_loaded + 1))
    else
      _ol_log "WARN: no credential/password field in item '${_ol_title#*@}'"
      _ol_skipped=$((_ol_skipped + 1))
    fi
  done <<< "$_ol_notes"

  _ol_log "done: $_ol_loaded loaded, $_ol_skipped skipped"
  unset -f _ol_log
}
