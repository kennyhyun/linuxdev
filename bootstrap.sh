#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

set +e

sed="sed"
if [ $(uname -s) == "Darwin" ]; then
  sed="gsed"
else
  windows=1
fi

echo =================================
echo Bootstrap vagrant machine
echo =================================

source .env

expand_disk_size=${EXPAND_DISK_GB:-4}
swapfile=${SWAPFILE:-}

# get username from env or prompt
username=$VAGRANT_USERNAME
if [ -z "$VAGRANT_USERNAME" ]; then
  echo -n "> Please enter default vagrant user name [vagrant]:"
  read input
  username=${input:-vagrant}
  echo "VAGRANT_USERNAME=$username">> .env
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

echo =================================
echo Welcome $username! Pleae wait a moment for bootstrapping $machine_name

vagrant plugin install vagrant-env
vagrant up

# create ssh config file
SSH_CONFIG="$SCRIPT_DIR/ssh.config"
if [ -z "$(grep vagrant $SSH_CONFIG)" ]; then
  vagrant ssh-config >> $SSH_CONFIG
fi

# create user with UID 1000

#### user vagrant
ssh="ssh -F $SSH_CONFIG default"
exists=$($ssh id -u $username 2>/dev/null)
vagrant_uid=$($ssh id -u vagrant 2>/dev/null)

set -e

if [ "$vagrant_uid" == "1000" ] || ([ "$exists" != "" ] && [ "$exists" != "1000" ]); then
  echo switching is required, remove $username and try again
fi
if [ -z "$vagrant_uid" ]; then
  echo ssh connection looks like failed
  exit -1;
fi
$ssh sudo cp -a /home/vagrant/.ssh /root/
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

if [ -z "$exists" ]; then
  echo "user $username not found"
  $ssh << EOSSH
echo ---------------------
echo "creating $username"
vagrant_uid=\$(id -u vagrant)
if [ \$vagrant_uid == 1000 ]; then
  pkill -U 1000
  usermod -u 1002 vagrant
  groupmod -g 1002 vagrant
fi
chown -R vagrant:vagrant /home/vagrant
useradd $username -u 1000 --create-home
if ! [ -d "/home/$username/.ssh" ]; then
  cp -a /home/vagrant/.ssh /home/$username/
  chown -R $username:$username /home/$username/.ssh
fi
grep $username /etc/passwd
EOSSH
  echo ---------------------
fi

vm_hosts_vars=$(set | grep "__VMHOSTS__[^=]\+=" | cut -c 12-)
$ssh << EOSSH
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
  cp /vagrant/config/vm.docker.disk.sh /root/docker.disk.sh && \
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

echo "==============================\nHello from $machine_name, \$(whoami)"
sudo apt remove vim -y
sudo apt update && sudo apt install \
git \
zsh \
vim-gtk \
python3-pip \
dnsutils \
pass gnupg2 \
-y

if [ -f ~/.oh-my-zsh/oh-my-zsh.sh ]; then
  echo "-----\noh my zsh is aleady installed"
else
  echo "-----\nInstalling oh my zsh...."
  wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
  sh install.sh --unattended
  rm -f install.sh*
  sudo chsh -s /bin/zsh $username
fi

if [ -f "/usr/local/bin/docker-compose" ]; then
  echo "-----\ndocker-compose aleady exists"
  docker-compose --version
else
  echo "-----\nInstalling docker-compose...."
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

mkdir -p ~/Projects
if [ -d ~/samba ]; then
  echo "-----\nSamba config is found. skipping to create"
else
  echo "-----\nConfiguring samba"
  mkdir -p samba
  cp /vagrant/config/samba/* samba/
  cd samba
  docker-compose down
  docker-compose up -d
  docker cp /etc/passwd samba:/etc/passwd
  chmod +x adduser
  ./adduser \$USER
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

if [ -d ~/.docker/certs.$machine_name ]; then
  echo "--------
~/.docker/certs.$machine_name already exists, skip creating Docker certs"
else
  echo "--------
Creating Docker certs"
  ssh $machine_name /vagrant/scripts/create_docker_certs.sh
  mkdir -p ~/.docker/certs.$machine_name
  cp $SCRIPT_DIR/certs/*.pem ~/.docker/certs.$machine_name/
  ssh $machine_name sudo /vagrant/scripts/config_docker_certs.sh
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
ssh $machine_name "bash /vagrant/scripts/download-fonts.sh \"$FONT_URLS\" \"$PATCHED_FONT_URLS\""
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

#### init dotfiles
if [ -z "$DOTFILES_REPO" ]; then
  echo "---------
DOTFILES_REPO is not defined. skipping"
else
  ssh $machine_name << EOSSH
if ! [ -d ~/dotfiles ]; then
  echo "======= Cloning dotfiles"
  git clone --recurse-submodules $DOTFILES_REPO ~/dotfiles && \
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

if [ -z "$windows" ]; then
  $SCRIPT_DIR/scripts/setup-launchd.sh
else
  mkdir -p ~/Programs
  # add Windows Terminal Profile
  powershell -executionPolicy ByPass -File $SCRIPT_DIR/add-machine-profile.ps1 $machine_name

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

- \`vagrant halt\` to shut down the VM
- \`vagrant up\` to turn on the VM
- \`./destory.sh\` to start from scratch
"
