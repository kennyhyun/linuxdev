#!/bin/bash
PATH=/usr/sbin:/usr/bin:$PATH
set -e

add_docker_disk_to_fstab () {
	local partition=$1 # /dev/sda1 or /dev/sdc12

	if [ -z "$(grep "^$partition" /etc/fstab)" ]; then
		local partition_name=$(echo $partition|grep -o ".d.[0-9]\+$")
		mkdir -p /mnt/$partition_name
		echo "$partition /mnt/$partition_name ext4 defaults,nofail 0 2 # by linuxdev startup script" >> /etc/fstab
		echo Added $partition to /etc/fstab
		mount -a
		mkdir -p /mnt/$partition_name/var/lib/docker
		echo "/mnt/$partition_name/var/lib/docker /var/lib/docker ext4 bind,defaults,nofail 0 0 # by linuxdev startup script" >> /etc/fstab
		echo Added docker lib directory to /etc/fstab
		service docker stop
		mount -a
		service docker start
		echo Restarted docker daemon
	else
		echo $partition found on /etc/fstab. skipping to add
	fi
}

create_partition_table () {
	local disk=$1
	local size_gb=$2

	sfdisk $disk << EOF
type=83
EOF
	local partition=$(fdisk -l $disk|grep -o "$disk[0-9]\+")
	## format
	local inode_ratio=2048
	local inode_count_1000=$(echo |awk "{ print $size_gb * 1024 * 1024 / $inode_ratio }"|grep -o "[0-9]\+")
	echo "===================="
	echo Created $partition, trying to format ext4 with $inode_ratio block and ${inode_count_1000}000 inodes
	mkfs.ext4 -N ${inode_count_1000}000 -i $inode_ratio $partition
	## add/update entry to fstab if required
	echo "===================="
	echo Formatted $partition, trying to add to /etc/fstab
	add_docker_disk_to_fstab $partition
}

# find empty disk

if [ "$(uname -s)" != "Linux" ]; then
	echo "Please run this script in Linux only"
	exit -1
fi

if [ "$1" ~= "/dev/.d.[0-9]+" ]; then
	echo Adding docker disk to fstab
	add_docker_disk_to_fstab $1
	exit 0
fi

echo Trying to find an empty disk and add it for docker libs
disks=$(fdisk -l |grep -o "^Disk /dev/.d.: [0-9.]\+ GiB")

while IFS= read -r line
do
	disk=$(echo $line|grep -o /dev/.d.)
## partition
	echo "======= $line ======="
	if ! [ -z "$(sfdisk --dump $disk | grep -o "$disk[0-9]\+")" ]; then
		echo $disk has a partiton table
	else
		echo Creating partition table on $disk
		size_gb=$(echo $line|grep -o "[0-9.]\+ GiB"|grep -o "[0-9.]\+")
		create_partition_table $disk $size_gb
		break
	fi
done <<< "$disks"

