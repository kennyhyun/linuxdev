#!/bin/bash
# setup-disks.sh -- in-distro work to set up the A1 data layout (rsync seeding).
#
# Called by setup-disks.ps1 AFTER it has:
#   - created TWO fresh empty vhdx: data.vhdx, docker.vhdx
#   - attached both as bare block devices (/dev/sdX)
#
# Steps (rsync ONLY -- no fallback):
#   0. REQUIRES rsync. If missing, abort without touching anything.
#   1. Stop the linuxdev .mount units so a pending start job cannot mount the
#      new volume onto /var and /home the moment it gets its label.
#   2. Format data(<distro>-data) and docker(<distro>-docker).
#   3. Mount the ROOTFS BLOCK DEVICE a second time at a private path. All reads
#      (seed source) and all deletes (emptying the rootfs) go through this
#      mount, never through the live /var and /home paths, which may be bind
#      mounts of the data volume. (Reading the live paths once copied the empty
#      data volume onto itself and lost the dpkg DB.)
#   4. rsync rootfs var (excluding var/lib/docker) and home onto the data volume.
#   5. Verify (sizes + var/lib/dpkg present on the data volume). Only then empty
#      the rootfs var/ and home/ (dirs kept as mountpoints).
#
# /home/linuxbrew lives inside the data volume -- no separate brew volume.
#
# Usage (invoked by setup-disks.ps1):
#   setup-disks.sh --data-dev /dev/sdX --docker-dev /dev/sdY \
#                  --data-label <distro>-data --docker-label <distro>-docker \
#                  [--log-file <path>]
#
# The devices are passed in explicitly (setup-disks.ps1 attaches the two vhdx one
# at a time and reports the device each one became). They are NEVER guessed from
# /dev/sd* order: all distros share one WSL2 VM, so stale empty disks left over
# from earlier runs can be present, and a guess formats the wrong disk.

set -euo pipefail

DATA_DEV=""
DOCKER_DEV=""
DATA_LABEL="linuxdev-data"
DOCKER_LABEL="linuxdev-docker"
LOG_FILE=""

DATA_MNT="/mnt/_setup_data"
ROOTFS_SRC="/mnt/_setup_rootfs"
MOUNT_UNITS="var-lib-docker.mount home.mount var.mount mnt-data.mount"

while [ $# -gt 0 ]; do
    case "$1" in
        --data-dev)       DATA_DEV="$2";       shift 2 ;;
        --docker-dev)     DOCKER_DEV="$2";     shift 2 ;;
        --data-label)     DATA_LABEL="$2";     shift 2 ;;
        --docker-label)   DOCKER_LABEL="$2";   shift 2 ;;
        --log-file)       LOG_FILE="$2";       shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Logging: always to stdout; also to LOG_FILE (durable, survives reboot) if set.
