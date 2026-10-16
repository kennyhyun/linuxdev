#!/bin/bash
# Temporarily make system directories writable for package installation
# Usage: sudo rootfs-rw.sh
# Run rootfs-ro.sh when done installing
#
# This verifies the ACTUAL mount state after each remount (via findmnt) instead
# of trusting the remount exit code, so it is idempotent: a dir that is already
# in the target state counts as success, and a remount that silently had no
# effect is reported as a failure. Both the caller's mount namespace and PID 1's
# (systemd) namespace are handled; a failure in either makes the whole run fail.

set -u

DIRS=(/usr /bin /sbin /lib /lib64 /etc /opt /srv)
TARGET=rw   # desired state for this script

# Return 0 if $1 is currently mounted $TARGET (rw/ro), else 1.
is_state() {
    local dir="$1" opts
    opts="$(findmnt -no OPTIONS --target "$dir" 2>/dev/null)" || return 1
    case ",$opts," in
        *",$TARGET,"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Remount a single dir to $TARGET and verify. Echoes status, returns 0/1.
apply_one() {
    local dir="$1"
    [ -d "$dir" ] || { echo "  $dir -> skip (missing)"; return 0; }

    if is_state "$dir"; then
        echo "  $dir -> $TARGET (already)"
        return 0
    fi

    if mountpoint -q "$dir" 2>/dev/null; then
        mount -o "remount,$TARGET,bind" "$dir" 2>/dev/null || true
    else
        # Not a bind mountpoint in this namespace: create one, then remount.
        mount --bind "$dir" "$dir" 2>/dev/null \
            && mount -o "remount,$TARGET,bind" "$dir" 2>/dev/null || true
    fi

    if is_state "$dir"; then
        echo "  $dir -> $TARGET"
        return 0
    fi
    echo "  $dir -> FAILED (still not $TARGET)"
    return 1
}

# Apply to every dir in the current namespace, aggregating failures.
apply_all() {
    local rc=0 dir
    for dir in "${DIRS[@]}"; do
        apply_one "$dir" || rc=1
    done
    return $rc
}

ns_rc=0

# On systemd WSL the wsl shell and systemd (PID 1) live in DIFFERENT mount
# namespaces. A remount here only affects the caller's namespace; package
# scripts call 'systemctl enable', which systemd executes in ITS namespace, so
# unlock that one too (otherwise: "Failed to enable unit: Read-only file system").
if [ -z "${LINUXDEV_IN_PID1_NS:-}" ] && [ -e /proc/1/ns/mnt ] \
   && [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ] \
   && command -v nsenter >/dev/null 2>&1; then
    echo "[systemd mount namespace]"
    if LINUXDEV_IN_PID1_NS=1 nsenter -t 1 -m -- bash "$(readlink -f "$0")"; then
        :
    else
        echo "WARNING: could not unlock systemd mount namespace"
        ns_rc=1
    fi
    echo "[this shell's mount namespace]"
fi

apply_all || ns_rc=1

echo ""
if [ "$ns_rc" -ne 0 ]; then
    echo "ERROR: some system dirs are NOT writable (see FAILED above)"
    exit 1
fi
echo "System dirs unlocked (rw)"
echo "Run 'sudo rootfs-ro.sh' when done installing"
