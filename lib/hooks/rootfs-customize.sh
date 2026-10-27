#!/bin/sh
# Runs inside the new root filesystem (chroot, under qemu for foreign
# arches) after mmdebstrap copied in the kernel modules and the overlay
# files. Settings come from the environment set by cmd_rootfs.
set -eu

# Copied-in files keep the builder's uid; the system should own them
chown -R root:root /usr/lib/modules /usr/local /etc/systemd
for k in /usr/lib/modules/*; do
	depmod -a "$(basename "$k")"
done
chmod 755 /usr/local/sbin/* /usr/local/bin/*

echo "$DMB_HOSTNAME" > /etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' \
	"$DMB_HOSTNAME" > /etc/hosts
printf 'PARTLABEL=%s\t/\text4\tdefaults,noatime\t0\t1\n' "$DMB_ROOT_PARTLABEL" > /etc/fstab

sed -i 's/^# *\(en_US.UTF-8\)/\1/; s/^# *\(ru_RU.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=ru_RU.UTF-8' > /etc/default/locale

groups=""
for g in sudo video render audio input plugdev netdev dialout; do
	grep -q "^$g:" /etc/group && groups="$groups,$g"
done
useradd -m -s /bin/bash -G "${groups#,}" "$DMB_USER"
echo "$DMB_USER:$DMB_PASSWORD" | chpasswd

systemctl enable dmb-usb-gadget.service serial-getty@ttyGS0.service \
	systemd-networkd.service ssh.service dmb-resize-rootfs.service
# usb0 is the only networkd link and has no carrier until a PC is plugged
# in; don't hold the boot for it
systemctl disable systemd-networkd-wait-online.service
# NetworkManager would fight networkd over usb0
mkdir -p /etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' > /etc/NetworkManager/conf.d/dmb-usb0.conf

echo "dmb $DMB_DEVICE $(date -u +%Y-%m-%d)" > /etc/dmb-release
