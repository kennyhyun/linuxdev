#!/bin/bash
# WSL2 bootstrap script
# Run inside WSL after first boot:
#   bash /mnt/c/Users/<user>/linuxdev/bootstrap-wsl.sh
#
# What it does:
#   1. Unlock system dirs (rootfs-rw)
#   2. Install packages (zsh, git, docker, microk8s, etc.)
#   3. Install linuxdev scripts to /usr/local/lib/linuxdev/
#   4. Install wsl-boot.sh + wsl.conf
#   5. Optionally rename default user
#   6. Re-lock system dirs (rootfs-ro)
#   7. Optionally export distro for release

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUXDEV_SCRIPTS="/usr/local/lib/linuxdev"
LINUXDEV_BIN="/usr/local/bin"

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

unlock_rootfs() {
    log "Unlocking system dirs for installation..."
    for dir in /usr /bin /sbin /lib /lib64 /etc; do
        [ -d "$dir" ] || continue
        if mountpoint -q "$dir" 2>/dev/null; then
            mount -o remount,rw,bind "$dir" 2>/dev/null && log "  $dir -> rw" || true
        fi
    done
}

lock_rootfs() {
    log "Re-locking system dirs..."
    bash "$LINUXDEV_SCRIPTS/rootfs-ro.sh"
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
# Step 1: Prompt for username if not set
# =============================================
if [ -z "$USERNAME" ]; then
    echo -n "[bootstrap] Enter default username [linuxdev]: "
    read -r input
    USERNAME="${input:-linuxdev}"
fi
log "Default user: $USERNAME"

# =============================================
# Step 2: Unlock rootfs
# =============================================
unlock_rootfs

# =============================================
# Step 3: Install packages
# =============================================
if [ "$SKIP_PACKAGES" -ne 1 ]; then
    log "Installing packages..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        zsh git curl wget sudo \
        ca-certificates gnupg lsb-release \
        apt-transport-https \
        dnsutils iputils-ping \
        vim-tiny \
        2>/dev/null
    log "Packages installed"
fi

# =============================================
# Step 4: Create default user
# =============================================
if ! id "$USERNAME" &>/dev/null; then
    log "Creating user $USERNAME..."
    useradd -m -s /bin/zsh -G sudo "$USERNAME"
    # Set password (interactive or blank for WSL)
    echo "$USERNAME:$USERNAME" | chpasswd
    log "User $USERNAME created (password: $USERNAME — change with passwd)"
else
    log "User $USERNAME already exists"
    # Update shell to zsh if needed
    chsh -s /bin/zsh "$USERNAME" 2>/dev/null || true
fi

# Ensure sudo without password for WSL convenience
if ! grep -q "$USERNAME" /etc/sudoers.d/wsl-nopasswd 2>/dev/null; then
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/wsl-nopasswd
    chmod 440 /etc/sudoers.d/wsl-nopasswd
    log "Sudo nopasswd configured for $USERNAME"
fi

# =============================================
# Step 5: Install linuxdev scripts
# =============================================
log "Installing linuxdev scripts to $LINUXDEV_SCRIPTS..."
mkdir -p "$LINUXDEV_SCRIPTS"

cp "$SCRIPT_DIR/scripts/wsl/rootfs-ro.sh" "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/rootfs-rw.sh" "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/mount-disks.sh" "$LINUXDEV_SCRIPTS/"
chmod +x "$LINUXDEV_SCRIPTS/"*.sh

# Symlink to /usr/local/bin for easy CLI access
ln -sf "$LINUXDEV_SCRIPTS/rootfs-ro.sh" "$LINUXDEV_BIN/rootfs-ro"
ln -sf "$LINUXDEV_SCRIPTS/rootfs-rw.sh" "$LINUXDEV_BIN/rootfs-rw"
log "rootfs-ro / rootfs-rw available as commands"

# =============================================
# Step 6: Install wsl-boot.sh + wsl.conf
# =============================================
log "Installing wsl-boot.sh..."
cp "$SCRIPT_DIR/config/wsl/wsl-boot.sh" "$LINUXDEV_BIN/wsl-boot.sh"
chmod +x "$LINUXDEV_BIN/wsl-boot.sh"

log "Writing /etc/wsl.conf..."
cat > /etc/wsl.conf << EOF
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
# Step 8: Rename user (optional, post-bootstrap)
# =============================================
log ""
log "================================================"
log " Bootstrap complete."
log " Default user: $USERNAME"
log ""
log " To rename user later:"
log "   sudo rootfs-rw"
log "   sudo usermod -l newname $USERNAME"
log "   sudo usermod -d /home/newname -m newname"
log "   sudo groupmod -n newname $USERNAME"
log "   Edit /etc/wsl.conf: default = newname"
log "   sudo rootfs-ro"
log "   wsl --terminate Linuxdev  (from PowerShell)"
log "================================================"

# =============================================
# Step 9: Export distro (optional, for release)
# =============================================
if [ "$EXPORT_AFTER" -eq 1 ]; then
    log ""
    log "Exporting distro for release..."
    log "Run from PowerShell after 'wsl --terminate':"
    log ""
    log "  wsl --export Debian \$env:USERPROFILE\\linuxdev\\exports\\linuxdev-x64-\$(Get-Date -Format yyyyMMdd).tar"
    log "  # Then compress and upload via scripts/wsl/export-wsl.ps1"
    log ""
    log "Or run the export script directly from PowerShell:"
    log "  .\\scripts\\wsl\\export-wsl.ps1"
fi
