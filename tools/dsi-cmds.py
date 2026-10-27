#!/usr/bin/env python3
"""Decode the qcom,mdss-dsi-on-command / -off-command properties of a
vendor panel node (from a dtc-decompiled .dts) into readable DSI commands.

  dsi-cmds.py panel.dts

Each record is: data type, last, vc, ack, wait (ms), payload length,
payload. Use the output to write the panel's on/off functions."""
import re
import struct
import sys

KINDS = {0x05: "DCS_SHORT0", 0x15: "DCS_SHORT1", 0x39: "DCS_LONG",
         0x29: "GEN_LONG", 0x03: "GEN_SHORT0", 0x13: "GEN_SHORT1",
         0x23: "GEN_SHORT2", 0x06: "DCS_READ"}


def prop_bytes(text, prop):
    m = re.search(re.escape(prop) + r" = <([^>]*)>;", text)
    if m:
        return b"".join(struct.pack(">I", int(x, 16)) for x in m.group(1).split())
    m = re.search(re.escape(prop) + r" = \[([^\]]*)\];", text)
    if m:
        return bytes(int(x, 16) for x in m.group(1).split())
    return None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    text = open(sys.argv[1]).read()
    for prop in ("qcom,mdss-dsi-on-command", "qcom,mdss-dsi-off-command"):
        data = prop_bytes(text, prop)
        if data is None:
            continue
        print(f"== {prop}")
        i = 0
        while i + 7 <= len(data):
            dtype, _last, _vc, _ack, wait = data[i:i + 5]
            dlen = struct.unpack(">H", data[i + 5:i + 7])[0]
            payload = data[i + 7:i + 7 + dlen]
            print(f"  {KINDS.get(dtype, hex(dtype)):10s} wait={wait:3d}ms  {payload.hex(' ')}")
            i += 7 + dlen


if __name__ == "__main__":
    main()
