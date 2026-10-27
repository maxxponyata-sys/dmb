# dmb shared helpers. Sourced by ./dmb, never executed directly.

DMB_TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMB_WORK="${DMB_WORK:-$DMB_TOP/work}"
DMB_DL="$DMB_WORK/dl"
DMB_CONFIG="${DMB_CONFIG:-$HOME/.config/dmb.conf}"

JOBS="${JOBS:-$(nproc)}"

# Messages go to stderr so functions can return values on stdout
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Defaults every device.conf may override
device_defaults() {
	DEVICE_ARCH="aarch64"
	DEVICE_DEBIAN_ARCH="arm64"
	DEVICE_CROSS_COMPILE="aarch64-linux-gnu-"
	DEVICE_KERNEL_ARCH="arm64"
	DEVICE_KERNEL_IMAGE="Image.gz"
	DEVICE_DTB=""
	DEVICE_DTB_VARIANTS=""
	DEVICE_DTB_APPEND="true"
	DEVICE_CMDLINE=""
	DEVICE_ROOT_PARTLABEL="userdata"
	DEVICE_FLASH_METHOD="fastboot"
	DEVICE_BOOTIMG_HEADER_VERSION=0
	DEVICE_BOOTIMG_PAGESIZE=2048
	DEVICE_BOOTIMG_BASE=0x10000000
	DEVICE_BOOTIMG_KERNEL_OFFSET=0x00008000
	DEVICE_BOOTIMG_RAMDISK_OFFSET=0x01000000
	DEVICE_BOOTIMG_TAGS_OFFSET=0x00000100
	DEVICE_BOOTIMG_SECOND_OFFSET=0x00f00000
	DEVICE_BOOTIMG_BOARD=""
	DEVICE_BOOTIMG_OS_VERSION=""
	DEVICE_BOOTIMG_OS_PATCH_LEVEL=""
	DEVICE_PACKAGES=""
	DEVICE_FIRMWARE=""
	DEVICE_ROOTFS_SIZE="4G"
}

# Load ~/.config/dmb.conf, then the device and its kernel description
load_device() {
	local dev="${1:-}"
	[ -z "$dev" ] && [ -f "$DMB_CONFIG" ] && dev="$(sed -n 's/^device=//p' "$DMB_CONFIG")"
	[ -n "$dev" ] || die "no device selected; run: ./dmb init <device>"
	DEVICE="$dev"
	DEVICE_DIR="$DMB_TOP/devices/$DEVICE"
	[ -f "$DEVICE_DIR/device.conf" ] || die "unknown device '$DEVICE' (see ./dmb list)"

	device_defaults
	DEBIAN_SUITE="trixie"
	DEBIAN_MIRROR="https://deb.debian.org/debian"
	UI="console"
	USERNAME="user"
	PASSWORD="147147"
	HOSTNAME_="$DEVICE"
	# shellcheck disable=SC1090
	[ -f "$DMB_CONFIG" ] && . <(grep -E '^(DEBIAN_SUITE|DEBIAN_MIRROR|UI|USERNAME|PASSWORD|HOSTNAME_)=' "$DMB_CONFIG")
	# shellcheck disable=SC1090
	. "$DEVICE_DIR/device.conf"

	KERNEL_DIR="$DMB_TOP/kernels/$DEVICE_KERNEL"
	[ -f "$KERNEL_DIR/kernel.conf" ] || die "device $DEVICE uses unknown kernel '$DEVICE_KERNEL'"
	# shellcheck disable=SC1090
	. "$KERNEL_DIR/kernel.conf"

	KSRC="$DMB_WORK/src/$DEVICE_KERNEL-$KERNEL_TAG"
	KOUT="$DMB_WORK/kbuild/$DEVICE"
	OUT="$DMB_WORK/out/$DEVICE"
	ROOTFS="$DMB_WORK/rootfs/$DEVICE"
}

# fetch URL FILE SHA512: download once into the cache and verify
fetch() {
	local url="$1" file="$DMB_DL/$2" sha="${3:-}"
	mkdir -p "$DMB_DL"
	if [ ! -f "$file" ]; then
		log "downloading $url"
		curl -fL --retry 3 -o "$file.part" "$url"
		mv "$file.part" "$file"
	fi
	if [ -n "$sha" ]; then
		echo "$sha  $file" | sha512sum -c --quiet - || die "checksum mismatch: $file"
	fi
}
