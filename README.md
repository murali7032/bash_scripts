# static ip configuration
✅ This script is safe on:
✔ RHEL/CentOS/Rocky
✔ Ubuntu (Netplan)
✔ Debian (ifupdown)
✔ SUSE (wicked)
⚠ 100% SAFE for SSH

None of these actions will cause SSH loss even if you configure the active interface, because:

✔ No interface restart
✔ No NetworkManager reload
✔ No wicked ifreload
✔ No systemctl restart networking
✔ Only ip addr add is used (non-destructive)
✔ Permanent config activates only after reboot

=====================================
# System Health Monitoring Script

A lightweight, production-ready Bash script for monitoring CPU, RAM, Disk usage, System Load, I/O wait, and Network activity on Linux servers.
Supports RHEL, CentOS, Ubuntu, Debian, SUSE, and other POSIX-compatible systems.

Includes automatic Slack + Email alerting, threshold-based warnings, and continuous logging.

🚀 Features

✔️ CPU, Memory, Disk, Load Average, I/O Wait monitoring

✔️ Network connection count

✔️ Automatic alerts:

Slack Webhooks

Email (mailx)

✔️ Threshold-based warning system

✔️ Logs written to /var/log/system_health.log

✔️ Ready for cron (runs every X minutes)

✔️ Works on all major Linux distributions

✔️ No external dependencies except curl, mailx, and iostat

📂 Files
File	Description
health_check.sh	Main monitoring script
README.md	Documentation
cron-example.txt	Example cron configuration
🔧 Requirements

Make sure these packages exist:

sudo apt install sysstat mailutils curl -y     # Ubuntu/Debian
sudo yum install sysstat mailx curl -y         # RHEL/CentOS
sudo zypper install sysstat mailx curl -y      # SUSE

⚙️ Configuration

Inside the script:

LOGFILE="/var/log/system_health.log"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"
EMAIL="admin@example.com"


You can customize thresholds:

CPU_THRESHOLD=85
MEM_THRESHOLD=85
DISK_THRESHOLD=90
LOAD_THRESHOLD=5
IOWAIT_THRESHOLD=10

📊 Metrics Collected
Metric	Description
CPU Usage	Uses top to capture actual usage
RAM Usage	free -m
Disk Usage	From root filesystem (df -h /)
Load Average	From /proc/loadavg
IO Wait	From iostat
Network Activity	ESTABLISHED TCP connections
🔔 Alerts
Slack Alerts

Uses an incoming webhook.
Example message:

🔴 High CPU detected: 92% on prod-server-01

Email Alerts

Uses mailx:

Subject: System Alert on prod-server-01
Body: High Disk Usage: 93%

📝 Logging

All activity goes to:

/var/log/system_health.log


You can rotate logs using:

logrotate -f /etc/logrotate.conf

⏱️ Run Automatically with Cron

Create a cron entry:

sudo crontab -e


And add:

*/5 * * * * /usr/local/bin/health_check.sh


This runs the monitor every 5 minutes.

▶️ Running Manually
sudo bash health_check.sh

📦 Example Slack Alert (Screenshot)

(Add this in GitHub if you want. Optional.)

[prod-server-01] ALERT: High CPU: 91% High Disk: 95%

🛡️ Compatibility
OS	Supported
Ubuntu	✔️
Debian	✔️
RHEL / CentOS	✔️
Rocky / AlmaLinux	✔️
SUSE / SLES	✔️
Amazon Linux	✔️
Oracle Linux	✔️
📘 License

MIT License. Free to modify for your environment.
