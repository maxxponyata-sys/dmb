# dmb pack: files to flash, per flash method.

# Odin takes a tar of raw partition images named after the partitions,
# with an MD5 appended to the tar (*.tar.md5)
odin_tar() {
	local name="$1"; shift
	(cd "$OUT/odin-src" && tar -H ustar -cf "$OUT/$name.tar" "$@")
	md5sum -t "$OUT/$name.tar" | sed "s|$OUT/||" >> "$OUT/$name.tar"
	mv "$OUT/$name.tar" "$OUT/$name.tar.md5"
	log "Odin AP file: $OUT/$name.tar.md5"
}

cmd_pack() {
	[ -f "$OUT/boot.img" ] || die "no boot.img; run ./dmb bootimg"
	case "$DEVICE_FLASH_METHOD" in
	odin)
		rm -rf "$OUT/odin-src"
		mkdir -p "$OUT/odin-src"
		cp "$OUT/boot.img" "$OUT/odin-src/boot.img"
		odin_tar "dmb-$DEVICE-boot" boot.img
		if [ -f "$DEVICE_DIR/dtbo.py" ]; then
			python3 "$DEVICE_DIR/dtbo.py" "$OUT/odin-src/dtbo.img"
			odin_tar "dmb-$DEVICE-empty-dtbo" dtbo.img
		fi
		rm -rf "$OUT/odin-src"
		;;
	fastboot)
		log "fastboot flash boot $OUT/boot.img"
		;;
	*)
		die "unknown flash method $DEVICE_FLASH_METHOD"
		;;
	esac
	[ -f "$OUT/rootfs.tar.gz" ] && log "rootfs: $OUT/rootfs.tar.gz (see docs/$DEVICE.md)"
	return 0
}
