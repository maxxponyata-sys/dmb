#!/bin/sh
# mmdebstrap customize hook: runs as (namespaced) root with the new root
# filesystem in $1. Settings come from the environment set by cmd_rootfs.
set -eu
R="$1"

# Kernel modules
mkdir -p "$R/usr/lib/modules"
cp -a "$DMB_STAGING"/lib/modules/* "$R/usr/lib/modules/"
for k in "$R"/usr/lib/modules/*; do
	chroot "$R" depmod -a "$(basename "$k")"
done

# Common files, then device files (devices may override)
cp -a "$DMB_TOP/rootfs/." "$R/"
[ -d "$DEVICE_DIR/rootfs" ] && cp -a "$DEVICE_DIR/rootfs/." "$R/"

echo "$DMB_HOSTNAME" > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' \
	"$DMB_HOSTNAME" > "$R/etc/hosts"
printf 'PARTLABEL=%s\t/\text4\tdefaults,noatime\t0\t1\n' "$DMB_ROOT_PARTLABEL" > "$R/etc/fstab"

sed -i 's/^# *\(en_US.UTF-8\)/\1/; s/^# *\(ru_RU.UTF-8\)/\1/' "$R/etc/locale.gen"
chroot "$R" locale-gen
echo 'LANG=ru_RU.UTF-8' > "$R/etc/default/locale"

groups=""
for g in sudo video render audio input plugdev netdev dialout; do
	grep -q "^$g:" "$R/etc/group" && groups="$groups,$g"
done
chroot "$R" useradd -m -s /bin/bash -G "${groups#,}" "$DMB_USER"
echo "$DMB_USER:$DMB_PASSWORD" | chroot "$R" chpasswd

chroot "$R" systemctl enable dmb-usb-gadget.service serial-getty@ttyGS0.service \
	systemd-networkd.service ssh.service dmb-resize-rootfs.service
# NetworkManager would fight networkd over usb0
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' > "$R/etc/NetworkManager/conf.d/dmb-usb0.conf"

echo "dmb $DMB_DEVICE $(date -u +%Y-%m-%d)" > "$R/etc/dmb-release"
