#!/bin/bash

set +e

sed="sed"
windows=
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

if [ -z "$NAME" ]; then
  echo -n "> Please enter the machine name [linuxdev]:"
  read input
  echo "NAME=${input:-linuxdev}">> .env
fi

if [ -z "$CPU" ]; then
  echo -n "> Please enter the number of cpus to assign to the VM [2]:"
  read input
  echo "CPU=${input:-2}">> .env
fi

if [ -z "$MEMORY" ]; then
  echo -n "> Please enter the kilobytes of memory [1024]:"
  read input
  echo "MEMORY=${input:-1024}">> .env
fi

if [ -z "$DOTFILES_REPO" ]; then
  echo -n "> Please enter the dotfiles repo (try https://github.com/kennyhyun/dotfiles.git if you don't have one):"
  read input
  echo "DOTFILES_REPO=${input}">> .env
fi

machine_name=${NAME:-linuxdev}
echo =================================
echo Welcome $username! Pleae wait a moment for bootstrapping $machine_name

vagrant plugin install vagrant-env
vagrant up

# create ssh config file
SSH_CONFIG="./ssh.config"
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

if [ -z "$(grep root $SSH_CONFIG.root)" ]; then
  $sed -e '0,/vagrant/{s/vagrant/root/}' -e '0,/default/{s/default/root/}' $SSH_CONFIG >> $SSH_CONFIG.root
fi

#### user root
ssh="ssh -F $SSH_CONFIG.root root"

docker_port=${DOCKER_PORT:-2376}
ip_address=${IP_ADDRESS:-192.168.99.123}

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

# Adding $username to Sudoer 
$ssh << EOSSH
echo ---------------------
echo Adding $username to Sudoer 
usermod -aG sudo $username
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/98_$username
chmod 440 /etc/sudoers.d/98_$username
usermod -aG docker $username

if [ $swapfile ]; then
  echo Found SWAPFILE config
  if ! [ -f /swapfile ]; then
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

if ! [ -f /dummy ]; then
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
  cp /vagrant/vm.startup.sh /root/${machine_name}.startup.sh && \
  chmod +x /root/${machine_name}.startup.sh && \
  crontab -l | { cat; echo "@reboot /root/${machine_name}.startup.sh"; } | crontab -
else
  echo "-----
crontab scripts:"
fi
  crontab -l

EOSSH

echo ---------------------
if [ -z "$(grep $machine_name ~/.ssh/config)" ]; then
  echo Adding ssh config for $machine_name
  $sed -e "0,/vagrant/{s/vagrant/$username/}" -e "0,/default/{s/default/$machine_name/}" $SSH_CONFIG >> ~/.ssh/config
else
  echo $machine_name entry found in ~/.ssh/config. Please double check if Port is correct:
  grep $machine_name ~/.ssh/config -A10|grep Port
fi

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

if [ -f /usr/local/bin/docker-compose ]; then
  echo "-----\ndocker-compose aleady exists"
else
  echo "-----\nInstalling docker-compose...."
  docker_compose_url=https://github.com\$(wget -q -O - https://github.com/docker/compose/releases/latest | sed -n 's/.*href="\([^"]*\).*/\1/p'|grep "\$(uname -s)-\$(uname -m)$")
  echo docker_compose_url: \$docker_compose_url
  sudo wget \$docker_compose_url -O /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo pip3 install requests --upgrade
fi
docker-compose --version

echo "-----\nConfiguring samba"
mkdir -p ~/Projects
mkdir -p samba
cp /vagrant/config/samba/* samba/
cd samba
docker-compose down
docker-compose up -d
docker cp /etc/passwd samba:/etc/passwd
chmod +x adduser
./adduser \$USER

if [ -f /dummy ]; then
  filesize=\$(stat -c%s "/dummy")
  if [ "\$filesize" ] && [ "\$filesize" != "0" ]; then
    echo \$filesize was larger than 1, removing /dummy
    sudo rm /dummy
    sudo touch /dummy
  fi
fi
EOSSH

if [ -d ~/.docker/certs.$machine_name ]; then
  echo "~/.docker/certs.$machine_name already exists, skip creating Docker certs"
else
  echo "--------
Creating Docker certs"
  ssh $machine_name mv linuxdev.certs linuxdev.certs.backup || echo ""
  ssh $machine_name /vagrant/create_docker_certs.sh
  mkdir -p ~/.docker/certs.$machine_name
  cp ./certs/*.pem ~/.docker/certs.$machine_name/
  ssh $machine_name sudo /vagrant/config_docker_certs.sh
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

#### create ssh key
ssh $machine_name << EOSSH

if [ -f ~/.ssh/id_rsa ]; then
  echo "-----\nssh key aleady exists"
else
  echo "-----\nGenerating ssh key"
  ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
fi
echo "Paste the public key below into Github or else"
echo ---------------------
cat ~/.ssh/id_rsa.pub
echo ---------------------

EOSSH

mkdir -p ~/Programs
if [ "$windows" ] && ! [ -f ~/Programs/docker_env.bat ]; then
  powershell ./add-programs-to-path.ps1
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

echo "----------------------

Congrats!!!

You can now ssh into the machine by
\`\`\`
ssh $machine_name
\`\`\`

- In ssh, run \`/vagrant/init_dotfiles.sh\` to continue setting up dotfiles
    - you can override repo by \`DOTFILE_REPO=git@github.com:kennyhyun/dotfiles.git\`
- \`./destory.sh\` to start from scratch
- \`vagrant halt\` to shut down the VM
- \`vagrant up\` to turn on the VM

Don't forget to paste the ssh key above to the dotfile repo host like Github
"
