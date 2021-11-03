#!/usr/bin/env bash

set -e

if [ $(uname -s) != "Darwin" ]; then
  echo "This script is only for Mac"
  exit -1
fi

# replace $HOME in plist and copy to ~/Library/LaunchAgents/
gsed 's+$HOME+'$HOME'+g' ./config/com.linuxdev.loginscript.plist > ~/Library/LaunchAgents/com.linuxdev.loginscript.plist

# set .startup.linuxdev.sh
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if ! [ -f "$HOME/.startup.linuxdev.sh" ];then
  echo "#!/bin/bash

export PATH=/usr/local/bin:\$PATH

cd $SCRIPT_DIR
vagrant up
" > ~/.startup.linuxdev.sh
  chmod +x ~/.startup.linuxdev.sh
fi
