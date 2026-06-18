#!/bin/bash
# WSL2 bootstrap script — idempotent, safe to run multiple times
# Run inside WSL after first boot (or to update):
#   sudo bash /mnt/c/Users/<user>/linuxdev/bootstrap-wsl.sh
#
# What gets installed:
#   Base packages : git, zsh, curl, sudo, htop, tmux, jq, python3, kubectl, etc.
#   linuxdev role : docker-ce, microk8s (snap), opentofu, Homebrew (/home/linuxbrew)
#   linuxdev tools: rootfs-ro/rw, mount-disks, wsl-boot.sh, wsl.conf
#
# Options:
#   --user <name>     Set default username (skips prompt)
#   --skip-pkgs       Skip dotfiles/linux.sh install (tools + docker + microk8s)
#   --dotfiles <url>  Use custom dotfiles repo (default: kennyhyun/dotfiles main)
#   --export          Print export instructions at end

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUXDEV_SCRIPTS="/usr/local/lib/linuxdev"
LINUXDEV_BIN="/usr/local/bin"
WSL_CONF="/etc/wsl.conf"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/kennyhyun/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"

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
            mount -o remount,rw,bind "$dir" 2>/dev/null && \
                log "  $dir -> rw" || log "  $dir -> already rw or skipped"
        fi
    done
}

lock_rootfs() {
    log "Re-locking system dirs..."
    if [ -f "$LINUXDEV_SCRIPTS/rootfs-ro.sh" ]; then
        bash "$LINUXDEV_SCRIPTS/rootfs-ro.sh" || log "WARNING: rootfs-ro partial failure"
    else
        # Fallback — before scripts are installed
        for dir in /usr /bin /sbin /lib /lib64 /etc; do
            [ -d "$dir" ] || continue
            mountpoint -q "$dir" 2>/dev/null || mount --bind "$dir" "$dir" 2>/dev/null || true
            mount -o remount,ro,bind "$dir" 2>/dev/null && \
                log "  $dir -> ro" || log "  $dir -> FAILED (skipping)"
        done
        mountpoint -q /var/log 2>/dev/null || \
            mount -t tmpfs -o size=64m tmpfs /var/log 2>/dev/null || true
    fi
}

current_wsl_user() {
    [ -f "$WSL_CONF" ] && \
        grep -m1 "^default" "$WSL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true
}

# =============================================
# Args
# =============================================
USERNAME="${WSL_USERNAME:-}"
EXPORT_AFTER=0
SKIP_PACKAGES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)      USERNAME="$2"; shift 2 ;;
        --dotfiles)  DOTFILES_REPO="$2"; shift 2 ;;
        --export)    EXPORT_AFTER=1; shift ;;
        --skip-pkgs) SKIP_PACKAGES=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

require_root

# =============================================
# Step 1: Determine username
# =============================================
if [ -z "$USERNAME" ]; then
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
# Step 2: Unlock rootfs for installation
# =============================================
unlock_rootfs

# =============================================
# Step 3: Install via dotfiles linux.sh
# =============================================
if [ "$SKIP_PACKAGES" -ne 1 ]; then
    log "Installing packages via dotfiles ($DOTFILES_REPO @ $DOTFILES_BRANCH)..."
    log ""
    log "This installs:"
    log "  Base: git, zsh, curl, htop, tmux, jq, python3, kubectl, net-tools..."
    log "  linuxdev role: docker-ce, microk8s, opentofu, Homebrew (/home/linuxbrew)"
    log ""

    # Clone to temp dir, run as target user if they exist, else as root
    TMPDIR_DOTFILES="$(mktemp -d)"
    git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$TMPDIR_DOTFILES/dotfiles"

    if id "$USERNAME" &>/dev/null; then
        # Run as target user so Homebrew installs to their home
        sudo -u "$USERNAME" bash -c "
            PRODUCTION=1 bash '$TMPDIR_DOTFILES/dotfiles/scripts/linux.sh' linuxdev
        "
    else
        # User not created yet — run as root, fix ownership later
        PRODUCTION=1 bash "$TMPDIR_DOTFILES/dotfiles/scripts/linux.sh" linuxdev
    fi

    rm -rf "$TMPDIR_DOTFILES"
    log "Packages installed"
fi

# =============================================
# Step 4: Create/update default user
# =============================================
if ! id "$USERNAME" &>/dev/null; then
    log "Creating user $USERNAME..."
    useradd -m -s /bin/zsh -G sudo,docker,microk8s "$USERNAME" 2>/dev/null || \
        useradd -m -s /bin/zsh -G sudo "$USERNAME"
    echo "$USERNAME:$USERNAME" | chpasswd
    log "User $USERNAME created (default password: $USERNAME — change with passwd)"
else
    log "User $USERNAME already exists — updating shell and groups"
    usermod -s /bin/zsh "$USERNAME" 2>/dev/null || true
    usermod -aG sudo "$USERNAME" 2>/dev/null || true
    usermod -aG docker "$USERNAME" 2>/dev/null || true
    usermod -aG microk8s "$USERNAME" 2>/dev/null || true
fi

# Sudoers (fixed filename — idempotent)
SUDOERS_FILE="/etc/sudoers.d/linuxdev-nopasswd"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
log "Sudo nopasswd configured: $SUDOERS_FILE"

# =============================================
# Step 5: Install linuxdev scripts
# =============================================
log "Installing linuxdev scripts to $LINUXDEV_SCRIPTS..."
mkdir -p "$LINUXDEV_SCRIPTS"
cp "$SCRIPT_DIR/scripts/wsl/rootfs-ro.sh"   "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/rootfs-rw.sh"   "$LINUXDEV_SCRIPTS/"
cp "$SCRIPT_DIR/scripts/wsl/mount-disks.sh" "$LINUXDEV_SCRIPTS/"
chmod +x "$LINUXDEV_SCRIPTS/"*.sh

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
log " Apply: wsl --terminate Linuxdev  (from PowerShell)"
log ""
log " Rename user later:"
log "   sudo rootfs-rw"
log "   sudo usermod -l newname -d /home/newname -m $USERNAME"
log "   sudo groupmod -n newname $USERNAME"
log "   sudo sed -i 's/default = .*/default = newname/' $WSL_CONF"
log "   sudo rootfs-ro"
log "   wsl --terminate Linuxdev"
log "================================================"

if [ "$EXPORT_AFTER" -eq 1 ]; then
    log ""
    log " Export for release (PowerShell after wsl --terminate):"
    log "   .\\scripts\\wsl\\export-wsl.ps1 -Upload"
fi
