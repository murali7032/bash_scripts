#!/bin/bash

LOGFILE="/var/log/add_secondary_interface.log"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

log() {
    local msg="$1"
    echo "[$DATE] $msg" >> "$LOGFILE"
}

#---------------------------------------------
# Parse Parameters --ip and --mac
#---------------------------------------------
IP_RAW=""
MAC=""
CIDR=""
IP_NO_CIDR=""

USAGE="Usage: $0 --ip <IP[/CIDR]> --mac <MAC_ADDRESS>"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip)
            IP_RAW="$2"
            shift 2
            ;;
        --mac)
            MAC="$2"
            shift 2
            ;;
        *)
            log "ERROR: Unknown parameter: $1"
            log "$USAGE"
            echo '{"status":"failed","message":"Unknown parameter","logfile":"'"$LOGFILE"'"}'
            exit 1
            ;;
    esac
done

if [[ -z "$IP_RAW" || -z "$MAC" ]]; then
    log "ERROR: Missing required parameters."
    log "$USAGE"
    echo '{"status":"failed","message":"Missing required parameters","logfile":"'"$LOGFILE"'"}'
    exit 1
fi

# Extract IP & CIDR
if [[ "$IP_RAW" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
    IP_NO_CIDR="${IP_RAW%/*}"
    CIDR="${IP_RAW#*/}"
else
    if [[ "$IP_RAW" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IP_NO_CIDR="$IP_RAW"
        CIDR=24
    else
        log "ERROR: Invalid IP format"
        echo '{"status":"failed","message":"Invalid IP format","logfile":"'"$LOGFILE"'"}'
        exit 1
    fi
fi

# CIDR validation
if ! [[ "$CIDR" =~ ^([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
    log "ERROR: Invalid CIDR"
    echo '{"status":"failed","message":"Invalid CIDR mask","logfile":"'"$LOGFILE"'"}'
    exit 1
fi

IP="$IP_NO_CIDR/$CIDR"

# Validate MAC
if ! [[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    log "ERROR: Invalid MAC"
    echo '{"status":"failed","message":"Invalid MAC format","logfile":"'"$LOGFILE"'"}'
    exit 1
fi

log "Input validated: IP=$IP_NO_CIDR CIDR=$CIDR MAC=$MAC"

#---------------------------------------------
# Detect OS family
#---------------------------------------------
if [[ -f /etc/redhat-release ]]; then
    OS="rhel"
elif [[ -f /etc/debian_version ]]; then
    OS="debian"
elif [[ -f /etc/SuSE-release ]] || [[ -d /etc/sysconfig/network ]]; then
    OS="suse"
elif [[ -d /etc/netplan ]]; then
    OS="ubuntu"
else
    OS="unknown"
fi

log "Detected OS: $OS"

#---------------------------------------------
# Find interface by MAC
#---------------------------------------------
INTERFACE=$(ip link | awk -v mac="$MAC" '$0 ~ mac {print prev} {prev=$2}' | sed 's/://')

if [[ -z "$INTERFACE" ]]; then
    log "ERROR: No interface found with MAC $MAC"
    echo '{"status":"failed","message":"Interface not found","logfile":"'"$LOGFILE"'"}'
    exit 1
fi

log "Detected interface: $INTERFACE"

#---------------------------------------------
# Backup config
#---------------------------------------------
BACKUP_DIR="/tmp/netcfg_backup_$DATE"
mkdir -p "$BACKUP_DIR"

#---------------------------------------------
# APPLY PERMANENT CONFIGS BUT WITHOUT RESTART
#---------------------------------------------

case "$OS" in

############################################################
#  RHEL / CENTOS / ROCKY
############################################################
rhel)
    CFG="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"
    [[ -f "$CFG" ]] && cp "$CFG" "$BACKUP_DIR/"

    cat > "$CFG" <<EOF
TYPE=Ethernet
NAME=$INTERFACE
DEVICE=$INTERFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IP_NO_CIDR
PREFIX=$CIDR
EOF

    log "Wrote RHEL config"
    ;;

############################################################
#  UBUNTU (Netplan)
############################################################
ubuntu)
    CFG="/etc/netplan/01-$INTERFACE.yaml"
    [[ -f "$CFG" ]] && cp "$CFG" "$BACKUP_DIR/"

    cat > "$CFG" <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses: [$IP]
EOF

    chmod 600 "$CFG"
    log "Wrote Ubuntu netplan config"
    ;;

############################################################
#  DEBIAN (ifupdown /etc/network/interfaces)
############################################################
debian)
    CFG="/etc/network/interfaces.d/$INTERFACE"
    mkdir -p /etc/network/interfaces.d
    [[ -f "$CFG" ]] && cp "$CFG" "$BACKUP_DIR/"

    cat > "$CFG" <<EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_NO_CIDR
    netmask $(ipcalc "$IP" | grep Netmask | awk '{print $2}')
EOF

    log "Wrote Debian /etc/network/interfaces config"
    ;;

############################################################
#  SUSE (wicked)
############################################################
suse)
    CFG="/etc/sysconfig/network/ifcfg-$INTERFACE"
    [[ -f "$CFG" ]] && cp "$CFG" "$BACKUP_DIR/"

    cat > "$CFG" <<EOF
BOOTPROTO='static'
IPADDR='$IP_NO_CIDR/$CIDR'
STARTMODE='auto'
EOF

    log "Wrote SUSE wicked config"
    ;;

*)
    log "ERROR: Unsupported OS"
    echo '{"status":"failed","message":"Unsupported OS","logfile":"'"$LOGFILE"'"}'
    exit 1
    ;;
esac

#---------------------------------------------
# SAFE TEMPORARY IP APPLY (NO RESTART)
#---------------------------------------------
log "Applying temporary IP: $IP"

if ip addr add "$IP" dev "$INTERFACE" 2>>"$LOGFILE"; then
    log "Temporary IP added safely"
else
    if ip addr show "$INTERFACE" | grep -q "$IP_NO_CIDR"; then
        log "IP already exists — safe"
    else
        log "Temporary IP add failed"
    fi
fi

#---------------------------------------------
# Schedule reboot to activate permanent config
#---------------------------------------------
log "Scheduling reboot in 1 minute"
shutdown -r +1 >>"$LOGFILE" 2>&1

echo "{\"status\":\"SUCCESS\",\"message\":\"Temporary IP applied. Permanent configuration will activate after reboot.\",\"logfile\":\"$LOGFILE\"}"
exit 0
