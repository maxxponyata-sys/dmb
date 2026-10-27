# dmb bootimg: Android boot image from the kernel, DTB and initramfs.

cmd_bootimg() {
	local kernel="$OUT/$DEVICE_KERNEL_IMAGE" dtb="" args=()
	[ -f "$kernel" ] || die "no kernel in $OUT; run ./dmb kernel"
	[ -f "$OUT/initramfs.cpio.gz" ] || die "no initramfs; run ./dmb initramfs"

	if [ -n "$DEVICE_DTB" ]; then
		dtb="$OUT/$(basename "$DEVICE_DTB").dtb"
		[ -f "$dtb" ] || die "missing $dtb"
	fi
	if [ "$DEVICE_DTB_APPEND" = "true" ] && [ -n "$dtb" ]; then
		cat "$kernel" "$dtb" > "$OUT/kernel-dtb"
		kernel="$OUT/kernel-dtb"
	fi

	args=(
		--kernel "$kernel"
		--ramdisk "$OUT/initramfs.cpio.gz"
		--cmdline "$DEVICE_CMDLINE"
		--base "$DEVICE_BOOTIMG_BASE"
		--kernel_offset "$DEVICE_BOOTIMG_KERNEL_OFFSET"
		--ramdisk_offset "$DEVICE_BOOTIMG_RAMDISK_OFFSET"
		--tags_offset "$DEVICE_BOOTIMG_TAGS_OFFSET"
		--second_offset "$DEVICE_BOOTIMG_SECOND_OFFSET"
		--pagesize "$DEVICE_BOOTIMG_PAGESIZE"
		--header_version "$DEVICE_BOOTIMG_HEADER_VERSION"
	)
	[ -n "$DEVICE_BOOTIMG_BOARD" ] && args+=(--board "$DEVICE_BOOTIMG_BOARD")
	[ -n "$DEVICE_BOOTIMG_OS_VERSION" ] && args+=(--os_version "$DEVICE_BOOTIMG_OS_VERSION")
	[ -n "$DEVICE_BOOTIMG_OS_PATCH_LEVEL" ] && args+=(--os_patch_level "$DEVICE_BOOTIMG_OS_PATCH_LEVEL")
	# Header v2+ carries the DTB in its own section
	if [ "$DEVICE_BOOTIMG_HEADER_VERSION" -ge 2 ] && [ -n "$dtb" ] && [ "$DEVICE_DTB_APPEND" != "true" ]; then
		args+=(--dtb "$dtb")
	fi

	mkbootimg "${args[@]}" -o "$OUT/boot.img"
	log "boot.img: $OUT/boot.img ($(du -h "$OUT/boot.img" | cut -f1))"
}
