#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/viewer/holen.py -- eine Datei AUS einem OFS-Abbild holen.

`tools/osum/mkfs.py` legt Abbilder an; um zu pruefen, ob das System eine
Datei richtig GESCHRIEBEN hat, muss sie wieder heraus. Dieses Programm
benutzt dieselbe Fassung des Formats wie mkfs (es importiert sie), also
gibt es keine dritte Meinung darueber, wo ein Block liegt.

    python3 tools/viewer/holen.py <abbild> <pfad im abbild> <ziel>
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "osum"))

import mkfs  # noqa: E402


def main():
    abbild, pfad, ziel = sys.argv[1], sys.argv[2], sys.argv[3]
    fs = mkfs.load(abbild)
    ino = fs.resolve(pfad)
    if not ino:
        print("holen: kein solcher Pfad: %s" % pfad)
        return 1
    size = fs.iget(ino, mkfs.I_SIZE)
    n = (size + mkfs.BS - 1) // mkfs.BS
    daten = bytearray()
    for i in range(n):
        b = fs.file_block(ino, i, False)
        if not b:
            print("holen: Block %d fehlt" % i)
            return 1
        daten += bytes(fs.d[b * mkfs.BS:(b + 1) * mkfs.BS])
    open(ziel, "wb").write(bytes(daten[:size]))
    print("holen %s -> %s (%d Oktette)" % (pfad, ziel, size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
