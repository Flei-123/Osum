#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import struct
import sys

HEADER_BYTES = 36
CHECKSUM_OFFSET = 9
SIGNATURE = b"XMCF"
OEM_ID = b"OSUMTS"
OEM_TABLE_ID = b"SYNTHMCF"
RESERVED_BYTES = 8
MIB = 1 << 20

CASES = {
    "synth-multi": [
        (0xB0000000, 0, 0, 127),
        (0xB8000000, 0, 128, 255),
        (0x8000000000, 1, 0, 255),
    ],
    "synth-invalid": [
        (0xB0000000, 0, 0, 255),
        (0, 0, 0, 255),
        (0xB0100800, 0, 0, 15),
        (0xC0000000, 0, 9, 3),
        (0xFFFFFFFFFFF00000, 0, 0, 255),
        (0xD0000000, 7, 32, 63),
    ],
    "synth-empty": [],
    "synth-partial": None,
}


def build(entries, trailing: int = 0) -> bytes:
    body = bytes(RESERVED_BYTES)
    for base, segment, first, last in entries:
        body += struct.pack("<QHBBI", base, segment, first, last, 0)
    body += bytes(trailing)
    length = HEADER_BYTES + len(body)
    header = struct.pack("<4sIBB6s8sI4sI", SIGNATURE, length, 1, 0,
                         OEM_ID, OEM_TABLE_ID, 1, b"OSUM", 1)
    table = bytearray(header + body)
    table[CHECKSUM_OFFSET] = (-sum(table)) & 0xFF
    return bytes(table)


def main(argv: list) -> int:
    if len(argv) != 2:
        sys.stderr.write("usage: mcfgsynth.py OUTDIR\n")
        return 2
    os.makedirs(argv[1], exist_ok=True)
    for name, entries in CASES.items():
        if entries is None:
            data = build([], trailing=6)
        else:
            data = build(entries)
        with open(os.path.join(argv[1], name), "wb") as dst:
            dst.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
