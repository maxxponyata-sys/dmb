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
	if [ ! -d "$DMB_WORK/tools/keyring/etc/apt/trusted.gpg.d" ]; then
		debian_extract "$(debian_deb debian-archive-keyring all)" "$DMB_WORK/tools/keyring"
	fi
	# mmdebstrap checks with arch-test that qemu can run the foreign arch
	if [ ! -x "$DMB_WORK/tools/arch-test/usr/bin/arch-test" ]; then
		debian_extract "$(debian_deb arch-test all)" "$DMB_WORK/tools/arch-test"
		# Its helper path is hardcoded; point it at the unpacked copy
		sed -i "s|^HELPERS=/usr/libexec/arch-test/|HELPERS=$DMB_WORK/tools/arch-test/usr/libexec/arch-test/|" \
			"$DMB_WORK/tools/arch-test/usr/bin/arch-test"
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
	# apt checks signatures as the unprivileged _apt user, which usually
	# can't read inside a home directory: hand it a world-readable copy
	DMB_KEYRING="$(mktemp -d /tmp/dmb-keyring.XXXXXX)"
	cp "$DMB_WORK"/tools/keyring/etc/apt/trusted.gpg.d/*.asc "$DMB_KEYRING/"
	chmod 755 "$DMB_KEYRING"
	chmod 644 "$DMB_KEYRING"/*
	trap 'rm -rf "$DMB_KEYRING"' EXIT

	# In unshare mode the chroot's root can't read the home directory
	# either, so files go in through mmdebstrap's own copy hooks, which
	# run as the calling user; the customize script then runs in the chroot.
	local hooks=(
		--customize-hook='mkdir -p "$1/usr/lib/modules"'
		--customize-hook="sync-in $staging/lib/modules /usr/lib/modules"
		--customize-hook="sync-in $DMB_TOP/rootfs /"
	)
	[ -d "$DEVICE_DIR/rootfs" ] && hooks+=(--customize-hook="sync-in $DEVICE_DIR/rootfs /")
	hooks+=(
		--customize-hook="copy-in $DMB_TOP/lib/hooks/rootfs-customize.sh /tmp"
		--customize-hook='chroot "$1" sh /tmp/rootfs-customize.sh'
		--customize-hook='rm "$1/tmp/rootfs-customize.sh"'
	)

	log "building Debian $DEBIAN_SUITE ($DEVICE_DEBIAN_ARCH, ui=$UI, mode=$mode)"
	DMB_DEVICE="$DEVICE" DMB_USER="$USERNAME" DMB_PASSWORD="$PASSWORD" \
	DMB_HOSTNAME="$HOSTNAME_" DMB_ROOT_PARTLABEL="$DEVICE_ROOT_PARTLABEL" \
	PATH="$DMB_WORK/tools/arch-test/usr/bin:$PATH" \
	perl "$mm" \
		--mode="$mode" \
		--architectures="$DEVICE_DEBIAN_ARCH" \
		--variant=minbase \
		--components="main,contrib,non-free,non-free-firmware" \
		--keyring="$DMB_KEYRING" \
		--include="$(rootfs_packages)" \
		"${hooks[@]}" \
		"$DEBIAN_SUITE" "$tarball" "$DEBIAN_MIRROR"

	log "making ext4 image from the tarball"
	rm -f "$OUT/rootfs.img"
	mke2fs -q -t ext4 -L "$DEVICE_ROOT_PARTLABEL" -d "$tarball" "$OUT/rootfs.img" "$DEVICE_ROOTFS_SIZE"
	gzip -1 -c "$tarball" > "$OUT/rootfs.tar.gz"
	log "rootfs: $OUT/rootfs.tar.gz, $OUT/rootfs.img"
}
