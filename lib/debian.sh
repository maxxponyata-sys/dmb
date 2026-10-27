# dmb debian: fetch single .deb packages from the Debian archive over HTTPS,
# checked against the SHA256 in the Packages index, without root or apt.

# debian_index ARCH COMPONENT: download that Packages index once
debian_index() {
	local arch="$1" comp="$2" idx="$DMB_DL/Packages-$DEBIAN_SUITE-$2-$1"
	if [ ! -f "$idx" ]; then
		log "fetching Debian $DEBIAN_SUITE $comp package index ($arch)"
		mkdir -p "$DMB_DL"
		curl -fsSL "$DEBIAN_MIRROR/dists/$DEBIAN_SUITE/$comp/binary-$arch/Packages.xz" |
			xz -d > "$idx.part"
		mv "$idx.part" "$idx"
	fi
	echo "$idx"
}

# debian_deb PKG [ARCH] [COMPONENT]: print the path of the downloaded, verified .deb
debian_deb() {
	local pkg="$1" arch="${2:-$DEVICE_DEBIAN_ARCH}" comp="${3:-main}" idx file sha
	idx="$(debian_index "$arch" "$comp")"
	read -r file sha < <(awk -v p="$pkg" '
		/^Package: / { cur = $2 }
		cur == p && /^Filename: / { f = $2 }
		cur == p && /^SHA256: / { s = $2 }
		/^$/ && f != "" { print f, s; exit }
	' "$idx")
	[ -n "$file" ] || die "package $pkg not found in Debian $DEBIAN_SUITE"
	local out="$DMB_DL/$(basename "$file")"
	if [ ! -f "$out" ]; then
		curl -fsSL -o "$out.part" "$DEBIAN_MIRROR/$file"
		mv "$out.part" "$out"
	fi
	echo "$sha  $out" | sha256sum -c --quiet - >&2 || die "checksum mismatch: $out"
	echo "$out"
}

# debian_extract DEB DIR: unpack the data part of a .deb
debian_extract() {
	mkdir -p "$2"
	dpkg-deb -x "$1" "$2"
}
