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
  echo -n "> Please enter default vm user name [admin]:"
  read input
  username=${input:-admin}
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

default_user_name=vagrant
if [ -z "$windows" ]; then
  default_user_name="admin"
fi
host_directory=/vagrant/
if [ -z "$windows" ]; then
  host_directory=/mnt/host/
fi

# create ssh config file
SSH_CONFIG="$SCRIPT_DIR/ssh.config"
if [ -z "$(grep $default_user_name $SSH_CONFIG)" ]; then
  vagrant ssh-config >> $SSH_CONFIG
fi

# create user with UID 1000

#### switch default user
ssh="ssh -F $SSH_CONFIG default"
exists=$($ssh id -u $username 2>/dev/null)
admin_uid=$($ssh id -u $default_user_name 2>/dev/null)

set -e

if [ "$admin_uid" == "1000" ] && ([ "$exists" != "" ] && [ "$exists" != "1000" ]); then
  echo switching is required, remove $username and try again
fi
if [ -z "$admin_uid" ]; then
  echo ssh connection looks like failed
  exit -1;
fi
$ssh sudo cp -a /home/$default_user_name/.ssh /root/
$ssh sudo chown -R root:root /root/.ssh

if [ -z "$(grep root $SSH_CONFIG.user)" ]; then
$sed -e '0,/vagrant/{s/vagrant/'$username'/}' -e '0,/default/{s/default/'$machine_name/'}' $SSH_CONFIG >> $SSH_CONFIG.user
fi

if [ -z "$(grep root $SSH_CONFIG.root)" ]; then
  $sed -e '0,/vagrant/{s/vagrant/root/}' -e '0,/default/{s/default/root/}' $SSH_CONFIG >> $SSH_CONFIG.root
fi

#### user root
ssh="ssh -F $SSH_CONFIG.root root"

docker_port=${DOCKER_PORT:-2376}
ip_address=${IP_ADDRESS:-192.168.99.123}
$ssh "touch ~/.hushlogin"

$ssh << EOSSH
docker -v && exit;

echo "====> Installing Docker"
docker_version=\$(grep '^_VER_DOCKER=' ${host_directory}.env |tail -1 |cut -d'=' -f2)
echo "Version: \$docker_version"

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt list -a docker-ce

if [ -z "\$docker_version" ];then
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  apt_docker_ver=\$(apt list -a docker-ce |grep -m1 \${docker_version} |cut -d' ' -f2)
  echo    "apt-get install -y docker-ce=\${apt_docker_ver} docker-ce-cli=\${apt_docker_ver} containerd.io docker-buildx-plugin docker-compose-plugin"
  apt-get install -y docker-ce=\${apt_docker_ver} docker-ce-cli=\${apt_docker_ver} containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker -v

EOSSH

if [ -z "$exists" ]; then
  echo "user $username not found"
  $ssh << EOSSH
echo ---------------------
echo "creating $username"
admin_uid=\$(id -u ${default_user_name})
if [ \$admin_uid == 1000 ]; then
  pkill -U 1000
  usermod -u 1002 ${default_user_name}
  groupmod -g 1002 ${default_user_name}
fi
chown -R ${default_user_name}:${default_user_name} /home/${default_user_name}
useradd $username -u 1000 --create-home
if ! [ -d "/home/$username/.ssh" ]; then
  cp -a /home/${default_user_name}/.ssh /home/$username/
  chown -R $username:$username /home/$username/.ssh
fi
grep $username /etc/passwd
EOSSH
  echo ---------------------
fi

vm_hosts_vars=$(set | grep "__VMHOSTS__[^=]\+=" | cut -c 12-)
$ssh << EOSSH
echo --------------------- Removing ${default_user_name} password
passwd ${default_user_name} --delete > /dev/null
echo ---------------------
echo Adding $username to Sudoer 
usermod -aG sudo $username
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/98_$username
chmod 440 /etc/sudoers.d/98_$username
usermod -aG docker $username

