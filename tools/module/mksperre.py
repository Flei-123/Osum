#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/module/mksperre.py -- K-014: the signed revocation list for .omod.

Layout (little-endian), read by `check_banlist` in kernel/ldr/module.fi:

      0   8   magic "OSUMSPR\\n"
      8   4   format (1)
     12   4   number of entries n (at most 256)
     16  64n  the Ed25519 signatures (last 64 bytes) of the revoked .omod files
  16+64n 64   Ed25519 over bytes 0 .. 16+64n, SAME key as the modules

An entry is the signature of the revoked file, not a hash: Ed25519 is
deterministic, so one signature names exactly one signed file, and the
kernel already holds it when it checks the module.

The broken variants for the test runner are built here, not patched in
afterwards with dd:

    --sig-dreh    flip one byte of the list's own signature
    --anzahl N    write N into the count field (length no longer matches)

Usage:
    mksperre.py <out> [--seed FILE] [--sig-dreh] [--anzahl N] [mod.omod ...]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkomod import ed25519_sign  # noqa: E402

MAGIC = b"OSUMSPR\n"
FORMAT = 1
SIGLEN = 64
MAX = 256


def main(argv):
    if not argv:
        sys.exit(__doc__)
    out = argv[0]
    seed_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "pruef.seed")
    flip = False
    count_override = None
    mods = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--seed":
            seed_path = argv[i + 1]; i += 2
        elif a == "--sig-dreh":
            flip = True; i += 1
        elif a == "--anzahl":
            count_override = int(argv[i + 1]); i += 2
        else:
            mods.append(a); i += 1
    seed = open(seed_path, "rb").read()
    if len(seed) != 32:
        sys.exit("mksperre: seed is %d bytes, not 32" % len(seed))
    if len(mods) > MAX:
        sys.exit("mksperre: at most %d entries" % MAX)
    entries = []
    for m in mods:
        data = open(m, "rb").read()
        if len(data) < 128 or data[:8] != b"OSUMMOD\n":
            sys.exit("mksperre: %s is not an .omod" % m)
        entries.append(data[-SIGLEN:])
    n = len(entries) if count_override is None else count_override
    body = MAGIC + struct.pack("<II", FORMAT, n) + b"".join(entries)
    sig = bytearray(ed25519_sign(seed, body))
    if flip:
        sig[0] ^= 0x01
    open(out, "wb").write(body + bytes(sig))
    print("%s: %d entries, %d bytes" % (out, len(entries), len(body) + SIGLEN))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
