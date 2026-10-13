#!/bin/bash
# install-runner.sh — install & register a GitLab Runner inside the WSL2 distro.
#
# This is an ON-DEMAND script: it is NOT run by bootstrap-wsl.sh automatically.
# Run it only on a machine you want to turn into a CI runner.
#
# Run inside WSL (as root), after bootstrap-wsl.sh has set up docker:
#   sudo bash /mnt/c/Users/<user>/linuxdev/scripts/wsl/install-runner.sh \
#     --url https://gitlab.imaginetoolbox.com \
#     --token <registration-or-authentication-token> \
#     --tags linux,localstack,runner \
#     --name "wsl2-localstack-$(hostname)"
#
# What it does:
#   - Installs the gitlab-runner binary (official apt repo, pinned major version)
#   - Verifies docker is present (the shell executor builds images via docker)
#   - Registers the runner with the given URL + token + tags
#   - Installs gitlab-runner as a service running as the given user
#   - Prints how to enable auto-start on WSL boot (see --autostart)
#
# Idempotent: re-running re-installs the binary if missing and registers an
# additional runner entry only if --token is provided again.
#
# Options:
#   --url <url>          GitLab instance URL (default: https://gitlab.imaginetoolbox.com)
#   --token <token>      Runner registration/authentication token (required to register)
#   --tags <csv>         Comma-separated tags (default: linux,localstack,runner)
#   --name <desc>        Runner description (default: wsl2-<hostname>)
#   --user <name>        User the runner service runs as (default: wsl.conf default user)
#   --executor <type>    Runner executor (default: shell)
#   --runner-version <v> Pin gitlab-runner apt version (default: unset = repo latest)
#   --autostart          Append a runner-start hook to wsl-boot.sh for auto-start
#   --skip-install       Skip binary install, only register (binary must exist)
#   -h, --help           Show this help

set -e

LINUXDEV_BIN="/usr/local/bin"
WSL_CONF="/etc/wsl.conf"
WSL_BOOT="/usr/local/bin/wsl-boot.sh"

GITLAB_URL="https://gitlab.imaginetoolbox.com"
TOKEN=""
TAGS="linux,localstack,runner"
RUNNER_NAME=""
RUN_USER=""
EXECUTOR="shell"
RUNNER_VERSION=""
AUTOSTART=0
SKIP_INSTALL=0

log() { echo "[install-runner] $*"; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root: sudo bash $0 $*"
        exit 1
    fi
}

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

current_wsl_user() {
    [ -f "$WSL_CONF" ] && \
        grep -m1 "^default" "$WSL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)            GITLAB_URL="$2"; shift 2 ;;
        --token)          TOKEN="$2"; shift 2 ;;
        --tags)           TAGS="$2"; shift 2 ;;
        --name)           RUNNER_NAME="$2"; shift 2 ;;
        --user)           RUN_USER="$2"; shift 2 ;;
        --executor)       EXECUTOR="$2"; shift 2 ;;
        --runner-version) RUNNER_VERSION="$2"; shift 2 ;;
        --autostart)      AUTOSTART=1; shift ;;
        --skip-install)   SKIP_INSTALL=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown arg: $1"; echo "Run with --help for usage."; exit 1 ;;
    esac
done

require_root

# Resolve defaults that depend on the environment
[ -z "$RUNNER_NAME" ] && RUNNER_NAME="wsl2-$(hostname)"
[ -z "$RUN_USER" ] && RUN_USER="$(current_wsl_user)"
[ -z "$RUN_USER" ] && RUN_USER="linuxdev"

# linuxdev images boot with a read-only rootfs — unlock for install if the
# helper is present (installed by bootstrap-wsl.sh).
if [ "$SKIP_INSTALL" -ne 1 ] && command -v rootfs-rw >/dev/null 2>&1; then
    log "Unlocking rootfs for install (rootfs-rw)..."
    rootfs-rw || log "WARNING: rootfs-rw failed; continuing (may already be rw)"
fi

# =============================================
# Step 1: Install the gitlab-runner binary
# =============================================
if [ "$SKIP_INSTALL" -ne 1 ]; then
    if command -v gitlab-runner >/dev/null 2>&1; then
        log "gitlab-runner already installed: $(gitlab-runner --version | head -1)"
    else
        log "Installing gitlab-runner from official apt repository..."
        curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
        if [ -n "$RUNNER_VERSION" ]; then
            apt-get install -y "gitlab-runner=$RUNNER_VERSION"
        else
            apt-get install -y gitlab-runner
        fi
        log "gitlab-runner installed: $(gitlab-runner --version | head -1)"
    fi

    # Docker is required for building images in CI (localstack image build)
    if ! command -v docker >/dev/null 2>&1; then
        log "WARNING: docker not found. Run bootstrap-wsl.sh first, or the"
        log "         runner will fail jobs that build/push docker images."
    else
        log "docker present: $(docker --version)"
        # Ensure the runner user can talk to the docker daemon
        usermod -aG docker "$RUN_USER" 2>/dev/null || true
    fi
fi

