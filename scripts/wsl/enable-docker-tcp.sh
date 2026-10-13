#!/bin/bash
# enable-docker-tcp.sh -- make dockerd listen on BOTH the unix socket (for use
# inside WSL) AND tcp://127.0.0.1:2375 (so Windows docker CLI can connect).
#
# WSL2 shares localhost with Windows, so 127.0.0.1:2375 is reachable from
# Windows but NOT exposed to the network. No TLS is used because the socket is
# local-only.
#
# Run inside WSL as root:
#   sudo bash scripts/wsl/enable-docker-tcp.sh
#
# Then on Windows (admin PowerShell):
#   .\scripts\wsl\setup-docker-host.ps1
#
# Options:
#   --port <n>   TCP port (default 2375)
#   --off        revert: remove TCP listener, keep unix socket only

set -e

PORT=2375
OFF=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --off)  OFF=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then echo "Run as root: sudo bash $0 $*"; exit 1; fi
if ! command -v docker >/dev/null 2>&1; then
    echo "docker not installed. Run bootstrap-wsl.sh first."; exit 1
fi

# linuxdev rootfs is read-only; unlock /etc for the duration if the helper exists
UNLOCKED=0
if command -v rootfs-rw >/dev/null 2>&1; then rootfs-rw >/dev/null 2>&1 && UNLOCKED=1; fi

DROPIN_DIR="/etc/systemd/system/docker.service.d"
DROPIN="$DROPIN_DIR/override.conf"
DAEMON_JSON="/etc/docker/daemon.json"

relock() { [ "$UNLOCKED" -eq 1 ] && command -v rootfs-ro >/dev/null 2>&1 && rootfs-ro >/dev/null 2>&1 || true; }
trap relock EXIT

if [ "$OFF" -eq 1 ]; then
    echo "Reverting: removing TCP listener..."
    rm -f "$DROPIN"
    if [ -f "$DAEMON_JSON" ]; then
        # drop the "hosts" key if present (simple: remove file if it only had hosts)
        python3 - "$DAEMON_JSON" <<'PY' 2>/dev/null || true
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p))
except Exception:
    sys.exit(0)
d.pop("hosts",None)
json.dump(d,open(p,"w"),indent=2)
PY
    fi
    systemctl daemon-reload
    systemctl restart docker
    echo "Done. docker now listens on the unix socket only."
    exit 0
fi

echo "Configuring dockerd to listen on unix socket + tcp://127.0.0.1:$PORT ..."

# 1) daemon.json : declare both hosts (merge if file exists)
mkdir -p /etc/docker
if [ -f "$DAEMON_JSON" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$DAEMON_JSON" "$PORT" <<'PY'
import json,sys
p,port=sys.argv[1],sys.argv[2]
try: d=json.load(open(p))
except Exception: d={}
d["hosts"]=["unix:///var/run/docker.sock", f"tcp://127.0.0.1:{port}"]
json.dump(d,open(p,"w"),indent=2)
PY
else
    cat > "$DAEMON_JSON" <<EOF
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://127.0.0.1:$PORT"]
}
EOF
fi

# 2) systemd drop-in : clear the packaged "-H fd://" so it does not conflict
#    with daemon.json "hosts" (otherwise dockerd refuses to start).
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF

systemctl daemon-reload
systemctl restart docker

# 3) verify both listeners
sleep 2
echo "---------------------------------------"
if docker -H unix:///var/run/docker.sock version >/dev/null 2>&1; then
    echo "  unix socket  : OK"
else
    echo "  unix socket  : FAILED"
fi
if docker -H tcp://127.0.0.1:$PORT version >/dev/null 2>&1; then
    echo "  tcp 127.0.0.1:$PORT : OK"
else
    echo "  tcp 127.0.0.1:$PORT : FAILED (check: journalctl -u docker)"
fi
echo "---------------------------------------"
echo "Next, on Windows (admin PowerShell):"
echo "  .\\scripts\\wsl\\setup-docker-host.ps1 -Port $PORT"
