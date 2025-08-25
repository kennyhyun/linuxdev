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
        -nographic
else
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
        -vnc 127.0.0.1:1,password=off \
        -daemonize
fi