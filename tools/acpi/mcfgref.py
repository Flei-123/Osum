#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct
import sys

HEADER_BYTES = 36
FIRST_ENTRY = 44
ENTRY_BYTES = 16
BUS_SHIFT = 20
ALIGN_MASK = (1 << BUS_SHIFT) - 1
ADDRESS_LIMIT = 1 << 64


def parse(data: bytes) -> dict:
    length = struct.unpack_from("<I", data, 4)[0]
    count = max(0, (length - FIRST_ENTRY) // ENTRY_BYTES)
    entries = []
    for i in range(count):
        base, segment, first, last = struct.unpack_from(
            "<QHBB", data, FIRST_ENTRY + i * ENTRY_BYTES)
        span = (last - first + 1) << BUS_SHIFT
        usable = (base != 0 and base & ALIGN_MASK == 0 and last >= first
                  and base + span < ADDRESS_LIMIT)
        entries.append((base, segment, first, last, usable))
    return {"length": length, "entries": entries}


def lines(data: bytes, signature: str) -> list:
    table = parse(data)
    out = ["ecamself: table=%s length=%d entries=%d"
           % (signature, table["length"], len(table["entries"]))]
    for i, (base, segment, first, last, usable) in enumerate(table["entries"]):
        out.append("ecamself: entry=%d base=0x%x segment=%d bus=%d-%d usable=%d"
                   % (i, base, segment, first, last, 1 if usable else 0))
    return out


def main(argv: list) -> int:
    if len(argv) != 3:
        sys.stderr.write("usage: mcfgref.py FILE SIGNATURE\n")
        return 2
    with open(argv[1], "rb") as src:
        data = src.read()
    print("\n".join(lines(data, argv[2])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
