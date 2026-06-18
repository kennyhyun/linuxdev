#!/bin/bash
# Mount additional vhdx disks for /home, /var/lib/docker, /home/linuxbrew
# Called by wsl-boot.sh on startup
#
# Disks are attached from Windows via PowerShell:
#   wsl --mount --vhd "$env:USERPROFILE\linuxdev\home.vhdx" --bare
#   wsl --mount --vhd "$env:USERPROFILE\linuxdev\docker.vhdx" --bare
#   wsl --mount --vhd "$env:USERPROFILE\linuxdev\brew.vhdx" --bare
#
# This script finds the attached devices and mounts them to the correct paths.

LOG="/var/run/wsl-boot.log"

mount_vhdx() {
    local label="$1"    # filesystem label (set during mkfs)
    local mountpoint="$2"

    # Find device by label
    local dev
    dev=$(blkid -L "$label" 2>/dev/null)
    if [ -z "$dev" ]; then
        echo "$(date): $mountpoint -> no device with label '$label', skipping" >> "$LOG"
        return 0
    fi

    if mountpoint -q "$mountpoint" 2>/dev/null; then
        echo "$(date): $mountpoint -> already mounted" >> "$LOG"
        return 0
    fi

    mkdir -p "$mountpoint"
    if mount "$dev" "$mountpoint" 2>/dev/null; then
        echo "$(date): $mountpoint -> mounted ($dev)" >> "$LOG"
    else
        echo "$(date): $mountpoint -> FAILED ($dev)" >> "$LOG"
    fi
}

# Mount home disk (label: linuxdev-home)
mount_vhdx "linuxdev-home" "/home"

# Mount docker disk (label: linuxdev-docker)
mount_vhdx "linuxdev-docker" "/var/lib/docker"

# Mount brew disk (label: linuxdev-brew)
mount_vhdx "linuxdev-brew" "/home/linuxbrew"
