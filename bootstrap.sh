#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

noStartupScript=$(echo ${@} | grep -w '\-\-noStartupScript' >> /dev/null && echo 1 || echo "")
echo "bootstrap.sh:" $@

set +e

sed="sed"
if [ $(uname -s) == "Darwin" ]; then
  sed="gsed"
else
  windows=1
fi

echo =================================
echo Bootstrap virtual machine
echo =================================

source ./.env

# get username from env or prompt
username=$VM_USERNAME
if [ -z "$VM_USERNAME" ]; then
  echo -n "> Please enter default vm user name [vagrant]:"
  read input
  username=${input:-vagrant}
  echo "VM_USERNAME=$username">> .env
fi

machine_name=${NAME:-linuxdev}
if [ -z "$NAME" ]; then
  echo -n "> Please enter the machine name [linuxdev]:"
  read input
  machine_name=${input:-linuxdev}
  echo "NAME=${machine_name}">> .env
fi

if [ -z "$CPUS" ]; then
  echo -n "> Please enter the number of cpus to assign to the VM [2]:"
  read input
  echo "CPUS=${input:-2}">> .env
fi

if [ -z "$MEMORY" ]; then
  echo -n "> Please enter the megabytes of memory [1024]:"
  read input
  echo "MEMORY=${input:-1024}">> .env
fi

if [ -z "$DOTFILES_REPO" ]; then
  echo -n "> Please enter the dotfiles repo (try https://github.com/kennyhyun/dotfiles.git if you don't have one):"
  read input
  DOTFILES_REPO=$input
  if [ "$input" ]; then
    echo "DOTFILES_REPO=${input}">> .env
  fi
fi

if [ -z "$DISK_SIZE_GB" ]; then
  echo -n "> Please enter the gigabytes of disk [64]:"
  read input
  echo "DISK_SIZE_GB=${input:-64}">> .env
fi

source ./.env

echo =================================
echo Welcome $username! Please wait a moment for bootstrapping $machine_name

if [ -z "$windows" ]; then
  # VM이 이미 생성되었는지 확인
  if [ -f "./vm/disk.qcow2" ]; then
    if [ -f "./vm/install.status" ]; then
      status=$(cat ./vm/install.status)
      case "$status" in
        "COMPLETED")
          echo "VM '$machine_name' installation completed successfully"
          echo "To start VM: ./up.sh"
          echo "To stop VM: ./halt.sh"
          exit 0
          ;;
        "INSTALLING")
          echo "VM '$machine_name' installation is in progress..."
          echo "Check status: tail -f ./vm/install.log"
          echo "To restart installation: rm -rf ./vm/ && ./bootstrap.sh"
          exit 0
          ;;
        "FAILED"|"TIMEOUT")
          echo "VM '$machine_name' installation failed or timed out"
          echo "Removing failed installation..."
          rm -rf ./vm/
          echo "Retrying installation..."
          ;;
      esac
    else
      echo "VM '$machine_name' exists but status unknown"
      echo "To start VM: ./up.sh"
      echo "To recreate VM: rm -rf ./vm/ && ./bootstrap.sh"
      exit 0
    fi
  fi
  
  # Mac - QEMU VM 생성
  echo "Creating and installing Debian 12 LTS with QEMU..."
  
  # QEMU 프로세스 실행 중 확인
  if pgrep -f "qemu-system-aarch64" > /dev/null; then
    echo "QEMU VM is already running. Please stop it first with './halt.sh'"
    exit 1
  fi
  
  if lsof -i :2222 > /dev/null 2>&1; then
    echo "Port 2222 is already in use. Please stop it manually."
    exit 1
  fi
  
  # VM 생성 및 설치
  set -e
  if ! ./scripts/qemu.create.sh "$machine_name" "${MEMORY:-2048}" "${CPUS:-2}" "${DISK_SIZE_GB:-20}" "$username"; then
    echo "VM creation failed. Check the error above."
    exit 1
  fi
  set +e
  
  echo "\n=== VM Setup Complete ==="
  echo "VM files created in: ./vm/"
  echo "To start VM: ./up.sh"
  echo "To stop VM: ./halt.sh"
  echo "SSH access: ssh -p 2222 $username@localhost (password: debian)"

else
  echo "Windows support not implemented yet"
  exit 1
fi