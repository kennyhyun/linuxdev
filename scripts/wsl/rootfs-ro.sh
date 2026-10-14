#!/bin/bash
# Make system directories read-only via bind mounts
# Usage: sudo rootfs-ro.sh
# Called by wsl-boot.sh on startup, or manually after package installation

set -e

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
