#!/bin/bash
# Temporarily make system directories writable for package installation
# Usage: sudo rootfs-rw.sh
# Run rootfs-ro.sh when done installing

set -e

DIRS=(/usr /bin /sbin /lib /lib64 /etc)

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
