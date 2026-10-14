#!/bin/bash
# Mount the A1 data layout manually (bootstrap-time / fallback helper).
#
# At normal boot this is done by systemd .mount units (mnt-data.mount,
# var.mount, home.mount, var-lib-docker.mount). But during bootstrap-wsl.sh the
# distro may run without those units active yet, so we mount here so the user's
# /home lands on the data volume (not the rootfs).
#
# Layout:
#   LABEL=linuxdev-data   -> /mnt/data   (holds var/ and home/ subdirs)
#      bind /mnt/data/var  -> /var
#      bind /mnt/data/home -> /home
#   LABEL=linuxdev-docker -> /var/lib/docker
#   LABEL=linuxdev-brew   -> /home/linuxbrew
#
# Idempotent: skips anything already mounted, skips volumes whose label is
# absent (e.g. before migration has run).

LOG="${WSL_BOOT_LOG:-/var/run/wsl-boot.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG="/tmp/wsl-boot.log"

mount_label() {
    local label="$1" mountpoint="$2" opts="$3"
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
    if mount ${opts:+$opts} "$dev" "$mountpoint" 2>/dev/null; then
        echo "$(date): $mountpoint -> mounted ($dev)" >> "$LOG"
    else
        echo "$(date): $mountpoint -> FAILED ($dev)" >> "$LOG"
    fi
}

bind_mount() {
    local src="$1" dst="$2"
    [ -d "$src" ] || { echo "$(date): bind $dst -> source $src missing, skipping" >> "$LOG"; return 0; }
    if mountpoint -q "$dst" 2>/dev/null; then
        echo "$(date): $dst -> already mounted" >> "$LOG"
        return 0
    fi
    mkdir -p "$dst"
    if mount --bind "$src" "$dst" 2>/dev/null; then
        echo "$(date): $dst -> bind ($src)" >> "$LOG"
    else
        echo "$(date): $dst -> bind FAILED ($src)" >> "$LOG"
    fi
}

# 1) data volume + binds for /var and /home
if [ -n "$(blkid -L linuxdev-data 2>/dev/null)" ]; then
    mount_label "linuxdev-data" "/mnt/data" ""
    bind_mount  "/mnt/data/var"  "/var"
    bind_mount  "/mnt/data/home" "/home"
fi

# 2) docker storage (under /var, so after the /var bind above)
mount_label "linuxdev-docker" "/var/lib/docker" ""

# 3) brew (under /home, so after the /home bind above)
mount_label "linuxdev-brew" "/home/linuxbrew" ""
