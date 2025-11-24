#!/bin/bash

###############################################
# Custom Log Rotation & Archiving Script
# Author: MURALI KRISHNA REDDY
# Description:
#   - Rotates logs based on size or age
#   - Compresses rotated logs
#   - Keeps only N archives
#   - Sends report to console or email
###############################################

# -------- CONFIGURATION --------
LOG_DIR="/var/log/myapp"         # Directory containing logs
LOG_FILE="myapp.log"             # Log file to rotate
MAX_SIZE_MB=50                   # Rotate if size ≥ 50 MB
MAX_DAYS=7                       # Rotate if file older than 7 days
RETENTION=10                     # Keep last 10 archives
ARCHIVE_DIR="/var/log/myapp/archive"
EMAIL_REPORT=""                  # Set email if you want notifications

# -------- CREATE DIRECTORIES --------
mkdir -p "$ARCHIVE_DIR"

# -------- FUNCTIONS --------

send_report() {
    echo "$1"
    [[ -n "$EMAIL_REPORT" ]] && echo "$1" | mail -s "Log Rotation Report" "$EMAIL_REPORT"
}

should_rotate() {
    local file="$LOG_DIR/$LOG_FILE"

    # Check file size
    local size_mb
    size_mb=$(du -m "$file" | awk '{print $1}')

    # Check file age
    local age_days
    age_days=$(( ( $(date +%s) - $(stat -c %Y "$file") ) / 86400 ))

    [[ $size_mb -ge $MAX_SIZE_MB || $age_days -ge $MAX_DAYS ]]
}

rotate_log() {
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)

    local src="$LOG_DIR/$LOG_FILE"
    local dst="$ARCHIVE_DIR/${LOG_FILE}.${timestamp}.gz"

    gzip -c "$src" > "$dst"
    : > "$src"  # Clear log file

    send_report "Rotated log file: $src → $dst"
}

cleanup_archives() {
    local count
    count=$(ls -1 "$ARCHIVE_DIR" | wc -l)

    if (( count > RETENTION )); then
        local remove=$(( count - RETENTION ))
        ls -1t "$ARCHIVE_DIR" | tail -n "$remove" | while read -r oldfile; do
            rm -f "$ARCHIVE_DIR/$oldfile"
            send_report "Removed old archive: $oldfile"
        done
    fi
}

# -------- MAIN LOGIC --------

LOG_PATH="$LOG_DIR/$LOG_FILE"

if [[ ! -f "$LOG_PATH" ]]; then
    send_report "ERROR: Log file not found: $LOG_PATH"
    exit 1
fi

if should_rotate; then
    rotate_log
    cleanup_archives
else
    send_report "No rotation needed for: $LOG_FILE"
fi
