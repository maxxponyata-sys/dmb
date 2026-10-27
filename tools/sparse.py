#!/usr/bin/env python3
"""Android sparse images, in place of img2simg/simg2img.

  sparse.py pack RAW SPARSE     raw image -> sparse
  sparse.py unpack SPARSE RAW   sparse -> raw (to check a packed image)

Zero blocks are stored as FILL chunks of value 0, not DONT_CARE: the
flasher then writes real zeros, so nothing left over on the partition
(old Android data) can show through in ext4 metadata that mke2fs left
zeroed, such as inode tables marked as initialised.
"""
import struct
import sys

MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE = 0xCAC1, 0xCAC2, 0xCAC3
BLK = 4096
# Keep raw chunks small enough for bootloader-side buffers
MAX_RAW_BLOCKS = 4096


def pack(src, dst):
    import os
    size = os.path.getsize(src)
    if size % BLK:
        sys.exit(f"{src}: size {size} is not a multiple of {BLK}")
    total = size // BLK
    zero = bytes(BLK)
    chunks = 0
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        fo.write(bytes(28))     # header, filled in at the end
        run_kind, run = None, []

        def flush():
            nonlocal chunks, run_kind, run
            if not run:
                return
            if run_kind == "zero":
                fo.write(struct.pack("<HHII", FILL, 0, len(run), 12 + 4))
                fo.write(struct.pack("<I", 0))
            else:
                fo.write(struct.pack("<HHII", RAW, 0, len(run), 12 + BLK * len(run)))
                for b in run:
                    fo.write(b)
            chunks += 1
            run_kind, run = None, []

        for _ in range(total):
            b = fi.read(BLK)
            kind = "zero" if b == zero else "raw"
            if kind != run_kind or (kind == "raw" and len(run) >= MAX_RAW_BLOCKS):
                flush()
                run_kind = kind
            # Zero runs only need a count
            run.append(None if kind == "zero" else b)
        flush()
        fo.seek(0)
        fo.write(struct.pack("<IHHHHIIII", MAGIC, 1, 0, 28, 12, BLK, total, chunks, 0))
    print(f"{dst}: {total} blocks in {chunks} chunks")


def unpack(src, dst):
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        magic, major, _, fhdr, chdr, blk, total, chunks, _ = struct.unpack("<IHHHHIIII", fi.read(28))
        if magic != MAGIC or major != 1:
            sys.exit(f"{src}: not an Android sparse image")
        fi.seek(fhdr)
        for _ in range(chunks):
            ctype, _, nblk, tsz = struct.unpack("<HHII", fi.read(12))
            fi.seek(chdr - 12, 1)
            if ctype == RAW:
                fo.write(fi.read(nblk * blk))
            elif ctype == FILL:
                fo.write(fi.read(4) * (blk // 4) * nblk)
            elif ctype == DONT_CARE:
                fo.seek(nblk * blk, 1)
            else:
                fi.seek(tsz - chdr, 1)      # CRC32 chunk
        fo.truncate(total * blk)


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        sys.exit(__doc__)
    (pack if sys.argv[1] == "pack" else unpack)(sys.argv[2], sys.argv[3])
