<!---
title: Configuring VM
date: 2021-10-15
--->

# Configuring the VM

You can create .env to customize the VM environment. Bootstrap interactively inputs the required values with some default values.

## Name

```
NAME=awesome-name
```

This will rename the machine name in VirtualBox. run `vagrant reload` to apply when updated.

## Cpus and memory

```
CPUS=4
MEMORY=8192
```

This will adjust cpus and memory, run `vagrant reload` to apply when updated.

## Expand disk size

```
EXPAND_DISK_GB=10
```

It's using 60GB of disk image but it's dynamically allocated.
It's is great in most case but when the disk space is expanded, the VM performance will be deteriorated.

This will expand the disk during bootstrap.
And you will have some slowness on the VM for a while but would not be slow while using the VM afterwhile.

This should be setup before running bootstrap.
Or you can retry after removing `/dummy`

## Docker lib disk

```
DOCKER_DISK_SIZE_GB=45
```

This creates a dedicated docker disk and mount to `/var/lib/docker`

This uses a **Fixed** size disk image for the performance, so please check the free space before setting this.
There is a startup script to check empty disk partition and format to utilise as a docker disk.
If you want to change the size, shutdown the VM and remove the image and delete existing, and change this and start the VM. Please note any data in the container **will be gone** with the previous disk image.

Please note that creating a fixed size image can take a few minutes, but maybe longer in Mac (like an hour). Please be patience.

This has no default value so it uses the dynamic sized system disk image (maximum 60GB).

If you had some data left in the system disk docker libs, you can see that by 1. stop docker, 2. unmounting /var/lib/docker, 3. start docker again. You can also delete that after unmounting if you don't need that any more. 
