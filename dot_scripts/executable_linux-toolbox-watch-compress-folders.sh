#!/bin/bash
#
# This script watches specific directories for changes (create, modify, delete, or move),
# archives them using tar (ensuring the archive is fully built before handing off to chezmoi),
# and then updates chezmoi with the encrypted archive.
#
# It uses a file lock mechanism (flock) so that duplicate watchers on the same directory are not started.
# All log messages are written to a dedicated daily log file (with logs older than one day deleted)
# and each log line is prefixed with a timestamp.

#######################################
# Logging Function
#######################################
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}
export -f log

#######################################
# Setup Logging
#######################################
LOG_DIR="/tmp/inotify_watcher"
mkdir -p "$LOG_DIR"

# Remove log files older than 1 day.
find "$LOG_DIR" -type f -mtime +1 -delete

LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d').log"

#######################################
# Configuration
#######################################
WATCH_DIRS=(
    "$HOME/.histdb"
    "$HOME/.john"
    "$HOME/.kube/config-files"
    "$HOME/.sqlmap"
)

# Debounce time in seconds (e.g., wait 2 seconds after an event before archiving)
DEBOUNCE_TIME=2

# Associative array to hold the timestamp of the last archive per directory (requires Bash 4+)
declare -A LAST_ARCHIVE

#######################################
# Archive Function
# Writes the archive to a file then invokes chezmoi to add it.
#######################################
archive_dir() {
    local dir="$1"
    local tar_file
    tar_file="${dir//\//-}.tar.gz"
    log "Archiving directory [$dir] to file [$tar_file]..."

    if tar -czf "$tar_file" -C "$dir" .; then
        log "Archive complete: [$tar_file]"
        log "Running chezmoi on archive: [$tar_file]"
        chezmoi add --encrypt --recipients-file "$HOME/.age_recipients" "./$tar_file"
        log "chezmoi.add complete for [$tar_file]"
    else
        log "Error: Failed to create archive for [$dir]."
    fi
}

#######################################
# Watch Function
#
# Uses process substitution so that the while-loop runs in the current shell
# (preserving variables such as the associative array for debouncing).
# The inotifywait command now includes the -q flag to silence inotifywait’s default
# informational messages (e.g., "Watches established." and "Setting up watches.").
#######################################
start_watching() {
    local dir="$1"
    log "Starting watcher for directory: [$dir]"

    while read -r changed_file; do
        log "Change detected: [$changed_file] in directory [$dir]"
        local now debounce_nano diff
        now=$(date +%s%N)  # current time in nanoseconds

        if (( DEBOUNCE_TIME > 0 )); then
            debounce_nano=$(( DEBOUNCE_TIME * 1000000000 ))
            if [[ -n "${LAST_ARCHIVE[$dir]}" ]]; then
                diff=$(( now - LAST_ARCHIVE[$dir] ))
                if (( diff < debounce_nano )); then
                    log "Debouncing archive for [$dir] (only $(awk 'BEGIN {printf "%.2f", '"$diff"'/1000000000}') seconds since last archive)"
                    continue
                fi
            fi
            LAST_ARCHIVE[$dir]=$now
        fi

        archive_dir "$dir"
    done < <(inotifywait -q -m -r -e create,modify,delete,move --format '%w%f' "$dir")
}

#######################################
# Main: Start Watchers with Lock Mechanism
#
# For each directory in WATCH_DIRS, a subshell is launched. Each subshell:
# - Redirects output to the daily log file.
# - Acquires a file lock using a sanitized lock file name.
# - Starts the watcher if the lock is obtained.
#######################################
for dir in "${WATCH_DIRS[@]}"; do
    (
        # Redirect all output of this subshell to the log file.
        exec >> "$LOG_FILE" 2>&1

        # Uncomment the following block if you want to ensure the log() function exists here.
        if ! type log >/dev/null 2>&1; then
            log() {
                echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
            }
        fi

        # Create a lock file in /tmp (sanitize the directory name for a safe filename).
        lock_file="/tmp/inotify_watcher_$(echo "$dir" | sed 's/[^a-zA-Z0-9]/_/g').lock"
        exec {lock_fd}> "$lock_file" || { log "Cannot open lock file $lock_file"; exit 1; }

        if ! flock -n "$lock_fd"; then
            log "Watcher already running for [$dir] (lock file busy)"
            exit 0
        fi

        start_watching "$dir"
    ) &
done

# Wait for all background watchers (they run indefinitely).
wait
