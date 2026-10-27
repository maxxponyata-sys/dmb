# dmb rootfs: Debian root filesystem with mmdebstrap.
# Without root it uses user namespaces (needs newuidmap from the 'uidmap'
# package); otherwise run it as root.

rootfs_packages() {
	local p="systemd-sysv udev dbus kmod openssh-server sudo locales
		ca-certificates iproute2 iputils-ping less nano vim-tiny wget curl
		systemd-timesyncd e2fsprogs usbutils pciutils htop bash-completion
		network-manager wpasupplicant rfkill firmware-qcom-soc
		mesa-utils mesa-utils-bin libgl1-mesa-dri libegl-mesa0 mesa-vulkan-drivers
		vulkan-tools"
	case "$UI" in
	console) ;;
	phosh) p="$p phosh-full" ;;
	weston) p="$p weston" ;;
	*) die "unknown UI '$UI' (console, phosh, weston)" ;;
	esac
	echo "$p $DEVICE_PACKAGES" | tr -s ' \t\n' ','
}

mmdebstrap_bin() {
	local d="$DMB_WORK/tools/mmdebstrap"
	if [ ! -x "$d/usr/bin/mmdebstrap" ]; then
		debian_extract "$(debian_deb mmdebstrap all)" "$d"
	fi
	if [ ! -f "$DMB_WORK/tools/keyring/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
		debian_extract "$(debian_deb debian-archive-keyring all)" "$DMB_WORK/tools/keyring"
	fi
	echo "$d/usr/bin/mmdebstrap"
}

cmd_rootfs() {
	local mode tarball="$OUT/rootfs.tar" staging="$KOUT/staging" mm
	[ -d "$staging/lib/modules" ] || die "no kernel modules; run ./dmb kernel"
	if [ "$(id -u)" = 0 ]; then
		mode=root
	elif command -v newuidmap >/dev/null; then
		mode=unshare
	else
		die "rootless build needs newuidmap: sudo apt install uidmap (or run ./dmb rootfs as root)"
	fi
	mm="$(mmdebstrap_bin)"
	mkdir -p "$OUT"

	log "building Debian $DEBIAN_SUITE ($DEVICE_DEBIAN_ARCH, ui=$UI, mode=$mode)"
	DMB_TOP="$DMB_TOP" DEVICE_DIR="$DEVICE_DIR" DMB_STAGING="$staging" \
	DMB_DEVICE="$DEVICE" DMB_USER="$USERNAME" DMB_PASSWORD="$PASSWORD" \
	DMB_HOSTNAME="$HOSTNAME_" DMB_ROOT_PARTLABEL="$DEVICE_ROOT_PARTLABEL" \
	perl "$mm" \
		--mode="$mode" \
		--architectures="$DEVICE_DEBIAN_ARCH" \
		--variant=minbase \
		--components="main,contrib,non-free,non-free-firmware" \
		--keyring="$DMB_WORK/tools/keyring/usr/share/keyrings/debian-archive-keyring.gpg" \
		--include="$(rootfs_packages)" \
		--customize-hook='"$DMB_TOP/lib/hooks/rootfs-customize.sh" "$1"' \
		"$DEBIAN_SUITE" "$tarball" "$DEBIAN_MIRROR"

	log "making ext4 image from the tarball"
	rm -f "$OUT/rootfs.img"
	mke2fs -q -t ext4 -L "$DEVICE_ROOT_PARTLABEL" -d "$tarball" "$OUT/rootfs.img" "$DEVICE_ROOTFS_SIZE"
	gzip -1 -c "$tarball" > "$OUT/rootfs.tar.gz"
	log "rootfs: $OUT/rootfs.tar.gz, $OUT/rootfs.img"
}
