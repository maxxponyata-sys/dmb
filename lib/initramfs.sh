# dmb initramfs: static busybox from Debian + initramfs/init.

cmd_initramfs() {
	local dir="$DMB_WORK/initramfs/$DEVICE" bb
	rm -rf "$dir"
	mkdir -p "$dir"/{bin,dev,etc,proc,sys,run,sysroot,tmp,var}

	bb="$(debian_deb busybox-static)"
	debian_extract "$bb" "$DMB_WORK/initramfs/busybox-$DEVICE_DEBIAN_ARCH"
	cp "$DMB_WORK/initramfs/busybox-$DEVICE_DEBIAN_ARCH/usr/bin/busybox" "$dir/bin/busybox"
	ln -s busybox "$dir/bin/sh"
	install -m755 "$DMB_TOP/initramfs/init" "$dir/init"

	cat > "$dir/etc/dmb-initramfs.conf" <<-EOF
	DEVICE="$DEVICE"
	DEVICE_NAME="$DEVICE_NAME"
	ROOT_PARTLABEL="$DEVICE_ROOT_PARTLABEL"
	USB_VID="0x1d6b"
	USB_PID="0x0104"
	EOF

	mkdir -p "$OUT"
	(cd "$dir" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9) > "$OUT/initramfs.cpio.gz"
	log "initramfs: $OUT/initramfs.cpio.gz ($(du -h "$OUT/initramfs.cpio.gz" | cut -f1))"
}
