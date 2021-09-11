#!/bin/bash

# find empty disk


disks=$(fdisk -l |grep -o "^Disk /dev/.d.: [0-9.]\+ GiB")

while IFS= read -r line
do
	echo ----- loop for $line

	disk=$(echo $line|grep -o /dev/.d.)
## partition
	echo "======= $line ======="
	if ! [ -z "$(sfdisk --dump $disk | grep -o "$disk[0-9]\+")" ]; then
		echo $disk has a partiton table
	else
		set -e # stops on any error
		echo Creating partition table on $disk
		sfdisk $disk << EOF
type=83
EOF
		partition=$(fdisk -l $disk|grep -o "$disk[0-9]\+")

## format
		size_gb=$(echo $line|grep -o "[0-9.]\+ GiB"|grep -o "[0-9.]\+")
		inode_ratio=2048
		inode_count_1000=$(echo |awk "{ print $size_gb * 1024 * 1024 / $inode_ratio }"|grep -o "[0-9]\+")
		echo "===================="
		echo Created $partition, trying to format ext4 with $inode_ratio block and ${inode_count_1000}000 inodes
		mkfs.ext4 -N ${inode_count_1000}000 -i $inode_ratio $partition

## add/update entry to fstab if required

		echo "===================="
		echo Formatted $partition, trying to add to /etc/fstab
		if [ -z "$(grep "^$partition" /etc/fstab)" ]; then
			partition_name=$(echo $partition|grep -o ".d.[0-9]\+$")
			mkdir -p /mnt/$partition_name
			echo "$partition /mnt/$partition_name ext4 defaults,nofail 0 2 # by linuxdev startup script" >> /etc/fstab
			echo Added $partition to /etc/fstab
			mount -a
			mkdir -p /mnt/$partition_name/var/lib/docker
			echo "/mnt/$partition_name/var/lib/docker /var/lib/docker ext4 bind,defaults,nofail 0 2 # by linuxdev startup script" >> /etc/fstab
			echo Added docker lib directory to /etc/fstab
			service docker stop
			mount -a
			service docker start
		else
			echo $partition found on /etc/fstab. skipping to add
		fi
		break
	fi
done <<< "$disks"

