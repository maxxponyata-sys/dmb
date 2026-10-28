#!/usr/bin/env python3
"""Write a do-nothing dtbo.img for the Galaxy A80.

The bootloader applies an overlay from the dtbo partition to every DTB it
boots (libufdt) and refuses to boot when that fails. The stock overlays
target downstream nodes the mainline DTB does not have, so the mainline
image needs this one: one entry per stock board revision (same
msm-id/board-id, so the bootloader still finds a match), each with a
single fragment that only adds a marker property to the "soc" node. A
real fragment keeps __fixups__ in the overlay, which libufdt expects;
"soc" exists in both the stock and the mainline DTB.

It goes to the dtbo partition from recovery (Odin refuses unsigned dtbo
images). Restore the saved stock dtbo to boot Android again."""
import struct
import subprocess
import sys

MSM_ID = 0x16D           # SM7150 (sdmmagpie)
BOARD_TYPE = 0x22        # r1q
BOARD_REVS = [0x3E8, 1, 2, 3, 4, 5, 6, 7, 8]   # as in the stock dtbo.img
PAGE_SIZE = 4096         # as in the stock dtbo.img


def overlay(rev):
    src = f"""/dts-v1/;
/plugin/;
/ {{
	model = "Samsung Galaxy A80 (dmb overlay, rev {rev:#x})";
	compatible = "samsung,r1q", "qcom,sm7150";
	qcom,msm-id = <{MSM_ID:#x} 0x0>;
	qcom,board-id = <{BOARD_TYPE:#x} {rev:#x}>;

	fragment@0 {{
		target = <&soc>;

		__overlay__ {{
			dmb,dtbo-placeholder;
		}};
	}};
}};
"""
    return subprocess.run(["dtc", "-q", "-@", "-I", "dts", "-O", "dtb"],
                          input=src.encode(), capture_output=True, check=True).stdout


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: dtbo.py OUT.img")
    blobs = [overlay(r) for r in BOARD_REVS]
    hdr_size, entry_size = 32, 32
    off = hdr_size + entry_size * len(blobs)
    entries, data = b"", b""
    for blob in blobs:
        entries += struct.pack(">8I", len(blob), off + len(data), 0, 0, 0, 0, 0, 0)
        data += blob
    total = off + len(data)
    header = struct.pack(">8I", 0xD7B7AB1E, total, hdr_size, entry_size,
                         len(blobs), hdr_size, PAGE_SIZE, 0)
    with open(sys.argv[1], "wb") as f:
        f.write(header + entries + data)


if __name__ == "__main__":
    main()
