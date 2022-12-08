#!/bin/sh -x

set -eux

rm -rf alpine.img

fallocate -l 1G alpine.img
sudo parted alpine.img mklabel gpt
sudo parted alpine.img mkpart boot fat32 16.8M 544M
sudo parted alpine.img set 1 boot on
sudo parted alpine.img mkpart rootfs ext4 544M 100%

dpkg -x rock-5b-rk-ubootimg_2017.09-g49da44e116d-220414_all.deb uboot
sudo dd if=uboot/usr/lib/u-boot-rock-5b/idbloader.img of=alpine.img bs=512 seek=64 conv=notrunc
sudo dd if=uboot/usr/lib/u-boot-rock-5b/u-boot.itb of=alpine.img bs=512 seek=16384 conv=notrunc

sudo losetup -f alpine.img

sudo partx -a /dev/loop0

sudo mkfs.vfat /dev/loop0p1
sudo mkfs.ext4 /dev/loop0p2
sudo tune2fs -m0 /dev/loop0p2

mkdir mnt
sudo mount /dev/loop0p2 mnt/
sudo mkdir -p mnt/boot/dtbs mnt/usr
sudo mount /dev/loop0p1 mnt/boot/

dpkg -x linux-image-5.10.110-31-rockchip-ged1406c748b1_5.10.110-31-rockchip_arm64.deb kernel
sudo cp kernel/boot/* mnt/boot
# for some weird reason, the kernel is gzipped in the deb package
zcat mnt/boot/vmlinuz-5.10.110-31-rockchip-ged1406c748b1 | sudo tee mnt/boot/vmlinuz-rockchip >/dev/null
sudo rm mnt/boot/vmlinuz-5.10.110-31-rockchip-ged1406c748b1
sudo mv mnt/boot/config-5.10.110-31-rockchip-ged1406c748b1 mnt/boot/config-rockchip
sudo mv mnt/boot/System.map-5.10.110-31-rockchip-ged1406c748b1 mnt/boot/System.map-rockchip
sudo cp -a kernel/lib mnt
sudo cp -a kernel/usr/lib mnt/usr
sudo cp -r mnt/usr/lib/linux-image-5.10.110-31-rockchip-ged1406c748b1 mnt/boot/dtbs

sudo tar -C mnt -xf alpine-minirootfs-3.17.0-aarch64.tar.gz

echo "nameserver 8.8.8.8 " | sudo tee mnt/etc/resolv.conf >/dev/null

sudo chroot mnt/ sh -c "apk update ; \
	apk add alpine-base chrony openssh-server mkinitfs sudo e2fsprogs dosfstools ; \
	mkinitfs -o /boot/initramfs-rockchip 5.10.110-31-rockchip-ged1406c748b1 ; \
	rc-update add sshd default ; \
	rc-update add chronyd default ; \
	rc-update add crond default ; \
	rc-update add klogd default ; \
	rc-update add networking default ; \
	rc-update add acpid default ; \
	rc-update add sysctl boot ; \
	rc-update add bootmisc boot ; \
	rc-update add hostname boot ; \
	rc-update add loadkmap boot ; \
	rc-update add syslog boot ; \
	rc-update add urandom boot ; \
	rc-update add machine-id boot ; \
	rc-update add modules boot ; \
	rc-update add hwclock boot ; \
	rc-update add swap boot ; \
	passwd -d root ; \
	addgroup rock ; \
	addgroup -S sudo ; \
	adduser -D -s /bin/ash -G rock rock ; \
	echo -en 'rock\nrock' | passwd rock ; \
	echo '%sudo   ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers.d/sudogroup ; \
	addgroup rock sudo ; \
	"

echo "r8125" | sudo tee -a mnt/etc/modules
echo "auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
" | sudo tee mnt/etc/network/interfaces

echo -n "rock5b" | sudo tee mnt/etc/hostname

# TODO repositories

echo "/dev/mmcblk1p2  /       ext4    relatime 0 1
/dev/mmcblk1p1  /boot   vfat    defaults        0 2
" | sudo tee mnt/etc/fstab >/dev/null

sudo mkdir mnt/boot/extlinux
echo "label Alpine 3.17
    kernel /vmlinuz-rockchip
    initrd /initramfs-rockchip
    devicetreedir /dtbs
    fdtoverlays /dtbs/rockchip/overlay/rk3588-uart7-m2.dtbo
    append root=/dev/mmcblk1p2 earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 console=tty1 consoleblank=0 loglevel=0 panic=10 rootwait rw init=/sbin/init rootfstype=ext4 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 irqchip.gicv3_pseudo_nmi=0 switolb=1 coherent_pool=2M
    " | sudo tee mnt/boot/extlinux/extlinux.conf >/dev/null

sudo umount mnt/boot mnt
sudo sync
sudo partx -d /dev/loop0p1 /dev/loop0
sudo partx -d /dev/loop0p2 /dev/loop0

sudo losetup -d /dev/loop0

sudo rm -rf kernel mnt uboot
