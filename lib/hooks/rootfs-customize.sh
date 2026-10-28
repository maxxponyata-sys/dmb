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

if [ "$DMB_UI" = xfce ]; then
	# Log straight into XFCE
	grep -q '^autologin:' /etc/group || groupadd -r autologin
	usermod -aG autologin "$DMB_USER"
	mkdir -p /etc/lightdm/lightdm.conf.d
	printf '[Seat:*]\nautologin-user=%s\nautologin-session=xfce\n' "$DMB_USER" \
		> /etc/lightdm/lightdm.conf.d/50-dmb-autologin.conf
	systemctl set-default graphical.target
	# Phone screens are dense: scale GTK 2x, matching window decorations
	x=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
	mkdir -p $x
	cat > $x/xsettings.xml <<-'EOF'
	<?xml version="1.0" encoding="UTF-8"?>
	<channel name="xsettings" version="1.0">
	  <property name="Gdk" type="empty">
	    <property name="WindowScalingFactor" type="int" value="2"/>
	  </property>
	</channel>
	EOF
	cat > $x/xfwm4.xml <<-'EOF'
	<?xml version="1.0" encoding="UTF-8"?>
	<channel name="xfwm4" version="1.0">
	  <property name="general" type="empty">
	    <property name="theme" type="string" value="Default-xhdpi"/>
	  </property>
	</channel>
	EOF
fi

echo "dmb $DMB_DEVICE $(date -u +%Y-%m-%d)" > /etc/dmb-release
