<!---
title: Trouble shooting and advanced usages
date: 2021-10-15
--->

# Trouble shooting and advanced usages

## Want to change the host only network IP

`192.168.99.123` is hardcoded in `Vagrantfile` so you can edit

```ruby
  config.vm.network "private_network", ip: "192.168.99.123"
```

## Want to destroy the VM but use the docker lib storage in the new VM

`vagrant destory` will remove all the VM storage attached.

1. Shutdown the VM first with `vagrant halt`
2. dettach the disk using Virtualbox
  1. Open Oracle VM VirtualBox
  2. In Tools > Media, identify docker.xx.vdi in the right pane, which is used in the VM
  3. right click and click Release
3. destroy the VM running `./destroy.sh` in linuxdev dir
4. bootstrap.sh
5. run `sudo /root/docker.disk.sh /dev/sdb1` to attach the storage
