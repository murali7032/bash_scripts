#!/usr/bin/env bash
# backup.sh - Incremental backup + restore + verification using rsync
# Author: Your Name
# Usage:
#   /usr/local/bin/backup.sh daily
#   /usr/local/bin/backup.sh weekly
#   /usr/local/bin/backup.sh monthly
#   /usr/local/bin/backup.sh restore <snapshot-timestamp> [<target-dir>]
#   /usr/local/bin/backup.sh list
#
# Requirements: bash, rsync, tar, sha256sum, flock (optional), jq (optional for Slack JSON)
set -uo pipefail
IFS=$'\n\t'

# ----------------------------
# CONFIG — edit these values
# ----------------------------
SOURCE="/var/www"                          # directory to backup (no trailing slash recommended)
DEST_ROOT="/backup"                        # root destination (local disk or mounted volume)
RET_DAILY=7                                # keep last N daily backups
RET_WEEKLY=8                               # keep last N weekly backups
RET_MONTHLY=12                             # keep last N monthly backups
SAMPLE_VERIFY_COUNT=20                     # how many files to verify by checksum per backup
EMAIL=""                                   # admin email for alerts (leave empty to disable)
SLACK_WEBHOOK_URL=""                       # slack webhook url (leave empty to disable)
LOGFILE="/var/log/backup.log"
LOCKFILE="/var/lock/backup.lock"
RSYNC_OPTS=(-aHAX --delete --partial --inplace --numeric-ids --relative --delete-excluded)
# Exclude list file path (one pattern per line)
EXCLUDE_FILE="/etc/backup_exclude.list"    # create this file if you need excludes
# For monthly compressed snapshots
MONTHLY_TAR=1                              # 1 = create .tar.gz of monthly snapshot, 0 = keep as rsync snapshot
# ----------------------------

# Derived dirs
DAILY_DIR="$DEST_ROOT/daily"
WEEKLY_DIR="$DEST_ROOT/weekly"
MONTHLY_DIR="$DEST_ROOT/monthly"
RESTORE_TEST_DIR="$DEST_ROOT/restore-tests"

# Helper functions
log() {
    local msg="$1"
    echo "[$(date '+%F %T')] $msg" >> "$LOGFILE"
}

send_alert() {
    local subject="$1"
    local body="$2"

    log "ALERT: $subject -- $body"

    # Email
    if [[ -n "$EMAIL" ]]; then
        printf "%s\n" "$body" | mail -s "$subject" "$EMAIL"
    fi

    # Slack
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        # Simple JSON payload
        local payload
        payload=$(printf '{"text":"%s: %s"}' "$(hostname)" "$(echo "$subject - $body" | sed 's/"/\\"/g')")
        curl -s -S -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi
}

ensure_dirs() {
    mkdir -p "$DAILY_DIR" "$WEEKLY_DIR" "$MONTHLY_DIR" "$RESTORE_TEST_DIR"
    touch "$LOGFILE"
}

acquire_lock() {
    exec 9>"$LOCKFILE"
    if ! flock -n 9; then
        log "Another backup is running. Exiting."
        echo '{"status":"failed","message":"Another backup is running","logfile":"'"$LOGFILE"'"}'
        exit 2
    fi
    # keep FD 9 open until script exits for lock
}

release_lock() {
    # close FD 9 -> releases lock
    exec 9>&-
}

timestamp() { date '+%Y-%m-%d_%H%M%S'; }

# find most recent snapshot in a dir
latest_snapshot() {
    local dir="$1"
    ls -1 "$dir" 2>/dev/null | tail -n1 || true
}

# rotate retention: keep last N snapshots (alphabetically latest)
rotate_retention() {
    local dir="$1"
    local keep="$2"
    if [[ ! -d "$dir" ]]; then return; fi
    local count
    count=$(ls -1 "$dir" 2>/dev/null | wc -l || echo 0)
    if (( count <= keep )); then
        return
    fi
    local remove=$((count - keep))
    log "Rotating $dir: keeping $keep, removing $remove oldest"
    ls -1t "$dir" | tail -n "$remove" | while read -r old; do
        rm -rf -- "$dir/$old"
        log "Removed old snapshot: $dir/$old"
    done
}

# prepare rsync link-dest parameter
prepare_link_dest() {
    local prev_dir="$1"
    if [[ -n "$prev_dir" && -d "$prev_dir" ]]; then
        echo "--link-dest=$prev_dir"
    else
        echo ""
    fi
}

