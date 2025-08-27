#!/bin/bash
# 설치 완료 대기 및 상태 업데이트 스크립트

VM_DIR="$1"
USERNAME="$2"
MAX_WAIT=1800  # 30분 최대 대기

echo "Waiting for installation to complete..." >> "$VM_DIR/install.log"

for i in $(seq 1 $MAX_WAIT); do
    # SSH 연결 테스트 (설치 완료 확인)
    if ssh -p 2222 -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$USERNAME@localhost" 'echo "Installation complete"' >> "$VM_DIR/install.log" 2>&1; then
        echo "COMPLETED" > "$VM_DIR/install.status"
        echo "$(date): Installation completed successfully" >> "$VM_DIR/install.log"
        
        # 설치 완료 후 VM 종료
        echo "system_powerdown" | socat - unix:"$VM_DIR/monitor.sock" 2>/dev/null
        
        echo "✅ Installation completed! VM has been shut down."
        echo "Use './up.sh' to start the installed VM"
        exit 0
    fi
    
    # VM이 종료되었는지 확인 (설치 실패 가능성)
    if ! pgrep -f "qemu-system-aarch64.*vm/disk.qcow2" > /dev/null; then
        echo "FAILED" > "$VM_DIR/install.status"
        echo "$(date): VM stopped unexpectedly during installation" >> "$VM_DIR/install.log"
        echo "❌ Installation failed - VM stopped unexpectedly"
        exit 1
    fi
    
    # 10초마다 체크
    sleep 10
done

# 타임아웃
echo "TIMEOUT" > "$VM_DIR/install.status"
echo "$(date): Installation timed out after 30 minutes" >> "$VM_DIR/install.log"
echo "⏰ Installation timed out. Please check manually."
exit 1