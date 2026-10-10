#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/vm"

# .env 파일에서 설정 로드
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# 기본값 설정
CPUS=${CPUS:-2}
MEMORY=${MEMORY:-2048}
NAME=${NAME:-linuxdev}

# VM 디렉토리 생성
mkdir -p "$VM_DIR"

# Monitor 소켓을 통한 VM 상태 조회
get_vm_status() {
    if [ -S "$VM_DIR/monitor.sock" ]; then
        echo "info status" | socat - UNIX-CONNECT:"$VM_DIR/monitor.sock" 2>/dev/null | grep -o "running\|paused\|stopped" || echo "unknown"
    else
        echo "no-monitor"
    fi
}

# VM 상태 출력
show_vm_status() {
    local status=$(get_vm_status)
    case $status in
        "running") echo "VM Status: Running ✅" ;;
        "paused") echo "VM Status: Paused ⏸️" ;;
        "stopped") echo "VM Status: Stopped ⏹️" ;;
        "no-monitor") echo "VM Status: Monitor not available" ;;
        *) echo "VM Status: Unknown ($status)" ;;
    esac
}

# 부팅 로그 확인
show_boot_log() {
    local log_file="$VM_DIR/console.log"
    if [ -f "$log_file" ]; then
        echo "Recent boot log (last 10 lines):"
        tail -n 10 "$log_file" | sed 's/^/  /'
    else
        echo "Boot log not available"
    fi
}

# SSH 연결 대기 함수
wait_for_ssh() {
    local max_attempts=60
    local attempt=1
    local ssh_config="$SCRIPT_DIR/../ssh.config"
    
    echo "Waiting for VM to boot and SSH to be ready..."
    echo "Monitor boot progress: tail -f vm/console.log"
    
    while [ $attempt -le $max_attempts ]; do
        # VM 상태 확인
        local vm_status=$(get_vm_status)
        
        # 10초마다 부팅 로그 표시
        if [ $((attempt % 5)) -eq 0 ]; then
            echo ""
            echo "[Attempt $attempt/$max_attempts] VM Status: $vm_status"
            show_boot_log
            echo "Continuing to wait..."
        fi
        
        if [ "$vm_status" = "running" ]; then
            # SSH 접속 가능 여부 확인
            if [ -f "$ssh_config" ]; then
                if ssh -F "$ssh_config" default pwd >/dev/null 2>&1; then
                    echo ""
                    show_vm_status
                    echo "VM is ready! SSH connection established."
                    return 0
                fi
            else
                # ssh.config가 없으면 기본 접속 시도
                if ssh -p 2222 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PasswordAuthentication=no kenny@localhost pwd >/dev/null 2>&1; then
                    echo ""
                    show_vm_status
                    echo "VM is ready! SSH connection established."
                    return 0
                fi
            fi
        elif [ "$vm_status" = "stopped" ]; then
            echo ""
            echo "ERROR: VM has stopped unexpectedly!"
            show_boot_log
            return 1
        fi
        
        printf "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo ""
    show_vm_status
    show_boot_log
    echo "Warning: VM may still be booting. SSH connection not ready after 2 minutes."
    echo "Debug commands:"
    echo "  - Check logs: tail -f vm/console.log"
    echo "  - Console access: ./up.sh --console"
    echo "  - VM status: ./status.sh"
    return 1
}

# VM이 이미 실행 중인지 확인
if pgrep -f "qemu-system-aarch64.*vm/disk.qcow2" > /dev/null; then
    echo "VM '$NAME' is already running"
    exit 0
fi

# VM 디스크 파일 존재 확인
if [ ! -f "$VM_DIR/disk.qcow2" ]; then
    echo "VM disk not found at $VM_DIR/disk.qcow2"
    echo "Please run ./bootstrap.sh first to create the VM"
    exit 1
fi


iso_filename="debian-13.0.0-arm64-netinst.iso"
iso_path="$HOME/Downloads/$iso_filename"

# 콘솔 모드 확인
if [ "$1" = "--console" ] || [ "$1" = "-c" ]; then
    # for debugging
    echo "Starting VM '$NAME' in console mode... in '$VM_DIR'"
    echo "Press Ctrl+A, X to exit console"
    qemu-system-aarch64 \
        -M virt,highmem=on,gic-version=3 \
        -accel hvf \
        -cpu host \
        -smp $CPUS \
        -m ${MEMORY}M,slots=4,maxmem=$((MEMORY * 2))M \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -drive file="$VM_DIR/disk.qcow2",format=qcow2,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -monitor unix:$VM_DIR/monitor.sock,server,nowait \
        -serial file:$VM_DIR/console.log \
        -nographic
else
    # default
    echo "Starting VM '$NAME' in headless mode... in '$VM_DIR'"
    if [ "$1" != "-q" ]; then
        echo "SSH: ssh -p 2222 kenny@localhost"
        echo "VNC: localhost:5901"
        echo "Console: ./up.sh --console"
    fi
    qemu-system-aarch64 \
        -M virt,highmem=on,gic-version=3 \
        -accel hvf \
        -cpu host \
        -smp $CPUS \
        -m ${MEMORY}M,slots=4,maxmem=$((MEMORY * 2))M \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -drive file="$VM_DIR/disk.qcow2",format=qcow2,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -monitor unix:$VM_DIR/monitor.sock,server,nowait \
        -serial file:$VM_DIR/console.log \
        -vnc 127.0.0.1:1,password=off \
        -virtfs local,path=$(cd $SCRIPT_DIR/.. && pwd),mount_tag=host,security_model=passthrough,id=host0 \
        -daemonize
    
    # VM 부팅 완료까지 대기
    show_vm_status
    show_boot_log
    wait_for_ssh
fi
