#!/bin/bash
# Report which host tools the build needs and which are missing.
need="make bc bison flex python3 gzip cpio git curl dtc
	aarch64-linux-gnu-gcc clang ld.lld
	debootstrap mke2fs img2simg mkbootimg lz4 tar"
missing=""
for t in $need; do
	if p=$(command -v "$t"); then
		printf '  %-22s %s\n' "$t" "$p"
	else
		printf '  %-22s MISSING\n' "$t"
		missing="$missing $t"
	fi
done
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo "  binfmt qemu-aarch64   $(sed -n 's/^interpreter //p' /proc/sys/fs/binfmt_misc/qemu-aarch64)"
else
	echo "  binfmt qemu-aarch64   MISSING"
	missing="$missing qemu-binfmt"
fi
aarch64-linux-gnu-gcc --version 2>/dev/null | head -1
echo "missing:${missing:- none}"