if [[ "\$(hostname)" =~ ^debian-[0-9]+$ ]]; then
  echo found default hostname, changing it to $machine_name
  hostname $machine_name
  echo $machine_name > /etc/hostname
  echo "127.0.0.1 $machine_name" >> /etc/hosts
fi

if [ $swapfile ]; then
  echo Found SWAPFILE config
  if ! [ -f "/swapfile" ]; then
    echo "-----
Creating swapfile"
    dd if=/dev/zero of=/swapfile bs=1M count=1024 oflag=append conv=notrunc
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  echo "-----
Adding swapfile"
  sudo swapon /swapfile
  if [ -z "\$(grep swapfile -w /etc/fstab)" ]; then
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
  fi
  mount -a
fi
swapon --show
free -h

if ! [ -f "/dummy" ]; then
  echo "-----
Expanding actual size for ${expand_disk_size}GB"
  let "blockSize = $expand_disk_size * 1024"
  #fallocate -l ${expand_disk_size}G /dummy
  echo DDing \$blockSize x 1M
  dd if=/dev/zero of=/dummy bs=1M count=\$blockSize oflag=append conv=notrunc
fi

if [ -z "\$(crontab -l|grep "${machine_name}.startup.sh")" ]; then
  echo "-----
Adding startup script to crontab"
  cp ${host_directory}config/vm.docker.disk.sh /root/docker.disk.sh && \
  chmod +x /root/docker.disk.sh && \
  echo "#!/bin/sh
/root/docker.disk.sh" > /root/${machine_name}.startup.sh && \
  chmod +x /root/${machine_name}.startup.sh && \
  crontab -l | { cat; echo "@reboot /root/${machine_name}.startup.sh"; } | crontab -
  if ! [ -z "$DOCKER_DISK_SIZE_GB" ]; then
   sdb1=\$(fdisk -l /dev/sdb|grep sdb1)
   if [ -z "\$sdb1" ]; then
     echo "Found an empty disk, make it a docker storage; /dev/sdb1, ${DOCKER_DISK_SIZE_GB}GB"
     /root/${machine_name}.startup.sh
   fi
  fi
else
  echo "-----
crontab scripts:"
fi
  crontab -l

# add hosts entry
echo "$vm_hosts_vars" | while read -r line; do
  host=\$(echo \$line | cut -d"=" -f 2)
  ip=\$(echo \$line | cut -d"=" -f 1 | cut -f1,2,3,4 -d'_' | tr _ ".")
  if [ -z "\$(grep "\$ip \$host" /etc/hosts)" ]; then
    echo "Adding \"\$ip \$host\" to hosts file"
    echo "\$ip \$host" >> /etc/hosts
  fi
done

EOSSH

$ssh "rm ~/.hushlogin"

echo ---------------------
mkdir -p ~/.ssh
touch ~/.ssh/config
if [ -z "$(grep -w "Host $machine_name" ~/.ssh/config)" ]; then
  echo Adding ssh config for $machine_name
  cat $SSH_CONFIG.user >> ~/.ssh/config
  if [ -z "$(grep -w "Host $machine_name" $HOME/.ssh/config || echo "")" ]; then
    # if $HOME is different to ~
    echo $ssh_config_for_the_machine >> $HOME/.ssh/config
  fi
else
  echo $machine_name entry found in ~/.ssh/config. Please double check if Port is correct:
  grep $machine_name ~/.ssh/config -A10|grep Port
fi

ssh $machine_name "touch ~/.hushlogin"

#### user $username
ssh $machine_name << EOSSH

echo "==============================
Hello from $machine_name, \$(whoami)"
sudo apt remove vim -y
sudo apt update && sudo apt install \
git \
zsh \
vim \
python3-pip \
tmux \
dnsutils \
pass gnupg2 \
-y

if [ "\$?" -eq 0 ]; then
if [ -f ~/.oh-my-zsh/oh-my-zsh.sh ]; then
  echo "-----
oh my zsh is aleady installed"
else
  echo "-----
Installing oh my zsh...."
  wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
  sh install.sh --unattended && \
  rm -f install.sh* && \
  sudo chsh -s /bin/zsh $username
fi
fi

