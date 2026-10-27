#!/bin/bash
# Report which host tools the build needs and which are missing.
need="make bc bison flex perl python3 gzip xz lz4 cpio git curl patch dtc
	aarch64-linux-gnu-gcc mkbootimg mke2fs dpkg-deb apt-get tar md5sum"
missing=""
for t in $need; do
	if p=$(command -v "$t"); then
		printf '  %-22s %s\n' "$t" "$p"
	else
		printf '  %-22s MISSING\n' "$t"
		missing="$missing $t"
	fi
done
# Rootless rootfs builds use user namespaces through newuidmap/newgidmap
if [ "$(id -u)" != 0 ]; then
	for t in newuidmap newgidmap; do
		if p=$(command -v "$t"); then
			printf '  %-22s %s\n' "$t" "$p"
		else
			printf '  %-22s MISSING (package uidmap)\n' "$t"
			missing="$missing $t"
		fi
	done
fi
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo "  binfmt qemu-aarch64   $(sed -n 's/^interpreter //p' /proc/sys/fs/binfmt_misc/qemu-aarch64)"
else
	echo "  binfmt qemu-aarch64   MISSING (package qemu-user-binfmt)"
	missing="$missing qemu-binfmt"
fi
aarch64-linux-gnu-gcc --version 2>/dev/null | head -1
echo "missing:${missing:- none}"
