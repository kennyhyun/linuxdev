#!/bin/bash
# WSL2 boot script — runs as root via /etc/wsl.conf [boot] command
# Protects system dirs from corruption on forced shutdown

LOG="/var/run/wsl-boot.log"
SCRIPTS_DIR="/usr/local/lib/linuxdev"

echo "$(date): wsl-boot.sh starting" >> "$LOG"

# Mount additional disks (home, docker, brew) if attached
if [ -f "$SCRIPTS_DIR/mount-disks.sh" ]; then
    bash "$SCRIPTS_DIR/mount-disks.sh"
fi

# Protect system dirs with bind+ro mounts
if [ -f "$SCRIPTS_DIR/rootfs-ro.sh" ]; then
    bash "$SCRIPTS_DIR/rootfs-ro.sh" >> "$LOG" 2>&1
else
    # Fallback inline (before bootstrap installs scripts)
    for dir in /usr /bin /sbin /lib /lib64 /etc; do
        [ -d "$dir" ] || continue
        mountpoint -q "$dir" 2>/dev/null || mount --bind "$dir" "$dir" 2>/dev/null
        mount -o remount,ro,bind "$dir" 2>/dev/null && \
            echo "$(date): $dir -> ro" >> "$LOG" || \
            echo "$(date): $dir -> FAILED" >> "$LOG"
    done
    if ! mountpoint -q /var/log 2>/dev/null; then
        mount -t tmpfs -o size=64m tmpfs /var/log
        echo "$(date): /var/log -> tmpfs" >> "$LOG"
    fi
fi

echo "$(date): wsl-boot.sh done" >> "$LOG"
