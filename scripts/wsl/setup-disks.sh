#!/bin/bash
# setup-disks.sh -- in-distro work to set up the A1 data layout (rsync seeding).
#
# Called by setup-disks.ps1 AFTER it has:
#   - created TWO fresh empty vhdx: data.vhdx, docker.vhdx
#   - attached both as bare block devices (/dev/sdX)
#
# This script (rsync ONLY -- no fallback):
#   0. REQUIRES rsync. If missing, it aborts immediately (does nothing).
#   1. Identifies the empty attached devices.
#   2. Formats data(linuxdev-data) and docker(linuxdev-docker).
#   3. Preallocates each volume to its INIT size (fallocate) so it does not pay
#      the grow-on-first-write penalty later. INIT=0 disables prealloc.
#   4. Stops docker, then ALWAYS seeds: rsync /var (excluding /var/lib/docker)
#      and /home onto the data volume, preserving perms/owners/ACLs/xattrs.
#   5. VERIFIES the copy (source vs dest byte counts). Only if the copy looks
#      complete does it empty the rootfs /var/* and /home/* (keeping the dirs).
#
# /home/linuxbrew lives inside the data volume -- no separate brew volume.
#
# Usage (invoked by setup-disks.ps1):
#   setup-disks.sh --data-label linuxdev-data --docker-label linuxdev-docker \
#                  --data-init-gb 24 --docker-init-gb 48

set -euo pipefail

DATA_LABEL="linuxdev-data"
DOCKER_LABEL="linuxdev-docker"
DATA_INIT_GB=0
DOCKER_INIT_GB=0
DATA_MNT="/mnt/_setup_data"

while [ $# -gt 0 ]; do
    case "$1" in
        --data-label)     DATA_LABEL="$2";     shift 2 ;;
        --docker-label)   DOCKER_LABEL="$2";   shift 2 ;;
        --data-init-gb)   DATA_INIT_GB="$2";   shift 2 ;;
        --docker-init-gb) DOCKER_INIT_GB="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log() { echo "[setup-disks] $*"; }

# ---------------------------------------------------------------------
# Step 0: rsync is MANDATORY. Do not start without it.
# ---------------------------------------------------------------------
if ! command -v rsync >/dev/null 2>&1; then
    log "ERROR: rsync is not installed. This setup requires rsync."
    log "Install it first (unlock rootfs if read-only):"
    log "  sudo rootfs-rw && apt-get update && apt-get install -y rsync && sudo rootfs-ro"
    log "Aborting without touching any disks."
    exit 1
fi

# used-bytes of a directory tree (one filesystem, apparent size)
tree_bytes() { du -sb --one-file-system "$1" 2>/dev/null | awk '{print $1}'; }

# Preallocate real blocks on a mounted volume: fallocate a reserved file of GB
# size (instant, reserves extents), then remove it. The vhdx keeps the grown
# physical size, but ext4 is empty and ready to use.
preallocate() {
    local mnt="$1" gb="$2"
    [ "${gb:-0}" -gt 0 ] || { log "  prealloc $mnt: skipped (0)"; return 0; }
    log "  prealloc $mnt: fallocate ${gb}G ..."
    if fallocate -l "${gb}G" "$mnt/.linuxdev-prealloc" 2>/dev/null; then
        sync
        rm -f "$mnt/.linuxdev-prealloc"
        log "  prealloc $mnt: ${gb}G reserved"
    else
        log "  prealloc $mnt: WARNING fallocate failed (continuing without prealloc)"
        rm -f "$mnt/.linuxdev-prealloc" 2>/dev/null || true
    fi
}

# The rootfs device (so we never format it).
ROOT_DEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
log "rootfs device: $ROOT_DEV"

# Collect unformatted whole disks (the fresh data/docker vhdx).
EMPTY_DEVS=()
for d in /dev/sd*; do
    [ -b "$d" ] || continue
    echo "$d" | grep -qE 'sd[a-z][0-9]' && continue   # skip partitions
    [ "$d" = "$ROOT_DEV" ] && continue                 # skip rootfs
    fstype="$(blkid -o value -s TYPE "$d" 2>/dev/null || true)"
    [ -n "$fstype" ] && continue                       # skip already-formatted
    EMPTY_DEVS+=("$d")
done

if [ "${#EMPTY_DEVS[@]}" -lt 2 ]; then
    log "ERROR: expected 2 empty disks (data, docker), found ${#EMPTY_DEVS[@]}: ${EMPTY_DEVS[*]:-<none>}"
    exit 1
fi
log "empty devices: ${EMPTY_DEVS[*]}"

DATA_DEV="${EMPTY_DEVS[0]}"
DOCKER_DEV="${EMPTY_DEVS[1]}"

