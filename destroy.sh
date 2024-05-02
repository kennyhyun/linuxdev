#!/bin/bash


echo ==============================
echo Destroy vagrant
echo ==============================
echo -n "> Press enter to destroy or ^C to stop"
read input

source .env

vagrant destroy

machine_name=${NAME:-linuxdev}

not_created=$(vagrant status | grep 'not created')


if [ -n "$not_created" ];then
  echo the VM is not exists any more, removing configs
  rm -f status
  mkdir -p backup
  mv ssh.config* backup/ 2> /dev/null
  rm -rf ~/.docker/certs.$machine_name
fi