# perform rsync incremental backup into new snapshot dir
perform_rsync_snapshot() {
    local dest_parent="$1"   # e.g. $DAILY_DIR
    local prev="$2"          # prev snapshot name (not path), may be empty
    local label="$3"         # timestamp label
    mkdir -p "$dest_parent/$label"
    local linkdest=""
    if [[ -n "$prev" ]]; then
        linkdest="$dest_parent/$prev"
    fi

    # Compose rsync command dynamically to include link-dest if present
    local rsync_cmd=(rsync "${RSYNC_OPTS[@]}")
    # exclude file if present
    if [[ -f "$EXCLUDE_FILE" ]]; then
        rsync_cmd+=(--exclude-from="$EXCLUDE_FILE")
    fi
    # add link-dest if present
    if [[ -n "$linkdest" ]]; then
        rsync_cmd+=(--link-dest="$linkdest")
    fi
    # source and destination: use trailing slash semantics to copy content into snapshot dir
    rsync_cmd+=("$SOURCE/" "$dest_parent/$label/")

    log "Running rsync: ${rsync_cmd[*]}"
    if "${rsync_cmd[@]}" >>"$LOGFILE" 2>&1; then
        log "rsync completed successfully for $dest_parent/$label"
        return 0
    else
        log "rsync failed for $dest_parent/$label (see $LOGFILE)"
        return 1
    fi
}

# verify backup: sample file checksums + count comparison
verify_snapshot() {
    local snapshot_path="$1"
    local -n _retmsg="$2"

    # Basic checks: snapshot exists
    if [[ ! -d "$snapshot_path" ]]; then
        _retmsg="snapshot-missing"
        return 1
    fi

    # Count files in source and snapshot
    local src_count
    local snap_count
    src_count=$(find "$SOURCE" -type f | wc -l)
    snap_count=$(find "$snapshot_path" -type f | wc -l)

    # If snapshot has fewer files than source it's suspect (but may be okay if excludes)
    if (( snap_count == 0 )); then
        _retmsg="snapshot-empty"
        return 2
    fi

    # Choose sample files randomly
    local samples
    samples=()
    while IFS= read -r f; do samples+=("$f"); done < <(find "$SOURCE" -type f | shuf -n "$SAMPLE_VERIFY_COUNT" 2>/dev/null || find "$SOURCE" -type f | head -n "$SAMPLE_VERIFY_COUNT")

    local mismatches=0
    for sf in "${samples[@]}"; do
        # compute relative path and compare checksums
        rel="${sf#$SOURCE/}"
        srcsum=$(sha256sum "$sf" | awk '{print $1}')
        if [[ -f "$snapshot_path/$rel" ]]; then
            snsum=$(sha256sum "$snapshot_path/$rel" | awk '{print $1}')
            if [[ "$srcsum" != "$snsum" ]]; then
                log "VERIFY MISMATCH: $rel src:$srcsum snap:$snsum"
                mismatches=$((mismatches + 1))
            fi
        else
            log "VERIFY MISSING: $rel not present in snapshot"
            mismatches=$((mismatches + 1))
        fi
    done

    if (( mismatches > 0 )); then
        _retmsg="verify-mismatch-$mismatches"
        return 3
    fi

    _retmsg="ok"
    return 0
}

# create a compressed tar.gz of a snapshot (monthly)
compress_snapshot() {
    local snapshot_dir="$1"
    local target_file="${snapshot_dir}.tar.gz"
    log "Creating tar.gz $target_file"
    if tar -C "$(dirname "$snapshot_dir")" -czf "$target_file" "$(basename "$snapshot_dir")" >>"$LOGFILE" 2>&1; then
        rm -rf -- "$snapshot_dir"
        log "Compressed and removed original snapshot: $snapshot_dir"
        return 0
    else
        log "Compression failed for $snapshot_dir"
        return 1
    fi
}

