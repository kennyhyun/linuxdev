#!/bin/bash

echo =================================
echo Bootstrap vagrant machine
echo =================================

source .env

# get username from env or prompt
username=$VAGRANT_USERNAME
if [ -z "$VAGRANT_USERNAME" ]; then
echo -n "> Please enter default vagrant user name [vagrant]:"
read input
username=${input:-vagrant}
echo "VAGRANT_USERNAME=$username">> .env
fi

vagrant plugin install vagrant-env
vagrant up

# create ssh config file
SSH_CONFIG=./ssh.config
if [ ! -f "$SSH_CONFIG" ]; then
vagrant ssh-config >> $SSH_CONFIG
fi

# create user with UID 1000

#### user vagrant
ssh="ssh -F $SSH_CONFIG default"
exists=$($ssh id -u $username 2>/dev/null)
vagrant_uid=$($ssh id -u vagrant 2>/dev/null)
if [[ $vagrant_uid == 1000 || $exists != 1000 ]]; then
  echo switching is required, remove $username and try again
fi
$ssh sudo cp -a /home/vagrant/.ssh /root/
$ssh sudo chown -R root:root /root/.ssh

if [[ ! -f "$SSH_CONFIG.root" ]]; then
  sed -e '0,/vagrant/{s/vagrant/root/}' -e '0,/default/{s/default/root/}' $SSH_CONFIG >> $SSH_CONFIG.root
fi
#### user root
ssh="ssh -F $SSH_CONFIG.root root"

echo iexists: $exists

if [[ -z "$exists" ]]; then
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
if [ ! -d "/home/$username/.ssj" ]; then
  cp -a /home/vagrant/.ssh /home/$username/
  chown -R $username:$username /home/$username/.ssh
fi
grep $username /etc/passwd
EOSSH
fi

# Adding $username to Sudoer 
$ssh << EOSSH
echo ---------------------
echo Adding $username to Sudoer 
usermod -aG sudo $username
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/98_$username
chmod 440 /etc/sudoers.d/98_$username
EOSSH

if [[ -z $(grep linuxdev ~/.ssh/config) ]]; then
  echo adding ssh config for linuxdev
  sed -e "0,/vagrant/{s/vagrant/$username/}" -e "0,/default/{s/default/linuxdev/}" $SSH_CONFIG >> ~/.ssh/config
fi

#### user $username
ssh linuxdev << EOSSH

echo Hello $(whoami) !!!!!!!
sudo apt update && sudo apt install git zsh -y
wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
sh install.sh --unattended
rm -f install.sh*
sudo chsh -s /bin/zsh $username

EOSSH





