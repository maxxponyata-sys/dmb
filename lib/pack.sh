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
			# The bootloader overlays dtbo onto every DTB it boots, so the
			# mainline kernel needs both: one file for Odin's AP slot
			odin_tar "dmb-$DEVICE-boot-dtbo" boot.img dtbo.img
		fi
		# Everything in one AP file: the rootfs goes to the root partition
		# as a sparse, lz4-compressed image, the way Samsung ships userdata
		if [ -f "$OUT/rootfs.img" ]; then
			log "sparse + lz4 rootfs for Odin (this takes a few minutes)"
			python3 "$DMB_TOP/tools/sparse.py" pack "$OUT/rootfs.img" "$OUT/odin-src/rootfs.simg"
			lz4 -q -f -B6 --content-size "$OUT/odin-src/rootfs.simg" \
				"$OUT/odin-src/$DEVICE_ROOT_PARTLABEL.img.lz4"
			rm "$OUT/odin-src/rootfs.simg"
			local files=(boot.img "$DEVICE_ROOT_PARTLABEL.img.lz4")
			[ -f "$OUT/odin-src/dtbo.img" ] && files+=(dtbo.img)
			odin_tar "dmb-$DEVICE-full" "${files[@]}"
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
