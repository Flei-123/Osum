#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""checkshot.py
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HIER), "k15"))
import icon as symmod  # noqa: E402
sys.path.insert(0, HIER)
import icons as iconmod  # noqa: E402


def ppm(path_2):
    d = open(path_2, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % path_2)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        anf = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        felder.append(int(d[anf:at]))
    at += 1
    w, h, _ = felder
    return w, h, d[at:]


ROLLE_NAME = {v: k for k, v in symmod.ROLLEN.items()}


def main(argv):
    if len(argv) < 6:
        print(__doc__)
        return 2
    screen, x, y, zeichnung, schema = (argv[1], int(argv[2]), int(argv[3]),
                                       argv[4], argv[5])
    nicht = "--nicht" in argv
    farben = iconmod.schema_read(schema)
    palette, rows = symmod.read_2(zeichnung)
    w, h, roh = ppm(screen)
    deckend = 0
    wrong = 0
    for r, line in enumerate(rows):
        for c, chars in enumerate(line):
            soll = palette[chars]
            if soll is None:
                continue
            if isinstance(soll, tuple):
                soll = farben[ROLLE_NAME[soll[1]]]
            deckend += 1
            px, py = x + c, y + r
            if px >= w or py >= h:
                wrong += 1
                continue
            at = (py * w + px) * 3
            if (roh[at] != ((soll >> 16) & 255)
                    or roh[at + 1] != ((soll >> 8) & 255)
                    or roh[at + 2] != (soll & 255)):
                wrong += 1
    if nicht:
        if wrong * 4 >= deckend:
            print("ok not there: %d of %d different" % (wrong, deckend))
            return 0
        print("there, but should not be: only %d of %d different" % (wrong, deckend))
        return 1
    if wrong:
        print("wrong %d of %d" % (wrong, deckend))
        return 1
    print("ok %d of %d equal" % (deckend, deckend))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
