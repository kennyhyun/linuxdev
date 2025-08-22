#!/bin/bash
set -e

# QEMU 완전 자동화 VM 생성 스크립트
create_qemu_vm() {
    local vm_name="$1"
    local memory="$2"
    local cpus="$3"
    local disk_size="${4:-20}"
    local username="${5:-debian}"
    
    echo "Creating QEMU VM: $vm_name (Debian 13 LTS)"
    echo "Memory: ${memory}MB, CPUs: $cpus, Disk: ${disk_size}GB"
    
    # Debian 13 ARM64 ISO 다운로드
    local base_url="https://cdimage.debian.org/debian-cd/current/arm64/iso-cd"
    local iso_filename="debian-13.0.0-arm64-netinst.iso"
    local iso_url="$base_url/$iso_filename"
    local sha256_url="$base_url/SHA256SUMS"
    local iso_path="$HOME/Downloads/$iso_filename"
    local sha256_path="$HOME/Downloads/SHA256SUMS"

    # ISO 파일 다운로드
    if [ ! -f "$iso_path" ]; then
        echo "Downloading Debian 13 ARM64 ISO..."
        curl -L -o "$iso_path" "$iso_url"
        
        # SHA256SUMS 다운로드
        echo "Downloading SHA256SUMS for verification..."
        curl -L -o "$sha256_path" "$sha256_url"
        
        
        # SHA256 검증
        echo "Verifying ISO integrity..."
        cd "$HOME/Downloads"
        if grep "$(basename "$iso_path")" "$sha256_path" | shasum -a 256 -c -; then
            echo "✅ ISO verification successful"
        else
            echo "❌ ISO verification failed"
            return 1
        fi
        cd - > /dev/null
    fi
    
    # VM 디스크 이미지 생성
    local vm_dir="$(pwd)/vm"
    echo "Using vm_dir: $vm_dir"
    mkdir -p "$vm_dir"
    
    # ISO에서 kernel과 initrd 추출
    local extract_dir="$vm_dir/extract"
    if [ ! -f "$extract_dir/vmlinuz" ] || [ ! -f "$extract_dir/initrd.gz" ]; then
        echo "Extracting kernel and initrd from ISO..."
        mkdir -p "$extract_dir"
        
        # 7zip 설치 확인
        if ! command -v 7z >/dev/null 2>&1; then
            echo "Installing 7zip..."
            brew install p7zip
        fi
        
        # ISO에서 파일 추출
        echo "Extracting files from ISO..."
        7z x "$iso_path" -o"$extract_dir/iso_content" "install.a64/vmlinuz" "install.a64/initrd.gz" -y
        
        # 파일 이동
        mv "$extract_dir/iso_content/install.a64/vmlinuz" "$extract_dir/vmlinuz"
        mv "$extract_dir/iso_content/install.a64/initrd.gz" "$extract_dir/initrd.gz"
        
        # 임시 폴더 삭제
        rm -rf "$extract_dir/iso_content"
        
        echo "✅ Kernel and initrd extracted successfully"
    fi
    
    # Preseed 파일 생성 (완전 자동 설치)
    cat > "$vm_dir/preseed.cfg" << EOF
d-i debian-installer/locale string en_US
d-i console-setup/ask_detect boolean false
d-i console-setup/layoutcode string us
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string $vm_name
d-i netcfg/get_domain string local
d-i mirror/country string manual
d-i mirror/http/hostname string ftp.us.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i passwd/root-login boolean false
d-i passwd/user-fullname string $username
d-i passwd/username string $username
d-i passwd/user-password password debian
d-i passwd/user-password-again password debian
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i base-installer/install-recommends boolean false
tasksel tasksel/first multiselect ssh-server
d-i pkgsel/include string openssh-server sudo curl wget git
d-i pkgsel/upgrade select none
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/halt boolean true
EOF
    
    # 사용 가능한 포트 찾기
    local http_port=8080
    while lsof -i :$http_port > /dev/null 2>&1; do
        http_port=$((http_port + 1))
    done
    echo "Using HTTP port: $http_port"
    
    # HTTP 서버로 preseed 제공
    echo "Starting HTTP server for preseed..."
    cd "$vm_dir"
    python3 -m http.server $http_port > /dev/null 2>&1 &
    local http_pid=$!
    cd - > /dev/null


    if [ ! -f "$vm_dir/disk.qcow2" ]; then
        echo "Creating VM disk image..."
        qemu-img create -f qcow2 "$vm_dir/disk.qcow2" "${disk_size}G"
    fi
    

    # 설치용 임시 시작
    # after booting,
    # choose Advanced and Auto installation
    # and paste http://10.0.2.2:8080/preseed.cfg
    
    echo "Starting automated Debian installation..."
    qemu-system-aarch64 \
        -M virt,highmem=on,gic-version=3 \
        -accel hvf \
        -cpu host \
        -smp $cpus \
        -m ${memory}M \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -drive file="$vm_dir/disk.qcow2",format=qcow2,if=virtio \
        -drive file="$iso_path",media=cdrom,readonly=on \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -monitor unix:$vm_dir/monitor.sock,server,nowait \
        -vnc 127.0.0.1:1,password=off \
        -nographic
    
    # HTTP 서버 종료
    kill $http_pid 2>/dev/null || true
    
    if [ $? -eq 0 ]; then
        echo "✅ VM started successfully in background"
        echo "📡 SSH will be available on port 2222 after installation"
        echo "⏱️  Installation takes about 10-15 minutes"
        
        # 설치 상태 파일 생성
        echo "INSTALLING" > "$vm_dir/install.status"
        echo "$(date)" > "$vm_dir/install.log"
        echo "Installation started for $vm_name" >> "$vm_dir/install.log"
        
        # 설치 완료 확인 스크립트 실행
        ./scripts/qemu.wait-install.sh "$vm_dir" "$username" &
    else
        echo "❌ Failed to start VM"
        return 1
    fi
    
    # VM 설정 완료
    
    # SSH 키 생성
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    fi
    

    
    echo "VM created at: $vm_dir"
    echo "Installation started. User: $username, Password: debian"
    echo "SSH will be available at: ssh -p 2222 $username@localhost"
    echo "Use './up.sh' to start VM after installation"
    echo "Use './halt.sh' to stop VM"
    
    return 0
}

# QEMU 설치 확인
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "Installing QEMU..."
    brew install qemu
fi

# 메인 실행
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <vm_name> <memory_mb> <cpus> [disk_size_gb] [username]"
    exit 1
fi

create_qemu_vm "$1" "$2" "$3" "$4" "$5"