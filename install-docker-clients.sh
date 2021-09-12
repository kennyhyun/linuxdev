#!/bin/bash

if [ "$(uname -s)" != "Darwin" ]; then
  exit -1;
fi

brew install docker
brew install docker-compose
