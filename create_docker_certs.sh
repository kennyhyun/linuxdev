#!/bin/bash

set -e

if [ "$(uname -s)" != "Linux" ]; then
  exit -1
fi

# https://docs.docker.com/engine/security/protect-access/

local_ip_addr=192.168.99.123
common_name=$local_ip_addr

passphrase=pass:passwd

tmpdir=$(mktemp -d)
client_certs_dir=/vagrant/certs/
server_certs_dir=/var/docker/

pushd tmpdir

# generate CA private and public keys
openssl genrsa -aes256 -out ca-key.pem -passout $passphrase 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem -passin $passphrase -subj "/C=AU/ST=NSW/L=Sydney/O=Linuxdev/CN=$common_name"

# create a server key and certificate signing request
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$common_name" -sha256 -new -key server-key.pem -out server.csr

# create an extension config file
echo subjectAltName = DNS:$common_name,IP:$local_ip_addr,IP:127.0.0.1 > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

# generate the signed certificate
openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -passin $passphrase \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# create a client key and certificate signing request
openssl genrsa -out key.pem 4096
openssl req -subj '/CN=client' -new -key key.pem -out client.csr

# create a new extensions config file
echo extendedKeyUsage = clientAuth > extfile-client.cnf

# generate the signed certificate
openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -passin $passphrase \
  -CAcreateserial -out cert.pem -extfile extfile-client.cnf

# remove intermediate files
rm -v client.csr server.csr extfile.cnf extfile-client.cnf

# file mode
chmod -v 0400 ca-key.pem key.pem server-key.pem
chmod -v 0444 ca.pem server-cert.pem cert.pem

sudo mkdir -p $server_certs_dir

# copy client certs to host
rm -f ${client_certs_dir}*.pem
cp ca.pem $client_certs_dir
cp cert.pem $client_certs_dir
cp key.pem $client_certs_dir
echo Copied client certs to $client_certs_dir

# copy server certs to $server_certs_dir
sudo cp server*.pem $server_certs_dir
sudo cp ca.pem $server_certs_dir
echo Copied server certs to $server_certs_dir

popd

echo "Certificates has been generated.

<SERVER>
tlscacert: ca.pem
tlscert: server-cert.pem
tlskey: server-key.pem

<CLIENT>
tlscacert: ca.pem
tlscert: cert.pem
tlskey: key.pem

Please run config_docker_certs.sh to apply config certificates.
"
