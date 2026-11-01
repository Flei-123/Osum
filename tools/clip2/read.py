#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, "..", "fsrobust"))
sys.path.insert(0, os.path.join(HIER, "..", "osum"))

import check  # noqa: E402
import mkfs   # noqa: E402


def main(argv):
    if len(argv) < 2:
        print("Aufruf: read.py <abbild>", file=sys.stderr)
        return 2
    b = check.Bild(argv[1])
    if not b.magic:
        print("kein OFS-Abbild", file=sys.stderr)
        return 1

    def zeig(pfad):
        ino = b.finde(pfad)
        if ino:
            print("da %s ino=%d size=%d"
                  % (pfad, ino, b.ig(ino, mkfs.I_SIZE)))
        else:
            print("weg %s" % pfad)
        return ino

    alt = zeig("/data/alpha.txt")
    new = zeig("/data/bilder/alpha.txt")
    zeig("/data/notizen")
    zeig("/data/beta.txt")

    if len(argv) > 2:
        try:
            vorher = int(argv[2])
        except ValueError:
            vorher = 0
        if new and vorher and new == vorher:
            print("inode gleich %d" % new)
        elif new and vorher:
            print("inode anders %d %d" % (vorher, new))

    if new:
        roh = b.lies(new, 0, b.ig(new, mkfs.I_SIZE))
        txt = roh.decode("latin-1").strip()
        if txt == "eins":
            print("inhalt ok %s" % txt)
        else:
            print("inhalt falsch %r" % txt)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
