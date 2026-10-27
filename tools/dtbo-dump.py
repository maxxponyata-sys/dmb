#!/usr/bin/env python3
"""Split an Android dtbo.img (or a DTB image with several DTBs appended) and
decompile every entry with dtc into OUTDIR/entryN.dts."""
import os
import struct
import subprocess
import sys

DTBO_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED


def split(data):
    magic = struct.unpack(">I", data[:4])[0]
    if magic == DTBO_MAGIC:
        _, _, _, esz, cnt, off = struct.unpack(">6I", data[:24])
        for i in range(cnt):
            size, o, eid, rev = struct.unpack(">4I", data[off + i * esz:off + i * esz + 16])
            yield data[o:o + size], f"id=0x{eid:x} rev=0x{rev:x}"
        return
    # Concatenated FDTs (e.g. the tail of an Image.gz-dtb)
    pos = data.find(struct.pack(">I", FDT_MAGIC))
    while pos >= 0:
        size = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        yield data[pos:pos + size], f"offset=0x{pos:x}"
        pos = data.find(struct.pack(">I", FDT_MAGIC), pos + size)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: dtbo-dump.py IMAGE OUTDIR")
    data = open(sys.argv[1], "rb").read()
    os.makedirs(sys.argv[2], exist_ok=True)
    for n, (blob, info) in enumerate(split(data)):
        dtb = os.path.join(sys.argv[2], f"entry{n}.dtb")
        dts = os.path.join(sys.argv[2], f"entry{n}.dts")
        open(dtb, "wb").write(blob)
        subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", "-o", dts, dtb], check=False)
        model = ""
        for line in open(dts, errors="replace"):
            if "model =" in line or "board-id" in line or "msm-id" in line:
                model += " " + line.strip()
        print(f"entry{n} {info}{model}")


if __name__ == "__main__":
    main()
