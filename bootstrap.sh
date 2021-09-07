#!/bin/bash

set +e

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

if [[ $vagrant_uid == 1000 || ($exists != "" && $exists != 1000) ]]; then
  echo switching is required, remove $username and try again
fi
if [[ -z "$vagrant_uid" ]]; then
  echo ssh connection looks like failed
  exit -1;
fi
$ssh sudo cp -a /home/vagrant/.ssh /root/
$ssh sudo chown -R root:root /root/.ssh

if [[ -z "$(grep root $SSH_CONFIG.root)" ]]; then
  sed -e '0,/vagrant/{s/vagrant/root/}' -e '0,/default/{s/default/root/}' $SSH_CONFIG >> $SSH_CONFIG.root
fi
#### user root
ssh="ssh -F $SSH_CONFIG.root root"


if [[ -z "$exists" ]]; then
echo "user $username not found"
  $ssh << EOSSH
echo ---------------------
echo "creating $username"
vagrant_uid=\$(id -u vagrant)
if [[ \$vagrant_uid == 1000 ]]; then
  pkill -U 1000
  usermod -u 1002 vagrant
  groupmod -g 1002 vagrant
fi
chown -R vagrant:vagrant /home/vagrant
useradd $username -u 1000 --create-home
if [ ! -d "/home/$username/.ssh" ]; then
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
  if [[ ! -f /swapfile ]]; then
    echo "-----
Creating swapfile"
    dd if=/dev/zero of=/swapfile bs=512M count=2 oflag=append conv=notrunc
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  echo "-----
Adding swapfile"
  sudo swapon /swapfile
  if [[ -z "$(grep swapfile -w /etc/fstab)" ]]; then
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
  fi
  mount -a
fi
swapon --show
free -h

if [[ ! -f /dummy ]]; then
  echo "-----
Expanding actual size for ${expand_disk_size}GB"
  #fallocate -l ${expand_disk_size}G /dummy
  dd if=/dev/zero of=/dummy bs=1G count=$expand_disk_size oflag=append conv=notrunc
fi

EOSSH

echo ---------------------
if [[ -z $(grep $machine_name ~/.ssh/config) ]]; then
  echo adding ssh config for $machine_name
  sed -e "0,/vagrant/{s/vagrant/$username/}" -e "0,/default/{s/default/$machine_name/}" $SSH_CONFIG >> ~/.ssh/config
else
  echo $machine_name entry found in ~/.ssh/config. Please double check if Port is correct:
  grep $machine_name ~/.ssh/config -A10|grep Port
fi

#### user $username
ssh $machine_name << EOSSH

echo "------------------------\nHello from $machine_name, \$(whoami)"
sudo apt remove vim -y
sudo apt update && sudo apt install \
git \
zsh \
vim-gtk \
python3-pip \
-y
wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
sh install.sh --unattended
rm -f install.sh*
sudo chsh -s /bin/zsh $username
echo "-----\nInstalling docker-compose...."
sudo apt install docker-compose -y
docker-compose --version
echo "-----\nConfiguring samba"
mkdir -p ~/Projects
mkdir -p samba
cp /vagrant/config/samba/* samba/
cd samba
docker-compose down
docker-compose up -d
docker cp /etc/passwd samba:/etc/passwd
./adduser \$USER

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

if [ -f /dummy ]; then
  filesize=\$(stat -c%s "/dummy")
  if (( filesize > 1 )); then
    echo \$filesize was larger than 1
    sudo rm /dummy
    sudo touch /dummy
  fi
fi
EOSSH

echo "
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
