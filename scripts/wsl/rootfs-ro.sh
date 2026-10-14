#!/bin/bash
# Make system directories read-only via bind mounts
# Usage: sudo rootfs-ro.sh
# Called by wsl-boot.sh on startup, or manually after package installation

set -e

# On systemd WSL the wsl shell and systemd (PID 1) live in DIFFERENT mount
# namespaces. A remount here only affects the caller's namespace, so also apply
# it inside PID 1's namespace (where systemd performs e.g. 'systemctl enable').
if [ -z "${LINUXDEV_IN_PID1_NS:-}" ] && [ -e /proc/1/ns/mnt ] \
   && [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ] \
   && command -v nsenter >/dev/null 2>&1; then
    echo "[systemd mount namespace]"
    LINUXDEV_IN_PID1_NS=1 nsenter -t 1 -m -- bash "$(readlink -f "$0")" \
        || echo "WARNING: could not lock systemd mount namespace"
    echo "[this shell's mount namespace]"
fi

DIRS=(/usr /bin /sbin /lib /lib64 /etc /opt /srv)
FAILED=()

for dir in "${DIRS[@]}"; do
    [ -d "$dir" ] || continue
    # Check if already a bind mount point
    if mountpoint -q "$dir" 2>/dev/null; then
        # Already mounted - just remount ro
        if mount -o remount,ro,bind "$dir" 2>/dev/null; then
            echo "  $dir -> ro (remounted)"
        else
            FAILED+=("$dir")
            echo "  $dir -> FAILED"
        fi
    else
        # First time - bind then ro
        if mount --bind "$dir" "$dir" 2>/dev/null && \
           mount -o remount,ro,bind "$dir" 2>/dev/null; then
            echo "  $dir -> ro"
        else
            FAILED+=("$dir")
            echo "  $dir -> FAILED"
        fi
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "WARNING: Failed to protect: ${FAILED[*]}"
    exit 1
fi

echo "System dirs protected (ro)"
