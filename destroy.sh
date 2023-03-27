#!/bin/bash


echo ==============================
echo Destroy vagrant
echo ==============================
echo -n "> Press enter to destroy or ^C to stop"
read input

source .env

vagrant destroy

machine_name=${NAME:-linuxdev}

vagrant status

exitCode=$?

if [[ $exitCode != 0 ]];then
  echo the VM is not exists any more, removing configs
  mkdir -p backup
  mv ssh.config* backup/
  rm -rf ~/.docker/certs.$machine_name
  exit $exitCode
fi
