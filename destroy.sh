#!/bin/bash


echo ==============================
echo Destroy vagrant
echo ==============================
echo -n "> Press enter to destroy or ^C to stop"
read input

source .env

vagrant destroy

machine_name=${NAME:-linuxdev}

vagrant status $machine_name

if [[ $? != 0 ]];then
  echo machine is not exists, removing configs
  mkdir -p backup
  mv ssh.config* backup/
fi
