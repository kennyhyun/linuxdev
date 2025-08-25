#!/bin/bash

# QEMU 완전 자동화 VM 생성 스크립트
create_qemu_vm() {
    local vm_name="$1"
    local memory="$2"
    local cpus="$3"
    local disk_size="${4:-20}"
    local username="${5:-linuxdev}"
    
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
    
    # # ISO에서 kernel과 initrd 추출
    # local extract_dir="$vm_dir/extract"
    # if [ ! -f "$extract_dir/vmlinuz" ] || [ ! -f "$extract_dir/initrd.gz" ]; then
    #     echo "Extracting kernel and initrd from ISO..."
    #     mkdir -p "$extract_dir"
        
    #     # 7zip 설치 확인
    #     if ! command -v 7z >/dev/null 2>&1; then
    #         echo "Installing 7zip..."
    #         brew install p7zip
    #     fi
        
    #     # ISO에서 파일 추출
    #     echo "Extracting files from ISO..."
    #     7z x "$iso_path" -o"$extract_dir/iso_content" "install.a64/vmlinuz" "install.a64/initrd.gz" -y
        
    #     # 파일 이동
    #     mv "$extract_dir/iso_content/install.a64/vmlinuz" "$extract_dir/vmlinuz"
    #     mv "$extract_dir/iso_content/install.a64/initrd.gz" "$extract_dir/initrd.gz"
        
    #     # 임시 폴더 삭제
    #     rm -rf "$extract_dir/iso_content"
        
    #     echo "✅ Kernel and initrd extracted successfully"
    # fi
    
    # 사용 가능한 포트 찾기 (미리 정의)
    local http_port=8080
    while lsof -i :$http_port > /dev/null 2>&1; do
        http_port=$((http_port + 1))
    done
    
    # for Automated Install
    # Preseed 파일 생성 (완전 자동 설치)
    # HTTP 포트와 사용자명을 preseed에 삽입하기 위해 임시 변수 사용
    local preseed_late_cmd="wget -O /tmp/id_rsa.pub http://10.0.2.2:$http_port/key/id_rsa.pub && mkdir -p /target/home/$username/.ssh /target/root/.ssh && cp /tmp/id_rsa.pub /target/home/$username/.ssh/authorized_keys && cp /tmp/id_rsa.pub /target/root/.ssh/authorized_keys && chown 1000:1000 /target/home/$username/.ssh/authorized_keys && chmod 600 /target/home/$username/.ssh/authorized_keys && chmod 700 /target/home/$username/.ssh && chmod 600 /target/root/.ssh/authorized_keys && chmod 700 /target/root/.ssh && echo '$username ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/98_$username && chmod 440 /target/etc/sudoers.d/98_$username"
    
    cat > "$vm_dir/preseed.cfg" << EOF
d-i debian-installer/locale string en_AU
d-i console-setup/ask_detect boolean false
d-i console-setup/layoutcode string us
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string $vm_name
d-i netcfg/get_domain string local
d-i mirror/country string manual
d-i mirror/http/hostname string ftp.au.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i passwd/root-login boolean false
d-i passwd/user-fullname string $username
d-i passwd/username string $username
d-i passwd/user-password password debian
d-i passwd/user-password-again password debian
d-i clock-setup/utc boolean true
d-i time/zone string Australia/Sydney
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
d-i preseed/late_command string $preseed_late_cmd
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/halt boolean true
EOF
    
    
  if [ -f $vm_dir/.status ]; then
    vm_installed=$(grep INSTALL_COMPLETE $vm_dir/.status)
  fi
  if [ -z "$vm_installed" ]; then
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

    # VM 전용 키페어 생성 (설치 전에 필요)
    mkdir -p "$vm_dir/key"
    if [ ! -f "$vm_dir/key/id_rsa" ]; then
        echo "Creating VM keypair..."
        ssh-keygen -t rsa -b 2048 -f "$vm_dir/key/id_rsa" -N "" -C "$username@$vm_name"
        echo "✅ VM keypair created"
    fi
    
    # 초기 설정 스크립트 생성 (설치 전에 필요)
    if [ ! -f "$vm_dir/setup.sh" ]; then
        cat > "$vm_dir/setup.sh" << 'SETUP_EOF'
#!/bin/bash
# Setup user SSH keys
mkdir -p /target/home/REPLACE_USERNAME/.ssh
cp /target/mnt/host/vm/key/id_rsa.pub /target/home/REPLACE_USERNAME/.ssh/authorized_keys
chown 1000:1000 /target/home/REPLACE_USERNAME/.ssh/authorized_keys
chmod 600 /target/home/REPLACE_USERNAME/.ssh/authorized_keys
chmod 700 /target/home/REPLACE_USERNAME/.ssh

# Setup root SSH keys
mkdir -p /target/root/.ssh
cp /target/mnt/host/vm/key/id_rsa.pub /target/root/.ssh/authorized_keys
chown 0:0 /target/root/.ssh/authorized_keys
chmod 600 /target/root/.ssh/authorized_keys
chmod 700 /target/root/.ssh

# Setup sudoers
echo 'REPLACE_USERNAME ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/98_REPLACE_USERNAME
chmod 440 /target/etc/sudoers.d/98_REPLACE_USERNAME
SETUP_EOF
        if [[ $(uname -s) == "Darwin" ]]; then
            gsed -i "s/REPLACE_USERNAME/$username/g" "$vm_dir/setup.sh"
        else
            sed -i "s/REPLACE_USERNAME/$username/g" "$vm_dir/setup.sh"
        fi
        chmod +x "$vm_dir/setup.sh"
    fi

    # 설치용 임시 시작
    # after booting,
    # choose Advanced and Auto installation
    # and paste http://10.0.2.2:8080/preseed.cfg
    
    echo "Starting automated Debian installation..."
    echo "📋 Preseed URL: http://10.0.2.2:$http_port/preseed.cfg"
    echo "🔧 Boot options: auto=true priority=critical preseed/url=http://10.0.2.2:$http_port/preseed.cfg"
    echo "⚠️  Manual step required: Select 'Advanced options' -> 'Automated install' and enter the preseed URL above"
    
    # 설치 시작 상태 기록
    echo "INSTALLING" >> "$vm_dir/.status"
    echo "$(date) - Installation started" > "$vm_dir/install.log"
    echo "Installation started for $vm_name" >> "$vm_dir/install.log"
    
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
    
    # HTTP 서버 종료 및 설치 완료 기록
    kill $http_pid 2>/dev/null || true
    echo "✅ VM installation completed"
  fi

    # Start the VM
    echo "Starting VM..."
    ./up.sh
    
    # Wait until SSH server is ready on port 2222
    echo "Waiting for SSH server to be ready..."
    for i in {1..60}; do
        if nc -z localhost 2222 2>/dev/null; then
            echo "✅ SSH server is ready on port 2222"
            break
        fi
        if [ $i -eq 60 ]; then
            echo "❌ Timeout waiting for SSH server"
            return 1
        fi
        sleep 2
    done
    
    # 설치 완료 상태 기록
    echo "INSTALL_COMPLETE" >> "$vm_dir/.status"
    
    echo "$(date) - Installation completed" >> "$vm_dir/install.log"
    echo "Installation completed for $vm_name" >> "$vm_dir/install.log"
    
    # VM 설정 완료

    
    echo "VM created at: $vm_dir"
    echo "Installation started. User: $username, Password: debian"
    echo "SSH will be available at: ssh -p 2222 $username@localhost"
    echo "Use './up.sh' to start VM after installation"
    echo "Use './halt.sh' to stop VM"
    
    return 0
}

# ================================

set -e

# QEMU 설치 확인
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "Installing QEMU..."
    brew install qemu
fi

# GNU sed 설치 및 설정 (macOS)
if [[ $(uname -s) == "Darwin" ]]; then
    if ! command -v gsed >/dev/null 2>&1; then
        echo "Installing GNU sed..."
        brew install gnu-sed
    fi
fi

# 메인 실행
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <vm_name> <memory_mb> <cpus> [disk_size_gb] [username]"
    exit 1
fi

create_qemu_vm "$@"
