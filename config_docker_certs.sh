#!/bin/bash

set -e

if [ "$(uname -s)" != "Linux" ]; then
  exit -1
fi

if [ "$EUID" != "0" ]; then
  echo "This script requires root access. Run this with sudo."
  exit -2
fi

docker_port=${DOCKER_PORT:-2376}

echo config_docker_certs.sh: Configuring docker server for the certificates
service docker stop

mkdir -p /etc/systemd/system/docker.service.d/
bash -c "echo \"[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --tls=true --tlscacert=/var/docker/ca.pem --tlscert=/var/docker/server-cert.pem --tlskey=/var/docker/server-key.pem -H fd:// -H tcp://0.0.0.0:$docker_port --containerd=/run/containerd/containerd.sock
\" > /etc/systemd/system/docker.service.d/override.conf"

systemctl daemon-reload

service docker start

