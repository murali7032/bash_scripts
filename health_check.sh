#!/bin/bash

# ============================
# System Health Monitoring Script
# ============================

LOGFILE="/var/log/system_health.log"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/...your_webhook..."
EMAIL="admin@example.com"

# Set thresholds
CPU_THRESHOLD=85
MEM_THRESHOLD=85
DISK_THRESHOLD=90
LOAD_THRESHOLD=5
IOWAIT_THRESHOLD=10

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

send_alert() {
    MSG="$1"

    # Email alert
    echo "$MSG" | mailx -s "System Alert on $(hostname)" "$EMAIL"

    # Slack alert
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\": \"$(hostname): $MSG\"}" \
        "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
}

# CPU usage %
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100-$8}')
CPU=${CPU%.*}

# Memory %
MEM=$(free | awk '/Mem/ {printf("%.0f"), $3/$2 * 100}')

# Disk %
DISK=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

# Load average
LOAD=$(awk '{print int($1)}' /proc/loadavg)

# IO wait
IOWAIT=$(iostat -c 1 2 | awk 'NR==7 {print int($4)}')

# Active TCP connections
NET_CONN=$(netstat -tun | grep ESTABLISHED | wc -l)

# Log the results
log "CPU: $CPU%, MEM: $MEM%, DISK: $DISK%, LOAD: $LOAD, IOWAIT: $IOWAIT%, NET_CONN: $NET_CONN"

ALERT_MSG=""

# Check thresholds
[ $CPU -gt $CPU_THRESHOLD ] && ALERT_MSG+="High CPU: $CPU% "
[ $MEM -gt $MEM_THRESHOLD ] && ALERT_MSG+="High Memory: $MEM% "
[ $DISK -gt $DISK_THRESHOLD ] && ALERT_MSG+="High Disk Usage: $DISK% "
[ $LOAD -gt $LOAD_THRESHOLD ] && ALERT_MSG+="High Load: $LOAD "
[ $IOWAIT -gt $IOWAIT_THRESHOLD ] && ALERT_MSG+="High IO Wait: $IOWAIT% "

if [ -n "$ALERT_MSG" ]; then
    log "ALERT: $ALERT_MSG"
    send_alert "$ALERT_MSG"
fi
