#!/bin/bash
# WSL2 bootstrap script -- idempotent, safe to run multiple times
#
# Run inside WSL after setup-disks.ps1 (home/docker/brew vhdx mounted):
#   sudo bash /mnt/c/Users/<user>/linuxdev/bootstrap-wsl.sh
#
# Usually invoked automatically by setup.ps1 -wsl in non-interactive mode:
#   bootstrap-wsl.sh --noninteractive --envfile /mnt/c/Users/<user>/linuxdev/.env
#
# What gets installed/configured:
#   - git, zsh, curl, sudo, ca-certificates (bootstrap essentials)
#   - docker-ce, microk8s, kubectl
#   - oh-my-zsh for the default user
#   - default user with UID 1000, sudo NOPASSWD
#   - hostname (from NAME), __VM__ env vars, __VMHOSTS__ /etc/hosts entries
#   - systemd enabled + linuxdev-boot.service (mount disks + readonly rootfs)
#   - rootfs-ro / rootfs-rw toggle commands
#
# Dotfiles (Homebrew, zsh config, neovim, etc.) are NOT installed automatically.
# Instructions are printed at the end.
#
# Options:
#   --user <name>      Set default username (skips prompt; default 'linuxdev')
#   --envfile <path>   Load .env (NAME, DOTFILES_REPO, __VM__*, __VMHOSTS__*)
#   --noninteractive   No prompts; use .env / defaults (used by setup.ps1)
#   --skip-pkgs        Skip package installation
#   --export           Print export instructions at end

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
NONINTERACTIVE=0
ENVFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)           USERNAME="$2"; shift 2 ;;
        --envfile)        ENVFILE="$2"; shift 2 ;;
        --noninteractive) NONINTERACTIVE=1; shift ;;
        --export)         EXPORT_AFTER=1; shift ;;
        --skip-pkgs)      SKIP_PACKAGES=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

require_root

# Load host-collected .env (NAME, DOTFILES_REPO, __VM__*, __VMHOSTS__*)
if [ -n "$ENVFILE" ] && [ -f "$ENVFILE" ]; then
    set -a; . "$ENVFILE"; set +a
    log "Loaded env from $ENVFILE"
fi
# Username precedence: --user > WSL_USERNAME/.env > default
USERNAME="${USERNAME:-${WSL_USERNAME:-}}"
MACHINE_NAME="${NAME:-linuxdev}"

# =============================================
# Step 1: Determine username
# =============================================
if [ -z "$USERNAME" ]; then
    if [ "$NONINTERACTIVE" -eq 1 ]; then
        USERNAME="linuxdev"
    else
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
fi
log "Default user: $USERNAME"

# =============================================
# Step 2: Unlock rootfs for installation
# =============================================
unlock_rootfs

