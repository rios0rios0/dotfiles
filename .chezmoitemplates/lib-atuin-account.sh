# shellcheck shell=bash
#
# The Atuin account on this device: the login every apply makes sure of, and the one-time import of
# the zsh-histdb history Atuin replaced. run_after_linux-016-login-atuin.sh.tmpl,
# run_after_linux-017-import-atuin-history.sh.tmpl and their Android twins (009, 010) pull this in;
# "Shell History (Atuin)" in CLAUDE.md lists the rules they keep.
#
# Neither ever fails the apply: every problem is a WARN followed by exit 0, so the next apply tries
# again. Neither puts a secret on a command line or the terminal: the password reaches `atuin login`
# in its environment (ATUIN_PASSWORD) and the key on its stdin.
#
#   atuin_ensure_login <username> <server device: true|false>
#       logs in when Atuin reports no session; the caller defines `atuin_secret <password|key>`,
#       which prints that field of the account's 1Password item, or fails
#   atuin_import_histdb <name for localhost, or ''> <host>...
#       imports the rows zsh-histdb recorded under those hosts, once per Atuin database and only
#       once logged in, then syncs them, on every apply until a sync succeeds

_atuin_prefix="atuin"

_atuin_info() { echo "[$_atuin_prefix] $*" >&2; }
_atuin_warn() { echo "[$_atuin_prefix] WARN: $*" >&2; }

# Atuin reports a missing session from its local meta store before it reaches the network. Logged
# in, `atuin status` asks the server who it is, so its timeouts are cut from 5 s and 30 s: an
# offline apply then waits seconds, not half a minute, and only learns that a session exists.
_atuin_not_logged_in() {
    local output
    if output="$(ATUIN_NETWORK_CONNECT_TIMEOUT=3 ATUIN_NETWORK_TIMEOUT=5 atuin status </dev/null 2>&1)"; then
        return 1
    fi
    [[ "$output" == *"You are not logged in to a sync server"* ]]
}

atuin_ensure_login() {
    local username="$1" is_server="$2" password key output
    command -v atuin >/dev/null 2>&1 || return 0
    _atuin_not_logged_in || return 0
    if [[ "$is_server" == "true" ]]; then
        _atuin_warn "this device runs the sync server and is not logged in to it; register the account by hand, once (.docs/atuin-sync.md, \"The account\")"
        return 0
    fi
    if ! password="$(atuin_secret password)" || [[ -z "$password" ]]; then
        _atuin_warn "could not read the Atuin password from 1Password; the next apply tries again"
        return 0
    fi
    if ! key="$(atuin_secret key)" || [[ -z "$key" ]]; then
        _atuin_warn "could not read the Atuin key from 1Password; the next apply tries again"
        return 0
    fi
    # `atuin login` reads ATUIN_PASSWORD when no --password is given, then the key as one line from
    # stdin: a pipe makes it non-interactive, so a wrong key fails instead of asking again.
    if output="$(printf '%s\n' "$key" | ATUIN_PASSWORD="$password" atuin login -u "$username" 2>&1)"; then
        _atuin_info "logged in to the sync server as $username"
    else
        _atuin_warn "atuin login failed ($(tail -n 1 <<<"$output")); the next apply tries again"
    fi
}