# =============================================
# Step 2: Register the runner (only if a token was supplied)
# =============================================
if [ -n "$TOKEN" ]; then
    log "Registering runner '$RUNNER_NAME' with $GITLAB_URL (tags: $TAGS)..."
    gitlab-runner register \
        --non-interactive \
        --url "$GITLAB_URL" \
        --registration-token "$TOKEN" \
        --executor "$EXECUTOR" \
        --description "$RUNNER_NAME" \
        --tag-list "$TAGS" \
        --locked="false" \
        --run-untagged="false"
    log "Runner registered."
else
    log "No --token supplied; skipping registration."
    log "Register later with:"
    log "  gitlab-runner register --non-interactive --url $GITLAB_URL \\"
    log "    --registration-token <token> --executor $EXECUTOR \\"
    log "    --description '$RUNNER_NAME' --tag-list '$TAGS'"
fi

# =============================================
# Step 3: Install the runner as a service (systemd-first)
# =============================================
# Preferred: a systemd unit — it auto-starts on boot AND restarts on crash
# (equivalent to docker's "restart: unless-stopped"). WSL enables systemd via
# `[boot] systemd=true` in wsl.conf (WSL 0.67.6+).
# Fallback: gitlab-runner's own service installer + a wsl-boot hook for
# non-systemd WSL instances.

HAS_SYSTEMD=0
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    HAS_SYSTEMD=1
fi

if [ "$HAS_SYSTEMD" -eq 1 ]; then
    log "systemd detected — installing gitlab-runner as a systemd service."
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^gitlab-runner\.service'; then
        gitlab-runner install --user "$RUN_USER" --working-directory "/home/$RUN_USER" || \
            log "WARNING: gitlab-runner install failed"
    fi
    # Ensure the unit restarts on failure (unless-stopped equivalent).
    # gitlab-runner's generated unit already sets Restart=always; enforce via drop-in
    # so it survives package upgrades.
    DROPIN_DIR="/etc/systemd/system/gitlab-runner.service.d"
    mkdir -p "$DROPIN_DIR"
    cat > "$DROPIN_DIR/restart.conf" << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable gitlab-runner 2>/dev/null || log "NOTE: could not enable unit"
    systemctl restart gitlab-runner 2>/dev/null || log "NOTE: could not start unit now"
    log "systemd service enabled (auto-start on boot + Restart=always)."
else
    log "systemd NOT active in this WSL instance."
    log "Recommend enabling it: add '[boot]\\n  systemd=true' to /etc/wsl.conf,"
    log "then 'wsl --terminate <distro>' and re-run this script."
    log "Falling back to gitlab-runner service installer + wsl-boot hook."
    if ! gitlab-runner status >/dev/null 2>&1; then
        gitlab-runner install --user "$RUN_USER" --working-directory "/home/$RUN_USER" 2>/dev/null || \
            log "service install skipped (already installed or unsupported init)"
    fi
    gitlab-runner start 2>/dev/null || log "NOTE: could not start service now (will start on boot/autostart)"
fi

# =============================================
# Step 4: Optional — auto-start on WSL boot (non-systemd fallback)
# =============================================
# With systemd, enable+Restart already handle boot/crash. The wsl-boot hook is
# only needed when systemd is unavailable, but we add it harmlessly either way
# when --autostart is requested (it is a no-op if the service is already up).
if [ "$AUTOSTART" -eq 1 ]; then
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        log "--autostart: systemd already handles boot start; no wsl-boot hook needed."
    elif [ -f "$WSL_BOOT" ]; then
        HOOK_LINE="gitlab-runner start 2>/dev/null || true"
        if ! grep -qF "$HOOK_LINE" "$WSL_BOOT"; then
            log "Appending runner auto-start hook to $WSL_BOOT..."
            printf '\n# Auto-start GitLab Runner (added by install-runner.sh)\n%s\n' "$HOOK_LINE" >> "$WSL_BOOT"
            chmod +x "$WSL_BOOT"
            log "Auto-start hook added. Runner starts on every WSL boot."
        else
            log "Auto-start hook already present in $WSL_BOOT."
        fi
    else
        log "WARNING: $WSL_BOOT not found (run bootstrap-wsl.sh first)."
        log "         Auto-start hook not installed."
    fi
    log ""
    log "NOTE: wsl.conf [boot] runs on WSL *instance* start, not on Windows login."
    log "      To wake the distro automatically at Windows logon, register the"
    log "      Task Scheduler job (run from Windows PowerShell):"
    log "        scripts\\wsl\\register-autostart.ps1 -DistroName <DistroName>"
fi

# Re-lock rootfs if we unlocked it
if [ "$SKIP_INSTALL" -ne 1 ] && command -v rootfs-ro >/dev/null 2>&1; then
    log "Re-locking rootfs (rootfs-ro)..."
    rootfs-ro || log "WARNING: rootfs-ro partial failure"
fi

log ""
log "================================================"
log " GitLab Runner setup complete"
log "   name:     $RUNNER_NAME"
log "   url:      $GITLAB_URL"
log "   tags:     $TAGS"
log "   executor: $EXECUTOR"
log "   user:     $RUN_USER"
log ""
log " Verify:   gitlab-runner list"
log " Logs:     gitlab-runner --debug run   (foreground, for troubleshooting)"
log "================================================"
