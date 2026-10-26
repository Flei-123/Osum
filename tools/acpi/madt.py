#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct
import sys

HEADER_BYTES = 36
ENTRIES_AT = 44
TYPE_OVERRIDE = 2
OVERRIDE_BYTES = 10


def overrides(table):
    length = struct.unpack_from("<I", table, 4)[0]
    found = []
    at = ENTRIES_AT
    while at + 2 <= length:
        kind, size = table[at], table[at + 1]
        if size < 2 or at + size > length:
            break
        if kind == TYPE_OVERRIDE and size >= OVERRIDE_BYTES:
            bus, source, gsi, flags = struct.unpack_from("<BBIH", table, at + 2)
            found.append((source, gsi, flags))
        at += size
    return found


def main(argv):
    if len(argv) != 2:
        print("usage: madt.py APIC_FILE", file=sys.stderr)
        return 2
    with open(argv[1], "rb") as f:
        table = f.read()
    for source, gsi, flags in overrides(table):
        print("irq=%d gsi=%d flags=0x%04x" % (source, gsi, flags))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
