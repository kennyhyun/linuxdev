#!/bin/bash
# install-docker.sh - install Docker CE from Docker's official apt repository.
#
# Replaces the previous 'curl | bash' of a script on the dotfiles main branch,
# which made WSL installs depend on an unpinned external branch and could not
# pin the Docker version. The procedure is the same one bootstrap.sh uses for
# the Vagrant VM.
#
# Usage (as root):
#   install-docker.sh [--version <x.y.z>]
#
#   --version   Docker Engine version (prefix) to pin, e.g. 27.3.1 or 27.3.
#               Empty or omitted = latest. bootstrap-wsl.sh passes _VER_DOCKER
#               from .env (the same key the Vagrant bootstrap reads).
#
# Debian and Ubuntu only. Idempotent: does nothing when docker is already
# installed. Unlocks the read-only rootfs only if needed and re-locks it after.
# Adding the login user to the 'docker' group is done by bootstrap-wsl.sh.

set -euo pipefail

WANT_VERSION=""
UNLOCKED=0

log() { echo "[install-docker] $*"; }

# pick_version <wanted-prefix>   (stdin: 'apt-cache madison docker-ce' output)
# Prints the first full apt version whose upstream part starts with the wanted
# prefix, e.g. 27.3.1 -> 5:27.3.1-1~debian.13~trixie. Prints nothing if none.
pick_version() {
    local want="$1" esc
    esc="${want//./\\.}"
    awk -F'|' '{gsub(/ /, "", $2); print $2}' \
        | grep -m1 -E "^[0-9]+:${esc}([-~.+]|\$)" || true
}

relock() {
    if [ "$UNLOCKED" -eq 1 ]; then
        log "Re-locking rootfs (rootfs-ro)..."
        rootfs-ro >/dev/null || log "WARNING: rootfs-ro reported a problem"
    fi
}

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --version) WANT_VERSION="${2:-}"; shift $(( $# >= 2 ? 2 : 1 )) ;;
            -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
            *) echo "Unknown arg: $1" >&2; exit 2 ;;
        esac
    done

    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR: run as root (sudo bash $0)"
        exit 1
    fi

    if command -v docker >/dev/null 2>&1; then
        log "docker already installed: $(docker --version)"
        exit 0
    fi

    # Read os-release in a subshell: it defines VERSION, which we must not clobber.
    local os_id codename
    os_id="$(. /etc/os-release; echo "${ID:-}")"
    codename="$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
    case "$os_id" in
        debian|ubuntu) ;;
        *) log "ERROR: unsupported OS '${os_id:-unknown}' (Debian and Ubuntu only)"; exit 1 ;;
    esac
    [ -n "$codename" ] || { log "ERROR: cannot determine the OS codename from /etc/os-release"; exit 1; }

    # The apt/dpkg steps write to /etc, /usr and /var. Unlock only when needed.
    if [ ! -w /etc/apt/sources.list.d ] && command -v rootfs-rw >/dev/null 2>&1; then
        log "rootfs is read-only - unlocking (rootfs-rw)..."
        rootfs-rw >/dev/null && UNLOCKED=1 || log "WARNING: rootfs-rw failed; continuing"
    fi
    trap relock EXIT

    log "Installing Docker CE for $os_id/$codename (version: ${WANT_VERSION:-latest})"

    # Packages that conflict with docker-ce (remove only those that are installed).
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            log "removing conflicting package: $pkg"
            apt-get remove -y "$pkg"
        fi
    done

    apt-get update -qq
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq

    local extra="containerd.io docker-buildx-plugin docker-compose-plugin"
    if [ -n "$WANT_VERSION" ]; then
        local full
        full="$(apt-cache madison docker-ce | pick_version "$WANT_VERSION")"
        if [ -z "$full" ]; then
            log "ERROR: docker-ce version '$WANT_VERSION' not found in the repository. Available:"
            apt-cache madison docker-ce | awk -F'|' '{gsub(/ /, "", $2); print "  " $2}' | head -15
            exit 1
        fi
        log "pinning docker-ce / docker-ce-cli to $full"
        # shellcheck disable=SC2086
        apt-get install -y "docker-ce=$full" "docker-ce-cli=$full" $extra
    else
        # shellcheck disable=SC2086
        apt-get install -y docker-ce docker-ce-cli $extra
    fi

    log "installed: $(docker --version)"
}

# Run only when executed, so the helpers can be sourced for testing.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
