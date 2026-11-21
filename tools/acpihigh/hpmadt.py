#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct
import sys

ENTRIES_AT = 44
TYPE_LAPIC = 0
FLAG_ENABLED = 1


def processors(table):
    length = struct.unpack_from("<I", table, 4)[0]
    enabled = []
    disabled = 0
    at = ENTRIES_AT
    while at + 2 <= length:
        kind, size = table[at], table[at + 1]
        if size < 2:
            break
        if kind == TYPE_LAPIC:
            apic_id = table[at + 3]
            flags = struct.unpack_from("<I", table, at + 4)[0]
            if flags & FLAG_ENABLED:
                enabled.append(apic_id)
            else:
                disabled += 1
        at += size
    return enabled, disabled


def main(argv):
    if len(argv) != 2:
        print("usage: hpmadt.py APIC_FILE", file=sys.stderr)
        return 2
    with open(argv[1], "rb") as f:
        table = f.read()
    enabled, disabled = processors(table)
    print("enabled=%d ids=%s disabled=%d" % (len(enabled), ",".join(str(i) for i in enabled), disabled))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