# main backup flow per frequency
run_backup_cycle() {
    local freq="$1"  # daily / weekly / monthly
    ensure_dirs
    local ts
    ts=$(timestamp)

    # choose destination parent
    local dest_parent
    case "$freq" in
        daily) dest_parent="$DAILY_DIR"; keep="$RET_DAILY" ;;
        weekly) dest_parent="$WEEKLY_DIR"; keep="$RET_WEEKLY" ;;
        monthly) dest_parent="$MONTHLY_DIR"; keep="$RET_MONTHLY" ;;
        *) log "Unknown frequency: $freq"; return 2 ;;
    esac

    # get latest snapshot name to use as link-dest
    local prev
    prev=$(ls -1 "$dest_parent" 2>/dev/null | sort | tail -n1 || true)

    if perform_rsync_snapshot "$dest_parent" "$prev" "$ts"; then
        # success — optionally compress monthly
        if [[ "$freq" == "monthly" && "$MONTHLY_TAR" -eq 1 ]]; then
            compress_snapshot "$dest_parent/$ts" || log "Compression failed for monthly snapshot"
        fi

        # verify snapshot (if compressed, skip deep verify and report success)
        local verify_msg
        if [[ "$freq" == "monthly" && "$MONTHLY_TAR" -eq 1 ]]; then
            verify_msg="ok (monthly compressed)"
            log "Monthly snapshot created and compressed: $dest_parent/$ts.tar.gz"
        else
            verify_snapshot "$dest_parent/$ts" verify_msg
            if [[ $? -ne 0 ]]; then
                send_alert "Backup verification failed" "Backup $freq $ts verification: $verify_msg"
                log "Verification failed: $verify_msg"
                # you may choose to exit non-zero here; we will keep going and rotate retention
            else
                log "Verification succeeded for $dest_parent/$ts"
            fi
        fi

        # rotate retention
        rotate_retention "$dest_parent" "$keep"

        log "Backup $freq completed: $dest_parent/$ts"
        echo "{\"status\":\"SUCCESS\",\"message\":\"Backup $freq completed\",\"snapshot\":\"$dest_parent/$ts\",\"logfile\":\"$LOGFILE\"}"
        return 0
    else
        send_alert "Backup failed" "rsync failed for $freq at $ts. See $LOGFILE"
        log "ERROR: rsync failed for $freq at $ts"
        echo "{\"status\":\"FAILED\",\"message\":\"rsync failed\",\"logfile\":\"$LOGFILE\"}"
        return 1
    fi
}

# List snapshots
list_snapshots() {
    echo "Daily:"
    ls -1 "$DAILY_DIR" 2>/dev/null || true
    echo "Weekly:"
    ls -1 "$WEEKLY_DIR" 2>/dev/null || true
    echo "Monthly:"
    ls -1 "$MONTHLY_DIR" 2>/dev/null || true
}

# restore snapshot to target dir
restore_snapshot() {
    local snapshot="$1"
    local target="${2:-/tmp/restore-$snapshot-$(timestamp)}"

    # find snapshot dir (could be compressed)
    local snap_path=""
    if [[ -d "$DAILY_DIR/$snapshot" ]]; then snap_path="$DAILY_DIR/$snapshot"; fi
    if [[ -d "$WEEKLY_DIR/$snapshot" ]]; then snap_path="$WEEKLY_DIR/$snapshot"; fi
    if [[ -d "$MONTHLY_DIR/$snapshot" ]]; then snap_path="$MONTHLY_DIR/$snapshot"; fi
    if [[ -f "$MONTHLY_DIR/$snapshot.tar.gz" ]]; then
        mkdir -p "$RESTORE_TEST_DIR/tmp_restore_$snapshot"
        tar -C "$RESTORE_TEST_DIR/tmp_restore_$snapshot" -xzf "$MONTHLY_DIR/$snapshot.tar.gz" || { log "Failed to extract monthly tar.gz"; echo '{"status":"failed","message":"extract failed"}'; return 1; }
        snap_path="$RESTORE_TEST_DIR/tmp_restore_$snapshot/$snapshot"
    fi

    if [[ -z "$snap_path" ]]; then
        log "Snapshot $snapshot not found"
        echo '{"status":"failed","message":"snapshot not found"}'
        return 2
    fi

    log "Restoring $snap_path -> $target"
    mkdir -p "$target"
    rsync -aHAX --numeric-ids --relative "$snap_path/" "$target/" >>"$LOGFILE" 2>&1
    if [[ $? -ne 0 ]]; then
        log "Restore failed (rsync error)"
        echo '{"status":"failed","message":"restore failed","logfile":"'"$LOGFILE"'"}'
        return 1
    fi

    log "Restore completed: $target"
    echo "{\"status\":\"SUCCESS\",\"message\":\"Restored to $target\",\"logfile\":\"$LOGFILE\"}"
    return 0
}

# -------------------------
# Main
# -------------------------
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 {daily|weekly|monthly|restore|list} [snapshot] [target]"
        exit 2
    fi

    local cmd="$1"
    ensure_dirs
    acquire_lock
    trap 'release_lock; log "Interrupted"; exit 130' INT TERM
    trap 'release_lock' EXIT

    case "$cmd" in
        daily|weekly|monthly)
            run_backup_cycle "$cmd"
            release_lock
            ;;
        list)
            list_snapshots
            release_lock
            ;;
        restore)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 restore <snapshot-name> [target-dir]"
                release_lock
                exit 2
            fi
            restore_snapshot "$2" "${3:-}"
            release_lock
            ;;
        *)
            echo "Unknown command: $cmd"
            release_lock
            exit 2
            ;;
    esac
}

main "$@"
