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

========================================================================

# backup.sh
below is a production-ready backup.sh you can drop into /usr/local/bin/backup.sh, make executable (chmod +x), and use with cron.
It implements:

Incremental backups using rsync --link-dest (hard-link trick)

Daily / weekly / monthly rotation & retention

Optional compression for monthly snapshots (tar.gz)

Restore command (restore to path or test dir)

Automated verification (checksums for samples + rsync exit code)

Logging, lockfile, and alerting via email or Slack webhook

Safe error handling and clear exit codes

Read the header config and adjust variables to your environment (SOURCE, DEST_ROOT, retention counts, EMAIL, SLACK_WEBHOOK).

Install notes

Save file as /usr/local/bin/backup.sh

chmod 750 /usr/local/bin/backup.sh

Edit config variables at top for source/destination, email/slack, retention.

Add cron entries (examples below) to automate.

📦 Backup & Restore Automation (Bash + rsync)
Incremental Linux Backup System with Automated Restore Verification

This project implements a production-grade backup and restore automation solution built entirely in Bash.
It uses rsync for incremental backups, tar for archive snapshots, and includes optional automated restore verification to ensure backup integrity.

🚀 Features
✅ 1. Incremental Backups (rsync)

Uses rsync --archive --delete --link-dest for efficient incremental backups

Only changed files are copied

Unchanged files are hard-linked to previous backup for optimal storage

✅ 2. Daily / Weekly / Monthly Scheduling

Integrated with cron for fully automated scheduling

Supports retention policies:

keep N daily backups

keep N weekly backups

keep N monthly backups

✅ 3. Restore Automation

One-command restore from any backup snapshot

Optionally restores to:

original directory

alternate directory

test environment

✅ 4. Automated Restore Verification

After each backup, script performs:

checksum verification (sha256)

file count comparison

sample file comparison

Logs results to /var/log/backup.log

✅ 5. Safety Features

Root-safe path validation

Lock file prevents overlapping executions

Email or Slack notifications (optional) when:

backup succeeds

backup fails

restore check fails

📁 Directory Structure

/backup/
   ├── daily/
   ├── weekly/
   ├── monthly/
   ├── logs/
   └── restore-tests/

⚙️ Requirements

Bash 4+

rsync

tar

cron

sha256sum

(optional) curl for Slack notifications

🧪 Restore Verification

For every new backup, the script automatically:

Extracts N sample files into /backup/restore-tests/

Compares checksums

Compares directory structure

Logs results

If mismatch → sends an alert.

📜 Example Cron Jobs
Daily backup (1 AM)
0 1 * * * /usr/local/bin/backup.sh daily

Weekly backup (Sunday at midnight)
0 0 * * 0 /usr/local/bin/backup.sh weekly

🛠️ Technologies Used
Skill	Usage
rsync	Incremental file-level backups
cron	Automated backup scheduling
tar	Compressing monthly snapshots
sha256sum	Integrity verification
Slack Webhooks	Backup/restore alerting
Filesystem Management	Snapshot rotation & retention
