#!/bin/bash

# VM 상태 확인 스크립트
check_vm_status() {
    local os_type=$(uname -s)
    
    case "$os_type" in
        "Darwin")
            check_qemu_status
            ;;
        "MINGW"*|"CYGWIN"*|"MSYS"*)
            check_vagrant_status
            ;;
        *)
            echo "❓ Unsupported OS: $os_type"
            exit 1
            ;;
    esac
}

check_qemu_status() {
    echo "🖥️  QEMU VM Status (Mac)"
    echo "========================"
    
    local vm_dir="$(pwd)/vm"
    local monitor_sock="$vm_dir/monitor.sock"
    local install_status="$vm_dir/install.status"
    
    # VM 디렉토리 확인
    if [ ! -d "$vm_dir" ]; then
        echo "❌ VM not found (no vm/ directory)"
        echo "💡 Run './scripts/qemu.create.sh' to create VM"
        return 1
    fi
    
    # 설치 상태 확인
    if [ -f "$install_status" ]; then
        local status=$(cat "$install_status")
        if [ "$status" = "INSTALLING" ]; then
            echo "⏳ VM is installing..."
            if [ -f "$vm_dir/install.log" ]; then
                echo "📝 Last log:"
                tail -3 "$vm_dir/install.log" | sed 's/^/   /'
            fi
            return 0
        fi
    fi
    
    # QEMU 프로세스 확인
    local qemu_pid=$(pgrep -f "qemu-system-aarch64.*$(basename "$vm_dir")" 2>/dev/null)
    
    if [ -n "$qemu_pid" ]; then
        echo "✅ VM is running (PID: $qemu_pid)"
        
        # SSH 연결 테스트
        if nc -z localhost 2222 2>/dev/null; then
            echo "🌐 SSH port 2222 is accessible"
        else
            echo "⚠️  SSH port 2222 not ready yet"
        fi
        
        # 메모리 사용량
        local mem_usage=$(ps -o rss= -p "$qemu_pid" 2>/dev/null | awk '{print int($1/1024)}')
        if [ -n "$mem_usage" ]; then
            echo "💾 Memory usage: ${mem_usage}MB"
        fi
        
    else
        echo "❌ VM is not running"
        
        # 디스크 이미지 확인
        if [ -f "$vm_dir/disk.qcow2" ]; then
            local disk_size=$(qemu-img info "$vm_dir/disk.qcow2" 2>/dev/null | grep "virtual size" | awk '{print $3 $4}')
            echo "💿 Disk image exists: $disk_size"
            echo "💡 Run './up.sh' to start VM"
        else
            echo "❌ No disk image found"
            echo "💡 Run './scripts/qemu.create.sh' to create VM"
        fi
    fi
}

check_vagrant_status() {
    echo "📦 Vagrant VM Status (Windows)"
    echo "=============================="
    
    # Vagrant 설치 확인
    if ! command -v vagrant >/dev/null 2>&1; then
        echo "❌ Vagrant not installed"
        echo "💡 Run 'setup.ps1' to install dependencies"
        return 1
    fi
    
    # Vagrantfile 확인
    if [ ! -f "Vagrantfile" ]; then
        echo "❌ Vagrantfile not found"
        echo "💡 Run 'bootstrap.sh' to setup VM"
        return 1
    fi
    
    # Vagrant 상태 확인
    echo "📊 Vagrant Status:"
    vagrant status 2>/dev/null | grep -E "(running|poweroff|saved|not created)" | sed 's/^/   /'
    
    # 실행 중인 VM 세부 정보
    local vm_status=$(vagrant status --machine-readable 2>/dev/null | grep ",state," | cut -d',' -f4)
    
    case "$vm_status" in
        "running")
            echo "✅ VM is running"
            
            # SSH 연결 테스트
            if vagrant ssh -c "echo 'SSH OK'" >/dev/null 2>&1; then
                echo "🌐 SSH connection is working"
            else
                echo "⚠️  SSH connection failed"
            fi
            
            # Docker 상태 확인
            local docker_status=$(vagrant ssh -c "systemctl is-active docker" 2>/dev/null | tr -d '\r')
            if [ "$docker_status" = "active" ]; then
                echo "🐳 Docker is running"
            else
                echo "⚠️  Docker is not running"
            fi
            ;;
        "poweroff")
            echo "⏹️  VM is stopped"
            echo "💡 Run 'vagrant up' to start VM"
            ;;
        "saved")
            echo "💾 VM is suspended"
            echo "💡 Run 'vagrant resume' to resume VM"
            ;;
        "not_created")
            echo "❌ VM not created"
            echo "💡 Run 'bootstrap.sh' to create VM"
            ;;
        *)
            echo "❓ Unknown VM state: $vm_status"
            ;;
    esac
    
    # VirtualBox VM 정보 (있는 경우)
    if command -v VBoxManage >/dev/null 2>&1; then
        local vbox_vm=$(VBoxManage list runningvms 2>/dev/null | grep -i linuxdev)
        if [ -n "$vbox_vm" ]; then
            echo "🖥️  VirtualBox VM running: $(echo "$vbox_vm" | cut -d'"' -f2)"
        fi
    fi
}

# 메인 실행
check_vm_status