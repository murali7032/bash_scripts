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
