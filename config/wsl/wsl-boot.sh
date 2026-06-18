#!/bin/bash
# WSL2 boot script — runs as root via /etc/wsl.conf [boot] command
# Goal: protect system directories from corruption on forced shutdown
#   - bind+remount ro: /usr /bin /sbin /lib /lib64 /etc
#   - /var/log on tmpfs: prevents journal corruption on forced kill

LOG="/var/run/wsl-boot.log"

echo "$(date): wsl-boot.sh starting" >> "$LOG"

# Protect system dirs with bind+ro mounts
for dir in /usr /bin /sbin /lib /lib64 /etc; do
    [ -d "$dir" ] || continue
    if mount --bind "$dir" "$dir" 2>/dev/null && \
       mount -o remount,ro,bind "$dir" 2>/dev/null; then
        echo "$(date): $dir -> ro" >> "$LOG"
    else
        echo "$(date): $dir -> FAILED" >> "$LOG"
    fi
done

# Move /var/log to tmpfs to prevent journal corruption on forced shutdown
if ! mountpoint -q /var/log; then
    mount -t tmpfs -o size=64m tmpfs /var/log
    echo "$(date): /var/log -> tmpfs" >> "$LOG"
fi

echo "$(date): wsl-boot.sh done" >> "$LOG"
