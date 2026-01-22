#!/bin/bash
#
# This script watches specific directories for changes and archives them using chezmoi.
# It uses a single global lock to ensure only one instance runs across all terminals.
#
# Lock strategy: Single lock for all folders is preferred because:
# - inotifywait efficiently watches multiple directories in one process
# - Simpler code with fewer race conditions
# - Lock is automatically released when process exits (flock releases on fd close)
#

set -euo pipefail

#######################################
# Configuration
#######################################
LOCK_FILE="/tmp/linux-toolbox-watch-compress-folders.lock"
LOG_FILE="/tmp/linux-toolbox-watch-compress-folders.log"
PID_FILE="/tmp/linux-toolbox-watch-compress-folders.pid"
DEBOUNCE_TIME=5
MAX_LOG_AGE_SECONDS=86400  # 1 day in seconds

WATCH_DIRS=(
  "$HOME/.histdb"
  "$HOME/.john"
  "$HOME/.kube/config-files"
  "$HOME/.sqlmap"
)

#######################################
# Log Rotation Function
# Keeps only logs from the last 24 hours
#######################################
rotate_logs() {
  if [[ ! -f "$LOG_FILE" ]]; then
    return
  fi

  local temp_file="${LOG_FILE}.tmp"
  local cutoff_time
  cutoff_time=$(date -d "1 day ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-1d '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")

  if [[ -z "$cutoff_time" ]]; then
    # If date command doesn't support these options, just truncate if file is too large (>1MB)
    local file_size
    file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    if (( file_size > 1048576 )); then
      tail -n 1000 "$LOG_FILE" > "$temp_file" && mv "$temp_file" "$LOG_FILE"
    fi
    return
  fi

  # Keep only lines newer than cutoff time
  awk -v cutoff="$cutoff_time" '$0 >= cutoff || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}/' "$LOG_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$LOG_FILE" || true
}

#######################################
# Logging Function
#######################################
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

#######################################
# Check if watcher is already running
#######################################
if [[ -f "$PID_FILE" ]]; then
  existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    # Watcher is already running, exit silently
    exit 0
  fi
  # Stale PID file, remove it
  rm -f "$PID_FILE"
fi

#######################################
# Acquire lock (non-blocking)
# Lock is automatically released when:
# - Process exits normally
# - Process is killed
# - Terminal closes (OS closes all file descriptors)
#######################################
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  # Another instance is starting up, exit silently
  exit 0
fi

# Write our PID
echo $$ > "$PID_FILE"

# Rotate logs before starting
rotate_logs

log "Starting folder watcher (PID: $$)"

#######################################
# Cleanup on exit
#######################################
cleanup() {
  log "Stopping folder watcher (PID: $$)"
  rm -f "$PID_FILE"
  # Lock file is kept (flock releases automatically on fd close)
  # Kill all child processes
  pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT

#######################################
# Archive Function
# Creates a tar archive in the original directory location
# and adds it to chezmoi with encryption
#######################################
archive_dir() {
  local dir="$1"
  local dir_name
  local parent_dir
  local tar_file

  dir_name=$(basename "$dir")
  parent_dir=$(dirname "$dir")
  tar_file="${parent_dir}/${dir_name}.tar"

  if [[ ! -d "$dir" ]]; then
    log "Directory does not exist: [$dir]"
    return 1
  fi

  log "Archiving directory: [$dir] -> [$tar_file]"

  # Create tar archive in the same parent directory as the source
  if tar -cf "$tar_file" -C "$parent_dir" "$dir_name" 2>>"$LOG_FILE"; then
    log "Archive created: [$tar_file]"

    # Add to chezmoi with encryption
    if chezmoi add --encrypt "$tar_file" 2>>"$LOG_FILE"; then
      log "Successfully added to chezmoi: [$tar_file]"
    else
      log "Failed to add to chezmoi: [$tar_file]"
    fi

    # Clean up the tar file after adding to chezmoi
    rm -f "$tar_file"
  else
    log "Failed to create archive for: [$dir]"
  fi
}

#######################################
# Build watch directories list (only existing ones)
#######################################
existing_dirs=()
for dir in "${WATCH_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    existing_dirs+=("$dir")
    log "Will watch: [$dir]"
  else
    log "Skipping non-existent directory: [$dir]"
  fi
done

if [[ ${#existing_dirs[@]} -eq 0 ]]; then
  log "No directories to watch, exiting"
  exit 0
fi

#######################################
# Check if inotifywait is available
#######################################
if ! command -v inotifywait &>/dev/null; then
  log "inotifywait not found, exiting"
  exit 1
fi

#######################################
# Main watch loop with debouncing
# Uses process substitution to keep the while loop in the main shell
# so the associative array persists across iterations
#######################################
declare -A last_event_time

# Rotate logs periodically (every hour)
last_rotation=$(date +%s)

while read -r changed_path; do
  # Periodic log rotation (every hour)
  now=$(date +%s)
  if (( now - last_rotation > 3600 )); then
    rotate_logs
    last_rotation=$now
  fi

  # Find which watched directory this change belongs to
  for dir in "${existing_dirs[@]}"; do
    if [[ "$changed_path" == "$dir"* ]]; then
      last_time="${last_event_time[$dir]:-0}"

      # Debounce: skip if we archived this directory recently
      if (( now - last_time < DEBOUNCE_TIME )); then
        continue
      fi

      last_event_time[$dir]=$now
      log "Change detected in: [$dir]"
      archive_dir "$dir" &
      break
    fi
  done
done < <(inotifywait -q -m -r -e create,modify,delete,move --format '%w' "${existing_dirs[@]}" 2>>"$LOG_FILE")
