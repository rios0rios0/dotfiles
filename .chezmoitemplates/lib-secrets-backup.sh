# shellcheck shell=bash
# Shared by secrets-backup, secrets-restore and run_onchange_after_linux-018-setup-secrets-backup,
# which include it as a chezmoi template, so it must stay pure bash, without template directives.
# The backup writes archives where the restore and the installer look for them, so all three take
# the archive names, the OneDrive finder, the listing and the allowlist from here rather than from
# three copies. It mirrors lib-omniroute.sh's generic half, kept separate so neither backup
# subsystem's key, names or retention touch the other.

# The names secrets-backup gives its archives. Anything else in a backup folder is left alone.
SECRETS_ARCHIVE_RE='^secrets-[0-9]{8}T[0-9]{6}Z\.tar\.age$'

# Prints Windows' environment variable $1 as a WSL path. Returns 2 when this is not WSL (no
# cmd.exe) and 1 when the variable is unset. cmd.exe is looked up on PATH and then where Windows
# keeps it, because a systemd unit's PATH holds none of Windows' directories; it prints an unset
# variable back as %NAME%, and its warning about starting in a WSL (UNC) directory goes to stderr.
secrets_windows_path() {
    local variable="$1" cmd value
    cmd="$(command -v cmd.exe 2>/dev/null)" || cmd="/mnt/c/Windows/System32/cmd.exe"
    [[ -x "$cmd" ]] || return 2
    value="$("$cmd" /d /c "echo %$variable%" 2>/dev/null | tr -d '\r')" || return 1
    [[ -n "$value" && "$value" != "%$variable%" ]] || return 1
    wslpath -u "$value" 2>/dev/null || return 1
}

# Resolves the mirror setting $1 (.chezmoidata/secrets-backup.yaml, mirror) into
# SECRETS_MIRROR_ROOT, the folder that holds one folder of archives per device, or explains in
# SECRETS_MIRROR_ERROR why there is none. Globals rather than stdout, so a caller keeps the reason.
#
# 'onedrive-personal' reads %OneDriveConsumer%, which only the personal account sets. %OneDrive%
# names whichever account signed in last -- on a machine also signed in to a work account, that
# one -- so it is never read: the archives would land in the employer's storage.
secrets_mirror_resolve() {
    local onedrive status=0
    SECRETS_MIRROR_ROOT=""
    SECRETS_MIRROR_ERROR=""
    case "$1" in
        '')
            SECRETS_MIRROR_ERROR="no mirror is configured (secretsBackup.mirror is empty)"
            return 1
            ;;
        /*)
            SECRETS_MIRROR_ROOT="$1"
            ;;
        onedrive-personal)
            onedrive="$(secrets_windows_path OneDriveConsumer)" || status=$?
            if [[ "$status" -eq 2 ]]; then
                SECRETS_MIRROR_ERROR="the personal OneDrive is reachable from WSL alone, and this is not WSL (no cmd.exe)"
                return 1
            elif [[ "$status" -ne 0 ]]; then
                SECRETS_MIRROR_ERROR="Windows names no personal OneDrive (%OneDriveConsumer% is unset; sign in to OneDrive with the personal account)"
                return 1
            elif [[ ! -d "$onedrive" ]]; then
                SECRETS_MIRROR_ERROR="the personal OneDrive folder $onedrive does not exist"
                return 1
            fi
            SECRETS_MIRROR_ROOT="$onedrive/Backup/secrets"
            ;;
        *)
            SECRETS_MIRROR_ERROR="secretsBackup.mirror is '$1', which is neither 'onedrive-personal', an absolute path nor empty"
            return 1
            ;;
    esac
}

# Prints the archives found in the folders given, newest first, one path per line. The UTC
# timestamp in each name orders them, so copies keep their place whatever their mtime; a name
# already found in an earlier folder is skipped.
secrets_list_archives() {
    local dir name
    local -A found=()
    for dir in "$@"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        while IFS= read -r name; do
            [[ "$name" =~ $SECRETS_ARCHIVE_RE && -z "${found[$name]:-}" ]] || continue
            found[$name]="$dir/$name"
        done < <(find "$dir" -maxdepth 1 -type f -name 'secrets-*.tar.age' -printf '%f\n' 2>/dev/null)
    done
    for name in "${!found[@]}"; do
        printf '%s\t%s\n' "$name" "${found[$name]}"
    done | LC_ALL=C sort -r | cut -f2-
}

# secrets_entry_allowed <entry> <source>...: whether a tar entry belongs to one of the configured
# sources and escapes nothing. The age recipient is public (.chezmoidata/age-keys.yaml), so anyone
# could encrypt an archive to it; the backup's own check and the restore both run every listed
# entry through this, so a planted archive naming `.ssh/`, an absolute path or a `..` component is
# refused before anything is written.
secrets_entry_allowed() {
    local entry="$1" src
    shift
    case "$entry" in
        /*) return 1 ;;
    esac
    case "/$entry/" in
        */../*) return 1 ;;
    esac
    for src in "$@"; do
        [[ "$entry" == "$src" || "$entry" == "$src/"* ]] && return 0
    done
    return 1
}

# secrets_tar_types_ok <tarfile>: whether every member is a regular file or a directory. The name
# allowlist cannot see this, and it is the other half of the planted-archive defence: a symlink
# (`.john` -> `.ssh`) or a hard link whose name passes the allowlist would, on a fresh restore, be
# created before a later member is written through it, outside the sources -- GNU tar defers only
# symlinks whose target is absolute or holds `..`. `tar -tvf` leads each line with the type
# character (ls -l style), so refusing anything but `-` and `d` refuses `l`, `h` and every special
# file. The mode is the first field, so a name with spaces does not throw the check off.
secrets_tar_types_ok() {
    local modestr _
    while read -r modestr _; do
        case "${modestr:0:1}" in
            -|d) ;;
            *) return 1 ;;
        esac
    done < <(tar -tvf "$1" 2>/dev/null)
}