if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || LOG_FILE=""
fi
log() {
    local msg="[setup-disks] $*"
    echo "$msg"
    if [ -n "$LOG_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Always release our private mounts, whatever happens.
cleanup() {
    for m in "$DATA_MNT" "$ROOTFS_SRC"; do
        if mountpoint -q "$m" 2>/dev/null; then umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; fi
        rmdir "$m" 2>/dev/null || true
    done
}
trap cleanup EXIT

die() { log "ERROR: $*"; log "Aborting. The rootfs /var and /home were NOT modified."; exit 1; }

log "setup-disks.sh start (data-label=$DATA_LABEL docker-label=$DOCKER_LABEL)"

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
# used-bytes of a var tree, excluding lib/docker (docker has its own volume)
var_bytes() { { du -sb --one-file-system --exclude='lib/docker' "$1" 2>/dev/null || true; } | awk '{print $1}'; }

# Device backing a path (strip any "[/subdir]" bind suffix).
backing_dev() { findmnt -no SOURCE --target "$1" 2>/dev/null | head -1 | sed 's/\[.*//'; }

# The rootfs device (never formatted; used as the seed source).
ROOT_DEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
log "rootfs device: $ROOT_DEV"
[ -b "$ROOT_DEV" ] || die "rootfs device '$ROOT_DEV' is not a block device"

# ---------------------------------------------------------------------
# Step 0b: validate the devices we were given (before anything is touched).
# They are never guessed from /dev/sd* order.
# ---------------------------------------------------------------------
[ -n "$DATA_DEV" ] && [ -n "$DOCKER_DEV" ] || { log "ERROR: --data-dev and --docker-dev are required"; exit 2; }
[ "$DATA_DEV" != "$DOCKER_DEV" ] || die "--data-dev and --docker-dev are the same device ($DATA_DEV)"
for d in "$DATA_DEV" "$DOCKER_DEV"; do
    [ -b "$d" ] || die "$d is not a block device"
    [ "$d" != "$ROOT_DEV" ] || die "$d is the rootfs device"
    fstype="$(blkid -o value -s TYPE "$d" 2>/dev/null || true)"
    [ -z "$fstype" ] || die "$d already has a filesystem ($fstype); refusing to format it"
done
# The .mount units find the volumes by label, and all distros share one VM: a
# second disk with the same label would make them mount the wrong one.
for pair in "$DATA_LABEL|$DATA_DEV" "$DOCKER_LABEL|$DOCKER_DEV"; do
    label="${pair%%|*}"
    other="$(blkid -L "$label" 2>/dev/null || true)"
    [ -z "$other" ] || die "label '$label' is already used by $other (another distro or an old disk). Detach it (wsl --unmount / wsl --shutdown) or use a different distro name."
done
log "data device: $DATA_DEV [$DATA_LABEL]   docker device: $DOCKER_DEV [$DOCKER_LABEL]"

# ---------------------------------------------------------------------
# Step 1: keep the .mount units from grabbing the new volume
# ---------------------------------------------------------------------
# On this boot the units are waiting for LABEL=linuxdev-data to appear; as soon
# as mkfs creates the label they would bind it onto /var and /home. Stopping
# them cancels those pending jobs. The next boot (after wsl --terminate) starts
# them normally.
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    log "Stopping linuxdev mount units (cancel pending jobs): $MOUNT_UNITS"
    # shellcheck disable=SC2086
    systemctl stop $MOUNT_UNITS 2>/dev/null || true
fi
for p in /var /home; do
    dev="$(backing_dev "$p")"
    log "diag: $p backing device before format = ${dev:-?}"
    [ "$dev" = "$ROOT_DEV" ] || die "$p is not on the rootfs ($dev). Detach data disks / reboot and retry."
done

# ---------------------------------------------------------------------
# Step 2: format
# ---------------------------------------------------------------------
log "Formatting $DATA_DEV   -> ext4 [$DATA_LABEL]"
mkfs.ext4 -q -L "$DATA_LABEL" -F "$DATA_DEV"
log "Formatting $DOCKER_DEV -> ext4 [$DOCKER_LABEL]"
mkfs.ext4 -q -L "$DOCKER_LABEL" -F "$DOCKER_DEV"
command -v udevadm >/dev/null 2>&1 && udevadm settle 2>/dev/null || true

# Re-check: nothing may have mounted the new volume onto /var or /home.
for p in /var /home; do
    dev="$(backing_dev "$p")"
    log "diag: $p backing device after format = ${dev:-?}"
    [ "$dev" = "$ROOT_DEV" ] || die "$p got mounted from $dev after formatting."
done

# ---------------------------------------------------------------------
# Step 3: private mount of the rootfs device (seed source)
# ---------------------------------------------------------------------
# The device is already mounted rw at /, so it cannot be mounted ro directly
# ("would change RO state"). Mount rw, then flip THIS mount to read-only with a
# bind remount (the live / stays rw).
mkdir -p "$ROOTFS_SRC"
mount "$ROOT_DEV" "$ROOTFS_SRC" || die "could not mount $ROOT_DEV at $ROOTFS_SRC"
mount -o remount,bind,ro "$ROOTFS_SRC" || die "could not make $ROOTFS_SRC read-only"
SRC_VAR="$ROOTFS_SRC/var"
SRC_HOME="$ROOTFS_SRC/home"
[ -d "$SRC_VAR" ] && [ -d "$SRC_HOME" ] || die "$SRC_VAR or $SRC_HOME missing"
[ -d "$SRC_VAR/lib/dpkg" ] || die "$SRC_VAR/lib/dpkg not found - rootfs var looks incomplete"
log "seed source: $ROOT_DEV mounted read-only at $ROOTFS_SRC"

# ---------------------------------------------------------------------
# Step 4: seed the data volume
# ---------------------------------------------------------------------
log "Stopping docker before copying var"
systemctl stop docker docker.socket 2>/dev/null || true

mkdir -p "$DATA_MNT"
mount "$DATA_DEV" "$DATA_MNT"
mkdir -p "$DATA_MNT/var" "$DATA_MNT/home"

SRC_VAR_BYTES="$(var_bytes "$SRC_VAR")"
SRC_HOME_BYTES="$(tree_bytes "$SRC_HOME")"
log "source sizes (rootfs): var(excl docker)=${SRC_VAR_BYTES:-0}B home=${SRC_HOME_BYTES:-0}B"
log "diag: rootfs home entries: $(ls -A "$SRC_HOME" 2>/dev/null | tr '\n' ' ')"

log "Copying rootfs var -> data volume (excluding var/lib/docker)"
rsync -aHAX --numeric-ids --delete --exclude='/lib/docker/' "$SRC_VAR/" "$DATA_MNT/var/"
mkdir -p "$DATA_MNT/var/lib/docker"

log "Copying rootfs home -> data volume"
rsync -aHAX --numeric-ids --delete "$SRC_HOME/" "$DATA_MNT/home/"
sync

# ---------------------------------------------------------------------
# Step 5: verify, then empty the rootfs var/ and home/
# ---------------------------------------------------------------------
DST_VAR_BYTES="$(var_bytes "$DATA_MNT/var")"
DST_HOME_BYTES="$(tree_bytes "$DATA_MNT/home")"
log "dest sizes:   var(excl docker)=${DST_VAR_BYTES:-0}B home=${DST_HOME_BYTES:-0}B"

verify_ratio_ok() {
    local src="$1" dst="$2" name="$3"
    src="${src:-0}"; dst="${dst:-0}"
    if [ "$src" -eq 0 ]; then
        log "  verify $name: source empty, nothing to copy"
        return 0
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

verify_ratio_ok "$SRC_VAR_BYTES" "$DST_VAR_BYTES" "var" || die "var copy verification failed"
verify_ratio_ok "$SRC_HOME_BYTES" "$DST_HOME_BYTES" "home" || die "home copy verification failed"
[ -d "$DATA_MNT/var/lib/dpkg" ] || die "var/lib/dpkg missing on the data volume after copy"
log "  verify var/lib/dpkg present on data volume"

umount "$DATA_MNT"
rmdir "$DATA_MNT" 2>/dev/null || true

# Empty the rootfs copies through the private mount only (never the live paths).
mount -o remount,bind,rw "$ROOTFS_SRC" || die "could not make $ROOTFS_SRC writable for cleanup"

# Point this distro's mount units at THIS distro's labels (drop-ins override the
# default What=LABEL=linuxdev-* in the unit files). Written through the private
# rootfs mount because the live /etc may already be bind-mounted read-only.
write_label_dropin() {
    local unit="$1" label="$2" d="$ROOTFS_SRC/etc/systemd/system/$1.d"
    mkdir -p "$d"
    printf '[Mount]\nWhat=LABEL=%s\n' "$label" > "$d/10-linuxdev-label.conf"
    log "  $unit -> What=LABEL=$label"
}
log "Pointing the mount units at this distro's labels"
write_label_dropin mnt-data.mount       "$DATA_LABEL"
write_label_dropin var-lib-docker.mount "$DOCKER_LABEL"
systemctl daemon-reload 2>/dev/null || true
shopt -s dotglob nullglob
log "Emptying rootfs home/ (via $ROOTFS_SRC)"
for entry in "$ROOTFS_SRC/home/"*; do
    rm -rf --one-file-system "$entry" || log "  WARNING: could not remove $entry"
done
log "Emptying rootfs var/ (via $ROOTFS_SRC; dir kept as mountpoint)"
for entry in "$ROOTFS_SRC/var/"*; do
    rm -rf --one-file-system "$entry" 2>/dev/null || log "  WARNING: could not remove $entry"
done
shopt -u dotglob nullglob
log "rootfs after cleanup: var=$(tree_bytes "$ROOTFS_SRC/var")B home=$(tree_bytes "$ROOTFS_SRC/home")B"

log "Done. data=$DATA_DEV docker=$DOCKER_DEV"
log "Reboot (wsl --terminate) and let the .mount units take over."
