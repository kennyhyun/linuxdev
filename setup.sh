#!/usr/bin/env bash

if [[ $(uname -s) != 'Darwin' ]]; then
  echo This is only for Mac. Please use Porwershell and `setup.ps1`
fi


if [[ $(xcode-select -p 1>/dev/null;echo $?) == "0" ]]; then
  echo Skip installing xcode-select
else
  xcode-select --install
fi

if brew -v ; then
  echo Skip installing brew
else
  /usr/bin/env bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# git
brew install git

# iterm2
brew install --cask iterm2

# vscode
brew install --cask visual-studio-code

# virtualbox
brew install --cask virtualbox

# vagrant
brew install --cask vagrant

