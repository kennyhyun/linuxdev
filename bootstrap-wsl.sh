#!/bin/bash
# WSL2 bootstrap script — idempotent, safe to run multiple times
# Run inside WSL after first boot (or to update):
#   sudo bash /mnt/c/Users/<user>/linuxdev/bootstrap-wsl.sh
#
# Options:
#   --user <name>   Set default username (skips prompt)
#   --skip-pkgs     Skip apt package install
#   --export        Print export instructions at the end

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUXDEV_SCRIPTS="/usr/local/lib/linuxdev"
LINUXDEV_BIN="/usr/local/bin"
WSL_CONF="/etc/wsl.conf"

# =============================================
# Helpers
# =============================================
log() { echo "[bootstrap] $*"; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root: sudo bash $0 $*"
        exit 1
    fi
}

# Unlock system dirs — always safe to call, even if already rw
unlock_rootfs() {
    log "Unlocking system dirs for installation..."
    for dir in /usr /bin /sbin /lib /lib64 /etc; do
        [ -d "$dir" ] || continue
        if mountpoint -q "$dir" 2>/dev/null; then
            mount -o remount,rw,bind "$dir" 2>/dev/null && \
                log "  $dir -> rw" || log "  $dir -> already rw or skipped"
        fi
        # Not a mountpoint = already rw from base ext4, nothing to do
    done
}

# Re-lock system dirs — always safe to call
lock_rootfs() {
    log "Re-locking system dirs..."
    # rootfs-ro.sh may not exist yet on very first run — use inline fallback
    if [ -f "$LINUXDEV_SCRIPTS/rootfs-ro.sh" ]; then
        bash "$LINUXDEV_SCRIPTS/rootfs-ro.sh" || log "WARNING: rootfs-ro partial failure"
    else
        for dir in /usr /bin /sbin /lib /lib64 /etc; do
            [ -d "$dir" ] || continue
            mountpoint -q "$dir" 2>/dev/null || mount --bind "$dir" "$dir" 2>/dev/null || true
            mount -o remount,ro,bind "$dir" 2>/dev/null && \
                log "  $dir -> ro" || log "  $dir -> FAILED (skipping)"
        done
        if ! mountpoint -q /var/log 2>/dev/null; then
            mount -t tmpfs -o size=64m tmpfs /var/log 2>/dev/null || true
        fi
    fi
}

# Read current default user from wsl.conf if set
current_wsl_user() {
    if [ -f "$WSL_CONF" ]; then
        grep -m1 "^default" "$WSL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true
    fi
}

# =============================================
# Args
# =============================================
USERNAME="${WSL_USERNAME:-}"
EXPORT_AFTER=0
SKIP_PACKAGES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)       USERNAME="$2"; shift 2 ;;
        --export)     EXPORT_AFTER=1; shift ;;
        --skip-pkgs)  SKIP_PACKAGES=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

require_root

# =============================================
# Step 1: Determine username
# =============================================
if [ -z "$USERNAME" ]; then
    # Try to read from existing wsl.conf
    EXISTING_USER="$(current_wsl_user)"
    if [ -n "$EXISTING_USER" ]; then
        log "Found existing user in wsl.conf: $EXISTING_USER"
        echo -n "[bootstrap] Keep '$EXISTING_USER' as default user? [Y/n]: "
        read -r input
        if [[ "$input" =~ ^[Nn] ]]; then
            echo -n "[bootstrap] Enter new default username: "
            read -r USERNAME
        else
            USERNAME="$EXISTING_USER"
        fi
    else
        echo -n "[bootstrap] Enter default username [linuxdev]: "
        read -r input
        USERNAME="${input:-linuxdev}"
    fi
fi
log "Default user: $USERNAME"

# =============================================
# Step 2: Unlock rootfs
# =============================================
unlock_rootfs

