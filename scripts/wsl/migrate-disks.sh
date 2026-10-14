#!/bin/bash
# migrate-disks.sh -- in-distro filesystem work for the A1 migration (rsync).
#
# Called by migrate-disks.ps1 AFTER it has:
#   - created THREE fresh empty vhdx: data.vhdx, docker.vhdx, brew.vhdx
#   - attached all three as bare block devices (/dev/sdX)
#
# This script (rsync ONLY -- no fallback):
#   0. REQUIRES rsync. If missing, it aborts immediately (does nothing).
#   1. Identifies the empty attached devices.
#   2. Formats data(linuxdev-data), docker(linuxdev-docker), brew(linuxdev-brew).
#   3. Stops docker so it is not writing /var/lib/docker.
#   4. rsync's /var (excluding /var/lib/docker) and /home onto the data volume,
#      preserving perms/owners/ACLs/xattrs/hardlinks.
#   5. VERIFIES the copy (compares source vs destination byte counts). Only if
#      the copy looks complete does it empty the rootfs /var/* and /home/*
#      (keeping the dirs as mountpoints). This prevents wiping the rootfs when
#      the copy silently failed.
#
# Usage (invoked by migrate-disks.ps1):
#   migrate-disks.sh --data-label linuxdev-data \
#                    --docker-label linuxdev-docker \
#                    --brew-label linuxdev-brew

set -euo pipefail

DATA_LABEL="linuxdev-data"
DOCKER_LABEL="linuxdev-docker"
BREW_LABEL="linuxdev-brew"
DATA_MNT="/mnt/_migrate_data"

while [ $# -gt 0 ]; do
    case "$1" in
        --data-label)   DATA_LABEL="$2";   shift 2 ;;
        --docker-label) DOCKER_LABEL="$2"; shift 2 ;;
        --brew-label)   BREW_LABEL="$2";   shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log() { echo "[migrate-disks] $*"; }

# ---------------------------------------------------------------------
# Step 0: rsync is MANDATORY. Do not start without it.
# ---------------------------------------------------------------------
if ! command -v rsync >/dev/null 2>&1; then
    log "ERROR: rsync is not installed. This migration requires rsync."
    log "Install it first (unlock rootfs if read-only):"
    log "  sudo rootfs-rw && apt-get update && apt-get install -y rsync && sudo rootfs-ro"
    log "Aborting without touching any disks."
    exit 1
fi

# used-bytes of a directory tree (one filesystem, apparent size)
tree_bytes() { du -sb --one-file-system "$1" 2>/dev/null | awk '{print $1}'; }

# The rootfs device (so we never format it).
ROOT_DEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
log "rootfs device: $ROOT_DEV"

# Collect unformatted whole disks (the fresh data/docker/brew vhdx).
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
    log "ERROR: expected at least 2 empty disks (data, docker), found ${#EMPTY_DEVS[@]}: ${EMPTY_DEVS[*]:-<none>}"
    exit 1
fi
log "empty devices: ${EMPTY_DEVS[*]}"

DATA_DEV="${EMPTY_DEVS[0]}"
DOCKER_DEV="${EMPTY_DEVS[1]}"
BREW_DEV="${EMPTY_DEVS[2]:-}"

# ---------------------------------------------------------------------
# Step A: format the volumes
# ---------------------------------------------------------------------
log "Formatting $DATA_DEV   -> ext4 [$DATA_LABEL]"
mkfs.ext4 -q -L "$DATA_LABEL" -F "$DATA_DEV"
log "Formatting $DOCKER_DEV -> ext4 [$DOCKER_LABEL]"
mkfs.ext4 -q -L "$DOCKER_LABEL" -F "$DOCKER_DEV"
if [ -n "$BREW_DEV" ]; then
    log "Formatting $BREW_DEV   -> ext4 [$BREW_LABEL]"
    mkfs.ext4 -q -L "$BREW_LABEL" -F "$BREW_DEV"
fi

# ---------------------------------------------------------------------
# Step B: rsync /var (minus docker) and /home into the data volume
# ---------------------------------------------------------------------
log "Stopping docker before copying /var"
systemctl stop docker 2>/dev/null || true
systemctl stop docker.socket 2>/dev/null || true

mkdir -p "$DATA_MNT"
mount "$DATA_DEV" "$DATA_MNT"
mkdir -p "$DATA_MNT/var" "$DATA_MNT/home"

# Source sizes measured the SAME way we exclude in rsync, for an apples-to-
# apples verification afterwards.
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

# Guard: destination must be at least 90% of source (allow small rsync/journald
# deltas). If not, the copy failed -- STOP before wiping the rootfs.
verify_ratio_ok() {
    local src="$1" dst="$2" name="$3"
    src="${src:-0}"; dst="${dst:-0}"
    if [ "$src" -eq 0 ]; then
        return 0   # nothing to copy (e.g. empty /home on clean install)
    fi
    # dst * 100 >= src * 90  (integer math, avoid overflow with awk)
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
    log "The data volume may be partially written; re-run migration with -Force."
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

log "Done. data=$DATA_DEV docker=$DOCKER_DEV brew=${BREW_DEV:-<none>}"
log "Reboot (wsl --terminate) and let the .mount units take over."
