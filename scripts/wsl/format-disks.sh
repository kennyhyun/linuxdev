#!/bin/bash
# Format attached vhdx disks that don't have a label yet
# Called by post-install.ps1 after disks are attached
# Safe to run multiple times — skips already-formatted disks

set -e

LOG="${WSL_BOOT_LOG:-/tmp/wsl-format.log}"

log() { echo "[format-disks] $*" | tee -a "$LOG"; }

format_if_needed() {
    local label="$1"
    local mountpoint="$2"

    # Check if already formatted (label exists)
    local dev
    dev=$(blkid -L "$label" 2>/dev/null || true)
    if [ -n "$dev" ]; then
        log "$label already formatted ($dev) - skipping"
        return 0
    fi

    # Find an unformatted disk block device (no filesystem, no partitions)
    local found=""
    for dev in /dev/sd*; do
        # Skip if not a block device or has partition children
        [ -b "$dev" ] || continue
        # Skip if it has a partition suffix (sdaX)
        echo "$dev" | grep -qE 'sd[a-z][0-9]' && continue
        # Skip if already has a filesystem
        local fstype
        fstype=$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)
        [ -n "$fstype" ] && continue
        # Skip if it's the main rootfs (typically sdf, largest disk)
        local size
        size=$(lsblk -rno SIZE "$dev" 2>/dev/null || true)
        # Skip very large disks (>= 500G = rootfs candidate)
        if echo "$size" | grep -qE '^[0-9]*T|^[5-9][0-9]{2}G|^[0-9]{4,}G'; then
            continue
        fi
        found="$dev"
        break
    done

    if [ -z "$found" ]; then
        log "WARNING: no unformatted disk found for label '$label' -> $mountpoint"
        return 1
    fi

    log "Formatting $found as ext4 [label: $label] for $mountpoint ..."
    mkfs.ext4 -L "$label" -F "$found"
    log "  $found formatted as '$label'"
}

log "Starting disk format check..."

format_if_needed "linuxdev-home"   "/home"
format_if_needed "linuxdev-docker" "/var/lib/docker"
format_if_needed "linuxdev-brew"   "/home/linuxbrew"

log "Done."
