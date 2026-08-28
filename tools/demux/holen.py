#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/demux/holen.py -- eine Datei AUS einem OFS-Abbild auf den Wirt.

Der Gegenweg zu `mkfs.py build`. Osum schreibt seine dekodierten
Abtastwerte in eine Datei auf der Platte; damit der Wirt sie gegen
ffmpeg halten kann, muss er sie herausholen -- und zwar mit DERSELBEN
zweiten Umsetzung des Dateisystems, die schon das Abbild gebaut hat
(tools/osum/mkfs.py). Ein eigener Leser waere eine dritte Meinung
darueber, wo ein Inode liegt.

    python3 tools/demux/holen.py <abbild> <pfad-in-osum> <ziel-auf-dem-wirt>
"""
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "osum_mkfs", os.path.join(here, "..", "osum", "mkfs.py"))
mkfs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mkfs)


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    fs = mkfs.load(sys.argv[1])
    if fs is None:
        print("holen: kein OFS-Abbild")
        return 1
    ino = fs.resolve(sys.argv[2])
    if not ino:
        print("holen: %s gibt es nicht" % sys.argv[2])
        return 1
    size = fs.iget(ino, mkfs.I_SIZE)
    with open(sys.argv[3], "wb") as f:
        f.write(fs.read_at(ino, 0, size))
    print("holen: %s -> %s  %d Oktette" % (sys.argv[2], sys.argv[3], size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
