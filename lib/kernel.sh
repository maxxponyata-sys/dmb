# dmb kernel: fetch the kernel tree, add the device DTS, configure and build.

# Shallow clone of the pinned tag; the commit check stands in for a checksum.
kernel_fetch() {
	[ -d "$KSRC" ] && return 0
	log "cloning $DEVICE_KERNEL $KERNEL_TAG"
	rm -rf "$KSRC.tmp"
	mkdir -p "$(dirname "$KSRC")"
	git clone -q --depth 1 --branch "$KERNEL_TAG" "$KERNEL_GIT" "$KSRC.tmp"
	local head
	head="$(git -C "$KSRC.tmp" rev-parse HEAD)"
	[ "$head" = "$KERNEL_COMMIT" ] || die "$KERNEL_TAG is $head, expected $KERNEL_COMMIT"
	# A clean tree to patch: drop git metadata, keep the source
	rm -rf "$KSRC.tmp/.git"
	mv "$KSRC.tmp" "$KSRC"
}

# Device trees that are not upstream yet live in devices/<dev>/dts and are
# copied into the kernel tree on every build, so edits are picked up.
kernel_add_dts() {
	local dtsdir="$KSRC/arch/$DEVICE_KERNEL_ARCH/boot/dts/$KERNEL_DTS_SUBDIR" f name
	[ -d "$DEVICE_DIR/dts" ] || return 0
	for f in "$DEVICE_DIR"/dts/*.dts "$DEVICE_DIR"/dts/*.dtsi; do
		[ -e "$f" ] || continue
		cp "$f" "$dtsdir/"
		name="$(basename "$f")"
		case "$name" in
		*.dts)
			grep -q "${name%.dts}.dtb" "$dtsdir/Makefile" ||
				echo "dtb-\$(CONFIG_ARCH_QCOM) += ${name%.dts}.dtb" >> "$dtsdir/Makefile"
			# Keep labels in /__symbols__: bootloaders that apply a dtbo
			# overlay (Qualcomm ABL via libufdt) refuse a base DTB without it
			grep -q "DTC_FLAGS_${name%.dts} " "$dtsdir/Makefile" ||
				echo "DTC_FLAGS_${name%.dts} := -@" >> "$dtsdir/Makefile"
			;;
		esac
	done
}

# Drivers that are not upstream yet: devices/<dev>/kernel/ is copied over
# the tree on every build, and patches from kernels/<k>/patches and
# devices/<dev>/patches are applied once each (stamp files in the tree).
kernel_add_files() {
	if [ -d "$DEVICE_DIR/kernel" ]; then
		cp -r "$DEVICE_DIR/kernel/." "$KSRC/"
	fi
	local p stamp
	for p in "$KERNEL_DIR"/patches/*.patch "$DEVICE_DIR"/patches/*.patch; do
		[ -e "$p" ] || continue
		stamp="$KSRC/.dmb-applied-$(basename "$p")"
		[ -f "$stamp" ] && continue
		log "applying $(basename "$p")"
		patch -d "$KSRC" -p1 --forward --quiet < "$p" || die "patch failed: $p"
		touch "$stamp"
	done
}

kernel_make() {
	make -C "$KSRC" O="$KOUT" ARCH="$DEVICE_KERNEL_ARCH" \
		CROSS_COMPILE="$DEVICE_CROSS_COMPILE" -j"$JOBS" \
		KBUILD_BUILD_USER=dmb KBUILD_BUILD_HOST="$DEVICE" "$@"
}

kernel_config() {
	mkdir -p "$KOUT"
	cp "$KERNEL_DIR/$KERNEL_CONFIG" "$KOUT/.config"
	# The dmb initramfs and Debian userspace need a few things on top of
	# the base config; devices can add their own fragment.
	cat "$DMB_TOP/kernels/dmb.fragment" >> "$KOUT/.config"
	[ -f "$DEVICE_DIR/kernel.fragment" ] && cat "$DEVICE_DIR/kernel.fragment" >> "$KOUT/.config"
	kernel_make olddefconfig
}

cmd_kernel() {
	kernel_fetch
	kernel_add_files
	kernel_add_dts
	kernel_config
	log "building $DEVICE_KERNEL_IMAGE, dtbs and modules ($JOBS jobs)"
	kernel_make "$DEVICE_KERNEL_IMAGE" dtbs modules

	local staging="$KOUT/staging"
	rm -rf "$staging"
	kernel_make INSTALL_MOD_PATH="$staging" INSTALL_MOD_STRIP=1 modules_install
	rm -f "$staging"/lib/modules/*/build "$staging"/lib/modules/*/source
	KREL="$(cat "$KOUT/include/config/kernel.release")"
	mkdir -p "$OUT"
	cp "$KOUT/arch/$DEVICE_KERNEL_ARCH/boot/$DEVICE_KERNEL_IMAGE" "$OUT/"
	cp "$KOUT/.config" "$OUT/config-$KREL"
	if [ -n "$DEVICE_DTB" ]; then
		local v
		for v in "" $DEVICE_DTB_VARIANTS; do
			cp "$KOUT/arch/$DEVICE_KERNEL_ARCH/boot/dts/$DEVICE_DTB${v:+-$v}.dtb" "$OUT/"
		done
	fi
	log "kernel $KREL ready in $OUT"
}
