#!/bin/bash

set -e

dotfile_repo=${DOTFILE_REPO:-git@github.com:kennyhyun/dotfiles.git}

if [[ -d "~/dotfiles" ]]; then
	echo Dotfiles exists already. Did you want to run ~/dotfiles/init.sh instead?
	exit 0
else
pushd ~
	git clone $dotfile_repo
	dotfiles/init.sh
popd
fi
