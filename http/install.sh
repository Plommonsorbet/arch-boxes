#!/bin/bash

set -e
set -x

if [ -e /dev/vda ]; then
  device=/dev/vda
elif [ -e /dev/sda ]; then
  device=/dev/sda
else
  echo "ERROR: There is no disk available for installation" >&2
  exit 1
fi
export device

memory_size_in_kilobytes=$(free | awk '/^Mem:/ { print $2 }')
swap_size_in_kilobytes=$((memory_size_in_kilobytes * 2))

####
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${device}
  o # create a DOS partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +200M # 100 MB boot parttion
  n # new partition
  p # primary partition
  2 # partition number 2
    # default - start next to the partiton1
    # default - until the end of the disk
  t # change partition type
  2 # select partition 2
  8e # type Linux LVM
  w # write the partition table
  q # and we're done
EOF

boot_partition=${device}1
lvm_partition=${device}2

pvcreate ${lvm_partition}
pv_path=${lvm_partition}

vg_name=sys

vgcreate ${vg_name} ${pv_path}
vg_path=/dev/${vg_name}

lv_swap_name=swap
lv_log_name=log
lv_root_name=root

lvcreate -L 1G ${vg_name} -n ${lv_swap_name}
lvcreate -L 200M ${vg_name} -n ${lv_log_name}
lvcreate -l 100%FREE ${vg_name} -n ${lv_root_name}

lv_swap_path=${vg_path}/swap
lv_log_path=${vg_path}/log
lv_root_path=${vg_path}/root

mkswap ${lv_swap_path}

mkfs.ext4 ${lv_root_path}
mkfs.ext4 ${lv_log_path}
mkfs.ext4 ${boot_partition}

mount ${lv_root_path} /mnt
mkdir -p /mnt/var/log
mount ${lv_log_path} /mnt/var/log
mkdir /mnt/boot
mount ${boot_partition} /mnt/boot


if [ -n "${MIRROR}" ]; then
  echo "Server = ${MIRROR}" >/etc/pacman.d/mirrorlist
else
  pacman -Sy reflector --noconfirm
  reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
fi

pacstrap -M /mnt base linux grub openssh sudo polkit haveged netctl python reflector lvm2
swapon ${lv_swap_path}
genfstab -p /mnt >>/mnt/etc/fstab
swapoff ${lv_swap_path}


arch-chroot /mnt /usr/bin/sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
arch-chroot /mnt /bin/bash