# The import runs in a subshell, so that its trap removes the private copy of the database however
# it ends. Every step that can fail is guarded: the callers run under errexit, which the subshell
# inherits, and a failure here must not fail the apply.
#
# Two markers make it once, in two steps. `atuin import` fills the local database alone and does not
# deduplicate, so `.dotfiles-histdb-imported` keeps it from running twice. Only an explicit `atuin
# sync` then adds the imported commands to the record store and uploads them -- the shell's
# background sync never does -- so `.dotfiles-histdb-synced` is written once that sync succeeded,
# and every apply before then tries it again. The import itself waits for a session: a marker
# written before the login would leave nothing to run the sync that uploads its commands. A device
# imported and synced by hand needs both markers created by hand.
atuin_import_histdb() (
    rename="$1"
    shift
    db="$HOME/.histdb/zsh-history.db"
    data="${ATUIN_HOME:-$HOME/.atuin}/data"
    imported="$data/.dotfiles-histdb-imported"
    synced="$data/.dotfiles-histdb-synced"

    command -v atuin >/dev/null 2>&1 || exit 0
    [[ ! -e "$synced" ]] || exit 0
    if [[ ! -e "$imported" && ! -s "$db" ]]; then
        { mkdir -p "$data" && printf 'nothing to import: no %s\n' "$db" >"$imported" &&
            printf 'nothing to sync: no %s\n' "$db" >"$synced"; } 2>/dev/null ||
            _atuin_warn "could not write $synced"
        exit 0
    fi
    if _atuin_not_logged_in; then
        _atuin_info "not logged in yet, so zsh-histdb's history waits for the apply after the login"
        exit 0
    fi

    if [[ ! -e "$imported" ]]; then
        if ! command -v sqlite3 >/dev/null 2>&1; then
            _atuin_warn "sqlite3 is not installed, so zsh-histdb's history waits for the next apply"
            exit 0
        fi

        # mktemp -d creates the directory private to this user, as the copy of the history needs.
        if ! work="$(mktemp -d)"; then
            _atuin_warn "could not create a private directory for the copy of $db; the next apply tries again"
            exit 0
        fi
        trap 'rm -rf "$work"' EXIT
        copy="$work/zsh-history.db"

        # A consistent copy, including what is still in the write-ahead log, in which the other hosts'
        # rows are deleted and Termux's `localhost` gets the device's name, as the shell now records it.
        hosts=""
        for host in "$@"; do
            hosts+="${hosts:+, }'${host//\'/\'\'}'"
        done
        if ! sqlite3 "$db" "VACUUM INTO '${copy//\'/\'\'}'" ||
            ! sqlite3 "$copy" "DELETE FROM history WHERE place_id NOT IN (SELECT id FROM places WHERE host IN ($hosts));"; then
            _atuin_warn "could not copy $db; the next apply tries again"
            exit 0
        fi
        if [[ -n "$rename" ]] &&
            ! sqlite3 "$copy" "UPDATE places SET host = '${rename//\'/\'\'}' WHERE host = 'localhost';"; then
            _atuin_warn "could not name localhost's commands after this device; the next apply tries again"
            exit 0
        fi
        count="$(sqlite3 "$copy" "SELECT COUNT(*) FROM history;" 2>/dev/null)" || count="the"

        if ! output="$(HISTDB_FILE="$copy" atuin import zsh-hist-db </dev/null 2>&1)"; then
            _atuin_warn "atuin import failed ($(tail -n 1 <<<"$output")); the next apply tries again"
            exit 0
        fi
        if ! { mkdir -p "$data" &&
            printf 'imported %s commands recorded under %s, %s\n' "$count" "$*" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$imported"; } 2>/dev/null; then
            _atuin_warn "imported, but could not write $imported: create it by hand, or the next apply imports the same commands again"
            exit 0
        fi
        _atuin_info "imported $count commands from zsh-histdb, recorded under $*"
    fi

    # The explicit sync that adds the imported commands to the record store and uploads them. Atuin's
    # shell hook exports ATUIN_SESSION, which a non-interactive shell lacks, and without it the sync's
    # history-store initialisation fails.
    if ! ATUIN_SESSION="$(atuin uuid)" atuin sync </dev/null >/dev/null 2>&1; then
        _atuin_warn "atuin sync failed, so zsh-histdb's history reaches the server with a later apply's sync"
        exit 0
    fi
    { printf 'synced %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$synced"; } 2>/dev/null ||
        _atuin_warn "synced, but could not write $synced; the next apply syncs once more"
    _atuin_info "synced zsh-histdb's history with the server"
)
