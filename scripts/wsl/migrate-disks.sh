#!/bin/bash
# migrate-disks.sh -- in-distro filesystem work for the A1 migration (rsync).
#
# Called by migrate-disks.ps1 AFTER it has:
#   - created THREE fresh empty vhdx: data.vhdx, docker.vhdx, brew.vhdx
#   - attached all three as bare block devices (/dev/sdX)
#
# This script (method B -- rsync, no vhdx cloning):
#   1. Identifies the three empty attached devices.
#   2. Formats each: data(linuxdev-data), docker(linuxdev-docker),
#      brew(linuxdev-brew).
#   3. Stops docker so it is not writing /var/lib/docker.
#   4. rsync's /var (excluding /var/lib/docker) and /home into the data volume
#      as /mnt/_migrate_data/{var,home}, preserving perms/owners/ACLs/xattrs.
#   5. Empties the rootfs /var/* and /home/* (keeps the dirs as mountpoints);
#      wipes /var/lib/docker (docker data discarded by design).
#
# Only docker + journald write /var during this; docker is stopped and journald
# only appends harmless log lines, so the copy is consistent.
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

command -v rsync >/dev/null 2>&1 || { log "ERROR: rsync not installed"; exit 1; }

# The rootfs device (so we never format it).
ROOT_DEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
log "rootfs device: $ROOT_DEV"

# All three new vhdx are empty (no filesystem). Collect unformatted whole disks.
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

# Deterministic assignment by device order: data, docker, brew.
DATA_DEV="${EMPTY_DEVS[0]}"
DOCKER_DEV="${EMPTY_DEVS[1]}"
BREW_DEV="${EMPTY_DEVS[2]:-}"

# ---------------------------------------------------------------------
# Step A: format the three volumes
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

log "Copying /var -> data volume (excluding /var/lib/docker)"
rsync -aHAX --numeric-ids --delete \
    --exclude='/lib/docker/' \
    /var/ "$DATA_MNT/var/"
# ensure the mountpoint for the docker volume exists on the data volume
mkdir -p "$DATA_MNT/var/lib/docker"

log "Copying /home -> data volume"
rsync -aHAX --numeric-ids --delete /home/ "$DATA_MNT/home/"

sync
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