if [ "\$?" -eq 0 ]; then
if [ -f "/usr/local/bin/docker-compose" ]; then
  echo "-----
docker-compose aleady exists"
  docker-compose --version
else
  echo "-----
Installing docker-compose...."
  sudo pip3 install requests --upgrade
  dc_version=\${COMPOSE_VERSION:-1.29.2}
  dc_version_url=/docker/compose/releases/download/\${dc_version}/docker-compose-\$(uname -s)-\$(uname -m)
  if [ -z "\$dc_version_url" ];then
    echo "Could not find the docker-compose url, please install manually from \$github_compose_release_url"
  else
    docker_compose_url=https://github.com\${dc_version_url}
    echo Downloading: \$docker_compose_url
    sudo wget \$docker_compose_url -O /usr/local/bin/docker-compose -q --show-progress --progress=bar:force
    sudo chmod +x /usr/local/bin/docker-compose
    docker-compose --version
  fi
fi
fi

if [ "\$?" -eq 0 ]; then
mkdir -p ~/Projects
if [ -d ~/samba ]; then
  echo "-----
Samba config is found. skipping to create"
else
  echo "-----
Configuring samba"
  mkdir -p samba
  cp ${host_directory}config/samba/* samba/
  cd samba
  docker-compose down
  docker-compose up -d
  docker cp /etc/passwd samba:/etc/passwd
  chmod +x adduser
  ./adduser \$USER
fi
fi

if [ -f "/dummy" ]; then
  filesize=\$(stat -c%s "/dummy")
  if [ "\$filesize" ] && [ "\$filesize" != "0" ]; then
    echo \$filesize was larger than 1, removing /dummy
    sudo rm /dummy
    sudo touch /dummy
  fi
fi
EOSSH

echo "Creating Docker Certs"

if [ -d ~/.docker/certs.$machine_name ]; then
  echo "--------
~/.docker/certs.$machine_name already exists, skip creating Docker certs"
else
  echo "--------
Creating Docker certs"
  ssh $machine_name ${host_directory}scripts/create_docker_certs.sh
  mkdir -p ~/.docker/certs.$machine_name
  cp $SCRIPT_DIR/certs/*.pem ~/.docker/certs.$machine_name/
  ssh $machine_name sudo ${host_directory}scripts/config_docker_certs.sh
  echo "export DOCKER_CERT_PATH=~/.docker/certs.$machine_name
export DOCKER_HOST=tcp://$ip_address:$docker_port
export DOCKER_TLS_VERIFY=1
export COMPOSE_CONVERT_WINDOWS_PATHS=1
" >> ~/.bashrc
  touch ~/.bash_profile
  if [ -z "$(grep bashrc ~/.bash_profile)" ]; then
    echo "test -f ~/.bashrc && source ~/.bashrc" >> ~/.bash_profile
  fi
fi

#### install fonts
mkdir -p $SCRIPT_DIR/data/fonts
touch $SCRIPT_DIR/data/fonts/.download_start_file
if [ "$FONT_URLS" ] || [ "$PATCHED_FONT_URLS" ]; then
echo "Installing fonts"
ssh $machine_name "bash ${host_directory}scripts/download-fonts.sh \"$FONT_URLS\" \"$PATCHED_FONT_URLS\""
downloaded=$(find $SCRIPT_DIR/data/fonts -maxdepth 1 -newer $SCRIPT_DIR/data/fonts/.download_start_file -type f -name "*.ttf")
if [ "$downloaded" ]; then
  if [ "$windows" ]; then
    while read file; do
      base=$(basename "$file")
      font_args="$font_args \"$base\""
    done <<< "$downloaded"
    powershell -executionPolicy ByPass -Command "& $(realpath --relative-to=. $SCRIPT_DIR)/scripts/install-fonts.ps1 $font_args"
  else
    mkdir -p ~/Library/Fonts
    while read file; do
      cp "$file" ~/Library/Fonts/
    done <<< "$downloaded"
  fi
fi
fi

#### TODO: upgrade docker if required

echo "Installing dotfiles"
#### init dotfiles
if [ -z "$DOTFILES_REPO" ]; then
  echo "---------
DOTFILES_REPO is not defined. skipping"
else
  ssh $machine_name << EOSSH
if ! [ -d ~/dotfiles ]; then
  echo "======= Cloning dotfiles"
  git clone $([ -n "$DOTFILES_BRANCH" ] && echo "--branch $DOTFILES_BRANCH") --recurse-submodules $DOTFILES_REPO ~/dotfiles && \
  init=\$(find dotfiles -maxdepth 1 -type f -executable -name 'init*' \
-o -type f -executable -name "bootstrap*" -o -type f -executable -name "setup*" \
-o -type f -executable -name "install*" \
|head -n 1) && \
  if [ -f "\$init" ]; then
    \$init
    if [ "\$?" -ne 0 ]; then
      echo "======= \$init has failed. Please run it in the dotfiles dir (in VM)"
    else
      echo "======= Ran \$init successfully"
    fi
  else
    echo "!!!! could not find init script. please run manually"
  fi
fi
EOSSH
fi

echo "Setting up host environments"
if [ -z "$windows" ]; then
  if [ -z "$noStartupScript" ]; then
    $SCRIPT_DIR/scripts/setup-launchd.sh
  fi
else
  mkdir -p ~/Programs
  # add Windows Terminal Profile
  if [ "$noStartupScript" ]; then
    powershell -executionPolicy ByPass -File $SCRIPT_DIR/add-machine-profile.ps1 $machine_name -noStartupScript
  else
    powershell -executionPolicy ByPass -File $SCRIPT_DIR/add-machine-profile.ps1 $machine_name
  fi

  if [ -f ~/Programs/docker_env.bat ]; then
    echo "-----
The docker environment is already set. delete ~/Programs/docker_env.bat and try again if you want to reconfigure"
  else
    echo "-----
Setting Docker Environment Variables for Windows. Please check DOCKER_HOST and related ones if you want to use other environments"
    powershell -executionPolicy ByPass -File $SCRIPT_DIR/add-programs-to-path.ps1
    echo "@echo off
set DOCKER_CERT_PATH=%userprofile%\.docker\certs.$machine_name
set DOCKER_HOST=tcp://$ip_address:$docker_port
set DOCKER_TLS_VERIFY=1
set COMPOSE_CONVERT_WINDOWS_PATHS=1
" > ~/Programs/docker_env.bat
    setx DOCKER_CERT_PATH %userprofile%\\.docker\\certs.$machine_name
    setx DOCKER_HOST tcp://$ip_address:$docker_port
    setx DOCKER_TLS_VERIFY 1
    setx COMPOSE_CONVERT_WINDOWS_PATHS 1
  fi
fi

# set env vars
vm_env_vars=$(set | grep "__VM__[A-Z_]\+=" | cut -c 7- | tr -d "'")
ssh $machine_name << EOSSH
  echo "$vm_env_vars" | while read -r line; do
    entry=\$(echo \$line)
    if [ -z "\$(grep "export \$entry" ~/.zshrc)" ]; then
      echo "Exporting env var (\$entry)"
      echo "export \$entry" >> ~/.zshrc
      echo "export \$entry" >> ~/.bashrc
    fi
  done
  if ! [ -f "\$HOME/.zshenv" ]; then
    echo "test -f ~/.zshrc && . ~/.zshrc" >> \$HOME/.zshenv
  fi
EOSSH

#### create ssh key
ssh $machine_name << EOSSH

if [ -f ~/.ssh/id_rsa ]; then
  echo "-----
ssh key aleady exists"
else
  echo "-----
Generating ssh key"
  ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
fi
echo "Paste the public key below into Github or else"
echo ---------------------
cat ~/.ssh/id_rsa.pub
echo ---------------------
rm ~/.hushlogin
EOSSH

echo "----------------------

Congrats!!!

You can now ssh into the machine by
\`\`\`
ssh $machine_name
\`\`\`

- \`./status.sh\` to check the VM status
- \`./halt.sh\` to shut down the VM
- \`./up.sh\` to turn on the VM
- \`./destory.sh\` to start from scratch
"
