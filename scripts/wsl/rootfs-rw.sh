#!/bin/bash
# Temporarily make system directories writable for package installation
# Usage: sudo rootfs-rw.sh
# Run rootfs-ro.sh when done installing

set -e

# On systemd WSL the wsl shell and systemd (PID 1) live in DIFFERENT mount
# namespaces. A remount here only affects the caller's namespace; package
# scripts call 'systemctl enable', which systemd executes in ITS namespace, so
# unlock that one too (otherwise: "Failed to enable unit: Read-only file system").
if [ -z "${LINUXDEV_IN_PID1_NS:-}" ] && [ -e /proc/1/ns/mnt ] \
   && [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ] \
   && command -v nsenter >/dev/null 2>&1; then
    echo "[systemd mount namespace]"
    LINUXDEV_IN_PID1_NS=1 nsenter -t 1 -m -- bash "$(readlink -f "$0")" \
        || echo "WARNING: could not unlock systemd mount namespace"
    echo "[this shell's mount namespace]"
fi

DIRS=(/usr /bin /sbin /lib /lib64 /etc /opt /srv)

for dir in "${DIRS[@]}"; do
    [ -d "$dir" ] || continue
    if mountpoint -q "$dir" 2>/dev/null; then
        if mount -o remount,rw,bind "$dir" 2>/dev/null; then
            echo "  $dir -> rw"
        else
            echo "  $dir -> FAILED (may already be rw)"
        fi
    else
        echo "  $dir -> not a mountpoint, already rw"
    fi
done

echo ""
echo "System dirs unlocked (rw)"
echo "Run 'sudo rootfs-ro.sh' when done installing"
