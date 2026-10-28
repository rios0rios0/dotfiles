# shellcheck shell=bash
# Shared by omniroute-backup, omniroute-restore and run_after_linux-015-start-omniroute.sh.tmpl,
# which include it as a chezmoi template, so it must stay pure bash, without template directives.
# The backup writes archives where the restore and the start script look for them, and carries the
# secrets the restore puts back, so all three take both from here rather than from three copies.

# The keys of the stack's secrets that travel with an archive and come back with a restore: what
# local-services/omniroute/.env sets, and what OmniRoute's bootstrap persists to server.env --
# including the two OAuth client secrets it says may be set there. Nothing else from either file is
# carried or restored: bootstrap merges server.env into the gateway's environment, so a key it never
# writes there (NODE_OPTIONS, say) would run inside the gateway.
OMNIROUTE_ENV_KEYS='JWT_SECRET|API_KEY_SECRET|STORAGE_ENCRYPTION_KEY|STORAGE_ENCRYPTION_KEY_VERSION|INITIAL_PASSWORD|OMNIROUTE_CA_BUNDLE|ANTIGRAVITY_OAUTH_CLIENT_SECRET|QODER_OAUTH_CLIENT_SECRET'

# The names omniroute-backup gives its archives. Anything else in a backup folder is left alone.
OMNIROUTE_ARCHIVE_RE='^omniroute-[0-9]{8}T[0-9]{6}Z\.tar\.age$'

# The CA bundle the Compose file mounts when .env names none: the host's own, present on every
# Linux machine, so an archive never carries it.
OMNIROUTE_DEFAULT_CA_BUNDLE='/etc/ssl/certs/ca-certificates.crt'

# Prints Windows' environment variable $1 as a WSL path. Returns 2 when this is not WSL (no
# cmd.exe) and 1 when the variable is unset. cmd.exe is looked up on PATH and then where Windows
# keeps it, because a systemd unit's PATH holds none of Windows' directories; it prints an unset
# variable back as %NAME%, and its warning about starting in a WSL (UNC) directory goes to stderr.
omniroute_windows_path() {
    local variable="$1" cmd value
    cmd="$(command -v cmd.exe 2>/dev/null)" || cmd="/mnt/c/Windows/System32/cmd.exe"
    [[ -x "$cmd" ]] || return 2
    value="$("$cmd" /d /c "echo %$variable%" 2>/dev/null | tr -d '\r')" || return 1
    [[ -n "$value" && "$value" != "%$variable%" ]] || return 1
    wslpath -u "$value" 2>/dev/null || return 1
}

# Resolves the mirror setting $1 (.chezmoidata/omniroute.yaml, backup.mirror) into
# OMNIROUTE_MIRROR_ROOT, the folder that holds one folder of archives per device, or explains in
# OMNIROUTE_MIRROR_ERROR why there is none. Globals rather than stdout, so a caller keeps the reason.
#
# 'onedrive-personal' reads %OneDriveConsumer%, which only the personal account sets. %OneDrive%
# names whichever account signed in last -- on a machine also signed in to a work account, that
# one -- so it is never read: the archives would land in the employer's storage.
omniroute_mirror_resolve() {
    local onedrive status=0
    OMNIROUTE_MIRROR_ROOT=""
    OMNIROUTE_MIRROR_ERROR=""
    case "$1" in
        '')
            OMNIROUTE_MIRROR_ERROR="no mirror is configured (omniroute.backup.mirror is empty)"
            return 1
            ;;
        /*)
            OMNIROUTE_MIRROR_ROOT="$1"
            ;;
        onedrive-personal)
            onedrive="$(omniroute_windows_path OneDriveConsumer)" || status=$?
            if [[ "$status" -eq 2 ]]; then
                OMNIROUTE_MIRROR_ERROR="the personal OneDrive is reachable from WSL alone, and this is not WSL (no cmd.exe)"
                return 1
            elif [[ "$status" -ne 0 ]]; then
                OMNIROUTE_MIRROR_ERROR="Windows names no personal OneDrive (%OneDriveConsumer% is unset; sign in to OneDrive with the personal account)"
                return 1
            elif [[ ! -d "$onedrive" ]]; then
                OMNIROUTE_MIRROR_ERROR="the personal OneDrive folder $onedrive does not exist"
                return 1
            fi
            OMNIROUTE_MIRROR_ROOT="$onedrive/Backup/omniroute"
            ;;
        *)
            OMNIROUTE_MIRROR_ERROR="omniroute.backup.mirror is '$1', which is neither 'onedrive-personal', an absolute path nor empty"
            return 1
            ;;
    esac
}

# Prints the archives found in the folders given, newest first, one path per line. The UTC
# timestamp in each name orders them, so copies keep their place whatever their mtime; a name
# already found in an earlier folder is skipped.
omniroute_list_archives() {
    local dir name
    local -A found=()
    for dir in "$@"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        while IFS= read -r name; do
            [[ "$name" =~ $OMNIROUTE_ARCHIVE_RE && -z "${found[$name]:-}" ]] || continue
            found[$name]="$dir/$name"
        done < <(find "$dir" -maxdepth 1 -type f -name 'omniroute-*.tar.age' -printf '%f\n' 2>/dev/null)
    done
    for name in "${!found[@]}"; do
        printf '%s\t%s\n' "$name" "${found[$name]}"
    done | LC_ALL=C sort -r | cut -f2-
}

# Prints the value the last `$1=` line of the env file $2 assigns, without the quotes Compose and
# OmniRoute's bootstrap both strip, or nothing. It reads secrets too: callers capture it into a
# variable, never print it.
omniroute_env_value() {
    local key="$1" env_file="$2" line value=""
    [[ -f "$env_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ "$line" == "$key="* ]] && value="${line#*=}"
    done < "$env_file"
    if [[ ${#value} -ge 2 && ( "$value" == \"*\" || "$value" == \'*\' ) ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s' "$value"
}

# Writes to $2, mode 600, the KEY=value lines of $1 whose key OMNIROUTE_ENV_KEYS names; comments,
# blank lines and every other key are dropped. Values are never printed.
omniroute_filter_env() {
    local source_file="$1" target="$2"
    local staged="$target.tmp.$$"
    (umask 077 && { grep -E "^(${OMNIROUTE_ENV_KEYS})=" "$source_file" | tr -d '\r' || true; } > "$staged")
    mv -f "$staged" "$target"
}

# Prints why `docker compose pull` failed, from the error output saved in $1, for the message that
# reports it. Docker sends the login ~/.docker/config.json keeps for a registry with every pull from
# it, and the registry refuses a stale one even for a public image: an error that says "denied" or
# "unauthorized" is that, not the network, which "offline?" alone would suggest.
omniroute_pull_failure() {
    local error_log="$1"
    if grep -qiwE 'denied|unauthorized' "$error_log" 2>/dev/null; then
        printf '%s' "the registry refused the login Docker sent with the pull: renew or remove that registry's entry in ~/.docker/config.json, a device note's docker: line, since a public image needs none"
    else
        printf '%s' "offline?"
    fi
}
