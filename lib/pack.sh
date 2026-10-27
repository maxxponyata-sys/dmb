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
	rm -f "$OUT"/*.tar.md5
	# Some bootloaders overlay the dtbo partition onto every DTB they boot;
	# devices that need it get an empty dtbo to write from recovery
	if [ -f "$DEVICE_DIR/dtbo.py" ]; then
		python3 "$DEVICE_DIR/dtbo.py" "$OUT/dtbo-empty.img"
		log "empty dtbo: $OUT/dtbo-empty.img"
	fi
	case "$DEVICE_FLASH_METHOD" in
	odin)
		# Samsung's Download mode accepts an unsigned boot.img on an unlocked
		# bootloader but refuses an unsigned dtbo ("FAIL! (Auth)"), so dtbo
		# stays out of the Odin files.
		rm -rf "$OUT/odin-src"
		mkdir -p "$OUT/odin-src"
		local v
		for v in $DEVICE_DTB_VARIANTS; do
			cp "$OUT/boot-$v.img" "$OUT/odin-src/boot.img"
			odin_tar "dmb-$DEVICE-boot-$v" boot.img
		done
		cp "$OUT/boot.img" "$OUT/odin-src/boot.img"
		odin_tar "dmb-$DEVICE-boot" boot.img
		# Everything else in one AP file: the rootfs goes to the root partition
		# as a sparse, lz4-compressed image, the way Samsung ships userdata
		if [ -f "$OUT/rootfs.img" ]; then
			log "sparse + lz4 rootfs for Odin"
			python3 "$DMB_TOP/tools/sparse.py" pack "$OUT/rootfs.img" "$OUT/odin-src/rootfs.simg"
			# Odin maps files to partitions by the file names in the PIT
			local name="${DEVICE_ODIN_ROOTFS_NAME:-$DEVICE_ROOT_PARTLABEL.img.ext4}"
			lz4 -q -f -B6 --content-size "$OUT/odin-src/rootfs.simg" "$OUT/odin-src/$name.lz4"
			rm "$OUT/odin-src/rootfs.simg"
			odin_tar "dmb-$DEVICE-install" boot.img "$name.lz4"
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
