#!/bin/bash

# https://docs.docker.com/engine/security/protect-access/

local_ip_addr=192.168.99.123
common_name=$local_ip_addr

passphrase=pass:passwd

mkdir -p ~/certs
cd ~/.certs

# generate CA private and public keys
openssl genrsa -aes256 -out ca-key.pem -passout $passphrase 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem -passin $passphrase -subj "/C=AU/ST=NSW/L=Sydney/O=Linuxdev/CN=$common_name"

# create a server key and certificate signing request
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$common_name" -sha256 -new -key server-key.pem -out server.csr

# create a extensions config file
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

# copy server certs to /var/docker
sudo mkdir -p /var/docker
sudo cp server*.pem /var/docker/
sudo cp ca.pem /var/docker/
echo Copied server certs to /var/docker/

# copy client certs to host
cp ca.pem /vagrant/certs/
cp cert.pem /vagrant/certs/
cp key.pem /vagrant/certs/

echo "Certificates has been generated.

<SERVER>
tlscert: server-cert.pem
tlskey: server-key.pem

<CLIENT>
tlscacert: ca.pem
tlscert: cert.pem
tlskey: key.pem

Please run config_docker_certs.sh to apply config certificates.
"