# =============================================
# Step 3: Install packages (idempotent — apt handles it)
# =============================================
if [ "$SKIP_PACKAGES" -ne 1 ]; then
    log "Installing packages..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        zsh git curl wget sudo \
        ca-certificates gnupg lsb-release \
        apt-transport-https \
        dnsutils iputils-ping \
        vim-tiny
    log "Packages installed"
fi

# =============================================
# Step 4: Create/update default user
# =============================================
if ! id "$USERNAME" &>/dev/null; then
    log "Creating user $USERNAME..."
    useradd -m -s /bin/zsh -G sudo "$USERNAME"
    echo "$USERNAME:$USERNAME" | chpasswd
    log "User $USERNAME created (default password: $USERNAME — change with passwd)"
else
    log "User $USERNAME already exists — updating shell and groups"
    usermod -s /bin/zsh "$USERNAME" 2>/dev/null || true
    # Add to sudo group if not already
    usermod -aG sudo "$USERNAME" 2>/dev/null || true
fi

# Sudoers — replace old entry if username changed
SUDOERS_FILE="/etc/sudoers.d/linuxdev-nopasswd"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
log "Sudo nopasswd configured: $SUDOERS_FILE"

# =============================================
# Step 5: Install linuxdev scripts (idempotent — cp overwrites)
# =============================================
log "Installing linuxdev scripts to $LINUXDEV_SCRIPTS..."
mkdir -p "$LINUXDEV_SCRIPTS"

cp "$SCRIPT_DIR/scripts/wsl/rootfs-ro.sh"   "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/rootfs-rw.sh"   "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/mount-disks.sh" "$LINUXDEV_SCRIPTS/"
chmod +x "$LINUXDEV_SCRIPTS/"*.sh

# Symlinks (ln -sf is idempotent)
ln -sf "$LINUXDEV_SCRIPTS/rootfs-ro.sh" "$LINUXDEV_BIN/rootfs-ro"
ln -sf "$LINUXDEV_SCRIPTS/rootfs-rw.sh" "$LINUXDEV_BIN/rootfs-rw"
log "rootfs-ro / rootfs-rw available as commands"

# =============================================
# Step 6: Install wsl-boot.sh + wsl.conf (idempotent — overwrites)
# =============================================
log "Installing wsl-boot.sh..."
cp "$SCRIPT_DIR/config/wsl/wsl-boot.sh" "$LINUXDEV_BIN/wsl-boot.sh"
chmod +x "$LINUXDEV_BIN/wsl-boot.sh"

log "Writing /etc/wsl.conf..."
cat > "$WSL_CONF" << EOF
[boot]
command = /usr/local/bin/wsl-boot.sh

[user]
default = $USERNAME
EOF
log "wsl.conf written (default user: $USERNAME)"

# =============================================
# Step 7: Re-lock rootfs
# =============================================
lock_rootfs

# =============================================
# Done
# =============================================
log ""
log "================================================"
log " Bootstrap complete ($(date))"
log " Default user  : $USERNAME"
log " wsl.conf      : $WSL_CONF"
log " Scripts       : $LINUXDEV_SCRIPTS/"
log ""
log " Apply changes: wsl --terminate Linuxdev (PowerShell)"
log ""
log " To rename user later:"
log "   sudo rootfs-rw"
log "   sudo usermod -l newname -d /home/newname -m $USERNAME"
log "   sudo groupmod -n newname $USERNAME"
log "   sudo sed -i 's/default = .*/default = newname/' $WSL_CONF"
log "   sudo rootfs-ro"
log "   wsl --terminate Linuxdev  (from PowerShell)"
log "================================================"

if [ "$EXPORT_AFTER" -eq 1 ]; then
    log ""
    log " Export for release — run from PowerShell after wsl --terminate:"
    log "   .\\scripts\\wsl\\export-wsl.ps1"
    log "   .\\scripts\\wsl\\export-wsl.ps1 -Upload  (publishes to GitHub)"
fi
