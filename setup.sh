#!/usr/bin/env bash
for param in "$@"
do
  if [ "$param" == "--no-confirm" ] ; then
    no_confirm=1
  fi
  if [ "$param" == "--no-devtools" ] ; then
    no_devtools=1
  fi
  if [ "$param" == "--no-xcode" ] ; then
    no_xcode=1
  fi
  if [ "$param" == "--no-vscode" ] ; then
    no_vscode=1
  fi
  if [ "$param" == "--no-gnused" ] ; then
    no_gnused=1
  fi
  if [ "$param" == "--no-git" ] ; then
    no_git=1
  fi
  if [ "$param" == "--no-iterm2" ] ; then
    no_iterm2=1
  fi
  if [ "$param" == "--no-virtualbox" ] ; then
    no_virtualbox=1
  fi
  if [ "$param" == "--no-vagrant" ] ; then
    no_vagrant=1
  fi
done

if [ $no_devtools ]; then
    no_xcode=1
    no_vscode=1
    no_gnused=1
    no_git=1
    no_iterm2=1
fi

if [[ $(uname -s) != 'Darwin' ]]; then
  echo This is only for Mac. Please use Porwershell and \`setup.ps1\`
  exit 1
fi

echo "=======================================
  Setting up linuxdev host apps

git, item2, vscode, virtualbox, vagrant
======================================="
if [ -z "$no_confirm" ]; then
echo -n "> Press enter to install or ^C to stop"
read input
fi

if [[ "$no_xcode" || $(xcode-select -p 1>/dev/null;echo $?) == "0" ]]; then
  echo Skip installing xcode-select
else
  xcode-select --install
fi

if brew -v ; then
  echo Skip installing brew
else
  brew_install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || exit)
  $SHELL -c "$brew_install_script"
fi

# git
if [ -z "$no_git" ]; then
brew install git
fi

# gnu-sed
if [ -z "$no_gnused" ]; then
brew install gnu-sed
fi

# iterm2
if [ -z "$no_iterm2" ]; then
brew install --cask iterm2
fi

# vscode
if [ -z "$no_vscode" ]; then
brew install --cask visual-studio-code
fi

# virtualbox
if [ -z "$no_virtualbox" ]; then
brew install --cask virtualbox
fi

# vagrant
if [ -z "$no_vagrant" ]; then
brew install --cask vagrant
fi

