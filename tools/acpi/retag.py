#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

SIGNATURE_BYTES = 4
LENGTH_OFFSET = 4
CHECKSUM_OFFSET = 9
HEADER_BYTES = 36


def retag(data: bytes, signature: str) -> bytes:
    sig = signature.encode("ascii")
    if len(sig) != SIGNATURE_BYTES:
        raise ValueError("signature must be 4 characters")
    if len(data) < HEADER_BYTES:
        raise ValueError("table shorter than the ACPI header")
    length = int.from_bytes(data[LENGTH_OFFSET:LENGTH_OFFSET + 4], "little")
    if length > len(data) or length < HEADER_BYTES:
        raise ValueError("header length does not fit the file")
    out = bytearray(data[:length])
    out[0:SIGNATURE_BYTES] = sig
    out[CHECKSUM_OFFSET] = 0
    out[CHECKSUM_OFFSET] = (-sum(out)) & 0xFF
    return bytes(out)


def main(argv: list) -> int:
    if len(argv) != 4:
        sys.stderr.write("usage: retag.py IN OUT NEWSIG\n")
        return 2
    with open(argv[1], "rb") as src:
        data = src.read()
    with open(argv[2], "wb") as dst:
        dst.write(retag(data, argv[3]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
