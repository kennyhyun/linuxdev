#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/vm"

# .env 파일에서 설정 로드
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

NAME=${NAME:-linuxdev}
VM_USERNAME=${VM_USERNAME:-debian}
MONITOR_SOCK="$VM_DIR/monitor.sock"

# VM이 실행 중인지 확인
if ! pgrep -f "qemu-system-aarch64.*vm/disk.qcow2" > /dev/null; then
    echo "VM '$NAME' is not running"
    exit 0
fi

echo "Stopping VM '$NAME'..."

# Monitor 소켓으로 우아한 종료 시도
if [ -S "$MONITOR_SOCK" ]; then
    echo "Sending ACPI powerdown signal..."
    echo "system_powerdown" | socat - unix:"$MONITOR_SOCK" 2>/dev/null
    
    # 10초 대기
    echo "checking qemu-system-aarch64 pid"
    for i in {1..50}; do
        if ! pgrep -f "qemu-system-aarch64.*vm/disk.qcow2"; then
            echo "✅ VM '$NAME' stopped gracefully"
            exit 0
        fi
        sleep 1
    done
fi

# # SSH로 종료 시도
# echo "Trying SSH shutdown..."
# ssh -p 2222 -o ConnectTimeout=3 $VM_USERNAME@localhost 'sudo poweroff' 2>/dev/null

# # 10초 더 대기
# for i in {1..10}; do
#     if ! pgrep -f "qemu-system-aarch64.*vm/disk.qcow2" > /dev/null; then
#         echo "✅ VM '$NAME' stopped via SSH"
#         exit 0
#     fi
#     sleep 1
# done

# # 강제 종료
# echo "Force stopping VM '$NAME'..."
# pkill -f "qemu-system-aarch64.*vm/disk.qcow2"
# sleep 2

if ! pgrep -f "qemu-system-aarch64.*vm/disk.qcow2" > /dev/null; then
    echo "✅ VM '$NAME' force stopped"
else
    echo "❌ Failed to stop VM '$NAME'"
    exit 1
fi