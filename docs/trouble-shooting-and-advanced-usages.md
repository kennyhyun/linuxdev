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

To avoid deletion of the storage attached, 

1. Shutdown the VM first with `vagrant halt`
2. dettach the disk using Virtualbox
    1. Open Oracle VM VirtualBox
![image](https://user-images.githubusercontent.com/5399854/137492415-55e4939a-e0fc-4b2c-9310-0c80cc0a4835.png)
    2. In Tools > Media, identify docker.xx.vdi in the right pane, which is used in the VM
    3. right click and click Release
![image](https://user-images.githubusercontent.com/5399854/137492552-765d1f06-52e9-4c98-b7ed-8b153c3fd7db.png)
3. destroy the VM running `./destroy.sh` in linuxdev dir
4. bootstrap.sh
5. run `sudo /root/docker.disk.sh /dev/sdb1` to attach the storage

## Want to create another VM

Clone this repo in the other directory and use different machine name during `bootstrap.sh`

You will need to manage DOCKER_xxx variables manually

## Creating machine failed

Find `%USERPROFILE%\VirualBox VMs\<machine_name>\Logs` and try to delete.
If it cannot be deleted, see the Task Manager and 

![image](https://user-images.githubusercontent.com/5399854/137558547-1dc16fcf-6484-4482-bb4b-abd27bde586e.png)

End tasks for `VirtualBox Headless Frontend` and try to remove the Logs directory and try again.
