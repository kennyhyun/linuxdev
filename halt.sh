#!/bin/bash

if [[ $(uname -s) == "Darwin" ]]; then
    # Mac - QEMU 사용
    ./scripts/qemu.halt.sh
else
    # Windows - Vagrant 사용
    vagrant halt
fi