#!/bin/bash

set -e

if [ "$(uname -s)" != "Linux" ]; then
  exit -1
fi

docker_port=${DOCKER_PORT:-2376}

cd ~/linuxdev.certs

sudo service docker stop

sudo mkdir -p /etc/systemd/system/docker.service.d/
sudo bash -c "echo \"[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --tls=true --tlscacert=/var/docker/ca.pem --tlscert=/var/docker/server-cert.pem --tlskey=/var/docker/server-key.pem -H fd:// -H tcp://0.0.0.0:$docker_port --containerd=/run/containerd/containerd.sock
\" > /etc/systemd/system/docker.service.d/override.conf"

sudo systemctl daemon-reload

sudo service docker start