# ---------------------------------------------------------------------
# Step A: format the volumes
# ---------------------------------------------------------------------
log "Formatting $DATA_DEV   -> ext4 [$DATA_LABEL]"
mkfs.ext4 -q -L "$DATA_LABEL" -F "$DATA_DEV"
log "Formatting $DOCKER_DEV -> ext4 [$DOCKER_LABEL]"
mkfs.ext4 -q -L "$DOCKER_LABEL" -F "$DOCKER_DEV"

# ---------------------------------------------------------------------
# Step A2: preallocate docker volume (data is prealloc'd after mount below)
# ---------------------------------------------------------------------
DOCKER_TMP="/mnt/_setup_docker"
mkdir -p "$DOCKER_TMP"
mount "$DOCKER_DEV" "$DOCKER_TMP"
preallocate "$DOCKER_TMP" "$DOCKER_INIT_GB"
umount "$DOCKER_TMP"
rmdir "$DOCKER_TMP" 2>/dev/null || true

# ---------------------------------------------------------------------
# Step B: ALWAYS seed -- rsync /var (minus docker) and /home into data volume
# ---------------------------------------------------------------------
log "Stopping docker before copying /var"
systemctl stop docker 2>/dev/null || true
systemctl stop docker.socket 2>/dev/null || true

mkdir -p "$DATA_MNT"
mount "$DATA_DEV" "$DATA_MNT"
preallocate "$DATA_MNT" "$DATA_INIT_GB"
mkdir -p "$DATA_MNT/var" "$DATA_MNT/home"

SRC_VAR_BYTES="$( { du -sb --one-file-system --exclude='lib/docker' /var 2>/dev/null || true; } | awk '{print $1}')"
SRC_HOME_BYTES="$(tree_bytes /home)"
log "source sizes: /var(excl docker)=${SRC_VAR_BYTES:-0}B /home=${SRC_HOME_BYTES:-0}B"

log "Copying /var -> data volume (excluding /var/lib/docker)"
rsync -aHAX --numeric-ids --delete --exclude='/lib/docker/' /var/ "$DATA_MNT/var/"
mkdir -p "$DATA_MNT/var/lib/docker"

log "Copying /home -> data volume"
rsync -aHAX --numeric-ids --delete /home/ "$DATA_MNT/home/"

sync

# ---------------------------------------------------------------------
# Step B2: VERIFY the copy BEFORE emptying the rootfs
# ---------------------------------------------------------------------
DST_VAR_BYTES="$( { du -sb --one-file-system --exclude='lib/docker' "$DATA_MNT/var" 2>/dev/null || true; } | awk '{print $1}')"
DST_HOME_BYTES="$(tree_bytes "$DATA_MNT/home")"
log "dest sizes:   /var(excl docker)=${DST_VAR_BYTES:-0}B /home=${DST_HOME_BYTES:-0}B"

verify_ratio_ok() {
    local src="$1" dst="$2" name="$3"
    src="${src:-0}"; dst="${dst:-0}"
    if [ "$src" -eq 0 ]; then
        return 0   # nothing to copy (e.g. empty /home)
    fi
    local ok
    ok="$(awk -v s="$src" -v d="$dst" 'BEGIN{ print (d*100 >= s*90) ? 1 : 0 }')"
    if [ "$ok" -ne 1 ]; then
        log "ERROR: $name copy incomplete: dest=${dst}B is < 90% of source=${src}B"
        return 1
    fi
    log "  verify $name OK (dest ${dst}B vs source ${src}B)"
    return 0
}

if ! verify_ratio_ok "$SRC_VAR_BYTES" "$DST_VAR_BYTES" "/var" \
   || ! verify_ratio_ok "$SRC_HOME_BYTES" "$DST_HOME_BYTES" "/home"; then
    log "Copy verification FAILED. Leaving the rootfs untouched (no data lost)."
    log "The data volume may be partially written; re-run setup with -Force."
    umount "$DATA_MNT" 2>/dev/null || true
    rmdir "$DATA_MNT" 2>/dev/null || true
    exit 1
fi

umount "$DATA_MNT"
rmdir "$DATA_MNT" 2>/dev/null || true

# ---------------------------------------------------------------------
# Step C: empty the rootfs /var and /home (keep dirs as mountpoints)
# ---------------------------------------------------------------------
log "Emptying rootfs /home/*"
shopt -s dotglob
for entry in /home/*; do
    [ -e "$entry" ] || continue
    rm -rf --one-file-system "$entry"
done
shopt -u dotglob

log "Emptying rootfs /var/* (keeps /var as a mountpoint)"
shopt -s dotglob
for entry in /var/*; do
    name="$(basename "$entry")"
    case "$name" in
        lost+found) : ;;
        *) rm -rf --one-file-system "$entry" 2>/dev/null || true ;;
    esac
done
shopt -u dotglob
mkdir -p /var/lib/docker

log "Done. data=$DATA_DEV docker=$DOCKER_DEV"
log "Reboot (wsl --terminate) and let the .mount units take over."