# =============================================
# Step 3: Install packages
# =============================================
if [ "$SKIP_PACKAGES" -ne 1 ]; then
    log "Installing base packages..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        git ca-certificates curl wget \
        zsh sudo \
        apt-transport-https gnupg lsb-release \
        dnsutils iputils-ping net-tools \
        htop tmux jq \
        psmisc
    log "Base packages installed"

    # Docker CE
    log "Installing docker-ce..."
    if ! command -v docker &>/dev/null; then
        bash <(curl -fsSL https://raw.githubusercontent.com/kennyhyun/dotfiles/main/scripts/install_docker.sh)
        log "docker-ce installed"
    else
        log "docker already installed: $(docker --version)"
    fi

    # microk8s
    log "Installing microk8s..."
    if ! command -v microk8s &>/dev/null; then
        bash <(curl -fsSL https://raw.githubusercontent.com/kennyhyun/dotfiles/main/scripts/install_microk8s.sh)
        log "microk8s installed"
    else
        log "microk8s already installed"
    fi

    # kubectl
    if ! command -v kubectl &>/dev/null; then
        log "Installing kubectl..."
        ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH/kubectl"
        install -o root -g root -m 0755 kubectl "$LINUXDEV_BIN/kubectl"
        rm kubectl
        log "kubectl installed"
    else
        log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || true)"
    fi
fi

# =============================================
# Step 4: Create/update default user
# =============================================
if ! id "$USERNAME" &>/dev/null; then
    log "Creating user $USERNAME (UID 1000)..."
    # Free UID 1000 if held by a different (distro default) user
    existing_1000="$(getent passwd 1000 | cut -d: -f1)"
    if [ -n "$existing_1000" ] && [ "$existing_1000" != "$USERNAME" ]; then
        log "UID 1000 held by '$existing_1000' -- moving it to 1002"
        pkill -u 1000 2>/dev/null || true
        usermod  -u 1002 "$existing_1000" 2>/dev/null || true
        groupmod -g 1002 "$existing_1000" 2>/dev/null || true
        chown -R 1002:1002 "/home/$existing_1000" 2>/dev/null || true
    fi
    useradd -m -u 1000 -s /bin/zsh -G sudo "$USERNAME" 2>/dev/null || \
        useradd -m -u 1000 -s /bin/zsh "$USERNAME"
    usermod -aG docker "$USERNAME" 2>/dev/null || true
    usermod -aG microk8s "$USERNAME" 2>/dev/null || true
    echo "$USERNAME:$USERNAME" | chpasswd
    log "User $USERNAME created (UID $(id -u "$USERNAME"); default password: $USERNAME -- change with: passwd)"
else
    log "User $USERNAME already exists (UID $(id -u "$USERNAME")) -- updating shell and groups"
    usermod -s /bin/zsh "$USERNAME" 2>/dev/null || true
    usermod -aG sudo,docker "$USERNAME" 2>/dev/null || true
    usermod -aG microk8s "$USERNAME" 2>/dev/null || true
fi

# Sudoers -- fixed filename, idempotent
SUDOERS_FILE="/etc/sudoers.d/linuxdev-nopasswd"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
log "Sudo nopasswd configured"

# oh-my-zsh for the default user (idempotent, unattended)
if [ "$SKIP_PACKAGES" -ne 1 ]; then
    if [ ! -d "/home/$USERNAME/.oh-my-zsh" ]; then
        log "Installing oh-my-zsh for $USERNAME..."
        su - "$USERNAME" -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' \
            || log "WARNING: oh-my-zsh install failed (continuing)"
    else
        log "oh-my-zsh already present for $USERNAME"
    fi
fi

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
# Step 6: Configure wsl.conf (systemd), hostname, env, hosts
# =============================================
# Keep wsl-boot.sh as a non-systemd fallback (used only if systemd is off)
log "Installing wsl-boot.sh (fallback)..."
cp "$SCRIPT_DIR/config/wsl/wsl-boot.sh" "$LINUXDEV_BIN/wsl-boot.sh"
chmod +x "$LINUXDEV_BIN/wsl-boot.sh"

log "Writing /etc/wsl.conf (systemd enabled)..."
cat > "$WSL_CONF" << EOF
[boot]
systemd = true

[user]
default = $USERNAME

[network]
hostname = $MACHINE_NAME
EOF
log "wsl.conf written (user: $USERNAME, hostname: $MACHINE_NAME)"

# Install boot tasks as a systemd oneshot unit (replaces [boot] command)
log "Installing linuxdev-boot.service..."
cp "$SCRIPT_DIR/config/wsl/linuxdev-boot.service" /etc/systemd/system/linuxdev-boot.service
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable linuxdev-boot.service 2>/dev/null \
        && log "linuxdev-boot.service enabled" \
        || log "WARNING: could not enable linuxdev-boot.service"
else
    # systemd is not PID1 yet (becomes PID1 after 'wsl --terminate').
    # Create the enable symlink manually so it activates on next systemd boot.
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/linuxdev-boot.service \
        /etc/systemd/system/multi-user.target.wants/linuxdev-boot.service
    log "systemd not active yet; unit linked to enable on next boot (wsl --terminate)."
fi

# ---- hostname (/etc/hostname + loopback entry) ----
log "Setting hostname: $MACHINE_NAME"
echo "$MACHINE_NAME" > /etc/hostname
grep -q "127.0.1.1[[:space:]]\+$MACHINE_NAME" /etc/hosts 2>/dev/null \
    || echo "127.0.1.1 $MACHINE_NAME" >> /etc/hosts

# ---- __VMHOSTS__ entries -> /etc/hosts ----
#   __VMHOSTS__127_0_0_1=foo  ->  "127.0.0.1 foo"
for var in $(compgen -A variable | grep '^__VMHOSTS__' || true); do
    host="${!var}"
    [ -n "$host" ] || continue
    ip="$(echo "${var#__VMHOSTS__}" | cut -f1-4 -d'_' | tr _ .)"
    if ! grep -q "$ip $host" /etc/hosts 2>/dev/null; then
        echo "$ip $host" >> /etc/hosts
        log "hosts: $ip $host"
    fi
done

# ---- __VM__ env vars -> user's shell rc (export __VM__X as X) ----
for var in $(compgen -A variable | grep '^__VM__' || true); do
    entry="${var#__VM__}=${!var}"
    for rc in "/home/$USERNAME/.zshrc" "/home/$USERNAME/.bashrc"; do
        touch "$rc"
        grep -q "export $entry" "$rc" 2>/dev/null || echo "export $entry" >> "$rc"
    done
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.zshrc" "/home/$USERNAME/.bashrc" 2>/dev/null || true
    log "env: exported ${var#__VM__}"
done

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
log " Default user: $USERNAME   hostname: $MACHINE_NAME"
log ""
log " NEXT: Apply systemd + config by restarting WSL (PowerShell):"
log "   wsl --terminate Linuxdev"
log "   wsl -d Linuxdev"
log "   (installed services auto-start via systemd; rootfs is readonly on boot)"
log ""
log " Install packages later (rootfs is readonly):"
log "   sudo rootfs-rw    # unlock /usr,/etc,..."
log "   sudo apt-get install <pkg>"
log "   sudo rootfs-ro    # re-lock"
log ""
log " NEXT: Install dotfiles (run as $USERNAME):"
log "   git clone $DOTFILES_REPO ~/dotfiles"
log "   PRODUCTION=1 bash ~/dotfiles/scripts/linux.sh linuxdev"
log ""
log " Optional: turn this host into a GitLab CI runner:"
log "   sudo bash $SCRIPT_DIR/scripts/wsl/install-runner.sh --token <t> \\"
log "     --tags linux,localstack,runner --autostart"
log "================================================"

if [ "$EXPORT_AFTER" -eq 1 ]; then
    log ""
    log " Export for release (PowerShell after wsl --terminate):"
    log "   .\\scripts\\wsl\\export-wsl.ps1 -Upload"
fi
