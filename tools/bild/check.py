#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    python3 tools/image/check.py <bilderverzeichnis> <geholtverzeichnis>
"""

import io
import warnings
import os
import sys

warnings.filterwarnings("ignore", category=DeprecationWarning)

from PIL import Image

FAELLE = [
    ("s-gif.png", "g-tafel.gif", "png", None),
    ("s-lace.png", "g-lace.gif", "png", None),
    ("s-bmp.png", "b-probe.bmp", "png", None),
    ("s-png.jpg", "b-probe.png", "jpeg", 90),
    ("s-jpg.jpg", "b-voll.jpg", "jpeg", 90),
    ("s-gif.jpg", "g-tafel.gif", "jpeg", 90),
]

MITTEL_LIBJPEG = 6.0
MAX_LIBJPEG = 40
SIZE_FACTOR = 1.35


def points(im):
    return list(im.convert("RGB").getdata())


def spacing(a, b):
    worst = 0
    sum_2 = 0
    nz = 0
    for x, y in zip(a, b):
        d = max(abs(x[0] - y[0]), abs(x[1] - y[1]), abs(x[2] - y[2]))
        if d:
            nz += 1
        sum_2 += d
        if d > worst:
            worst = d
    n = max(1, len(a))
    return worst, sum_2 / n, nz, n


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    quelldir, holdir = argv[1], argv[2]
    bad_2 = 0
    for name, source, art, q in FAELLE:
        hp = os.path.join(holdir, name)
        qp = os.path.join(quelldir, source)
        if not os.path.exists(hp) or os.path.getsize(hp) == 0:
            print("FAIL  %-12s the file did not come from the image" % name)
            bad_2 += 1
            continue
        try:
            mein = Image.open(hp)
            mein.load()
        except Exception as e:
            print("FAIL  %-12s Pillow cannot open it: %s" % (name, e))
            bad_2 += 1
            continue
        orig = Image.open(qp)
        orig.seek(0)
        if mein.size != orig.size:
            print("FAIL  %-12s dimensions %s instead of %s"
                  % (name, mein.size, orig.size))
            bad_2 += 1
            continue
        fmt = (mein.format or "?").lower()
        if fmt != art:
            print("FAIL  %-12s Pillow nennt es %s, erwartet %s"
                  % (name, fmt, art))
            bad_2 += 1
            continue
        pm, po = points(mein), points(orig)
        worst, mittel, nz, n = spacing(pm, po)
        if art == "png":
            if worst == 0:
                print("OK    %-12s %dx%d PNG verlustfrei, Abweichung 0 "
                      "(%d Bildpunkte)" % (name, mein.size[0],
                                           mein.size[1], n))
            else:
                print("FAIL  %-12s PNG is NOT lossless: maxdiff=%d, "
                      "%d von %d Bildpunkten weichen ab"
                      % (name, worst, nz, n))
                bad_2 += 1
            continue
        b = io.BytesIO()
        orig.convert("RGB").save(b, "JPEG", quality=q, subsampling=0)
        libp = points(Image.open(io.BytesIO(b.getvalue())))
        lw, lm, _lnz, _ln = spacing(libp, po)
        vw, vm, _vnz, _vn = spacing(pm, libp)
        libgr = len(b.getvalue())
        meingr = os.path.getsize(hp)
        schlimm = []
        if vm > MITTEL_LIBJPEG:
            schlimm.append("Abstand zu libjpeg %.2f > %.1f"
                           % (vm, MITTEL_LIBJPEG))
        if vw > MAX_LIBJPEG:
            schlimm.append("groesster Abstand zu libjpeg %d > %d"
                           % (vw, MAX_LIBJPEG))
        if meingr > libgr * SIZE_FACTOR:
            schlimm.append("Datei %d gegen %d Oktette (Faktor %.2f)"
                           % (meingr, libgr, meingr / max(1, libgr)))
        header = ("%-12s %dx%d JPEG q%d: gegen das Original maxdiff=%d "
                "mittel=%.2f | libjpeg selbst maxdiff=%d mittel=%.2f | "
                "gegen libjpeg maxdiff=%d mittel=%.2f | %d gegen %d Oktette"
                % (name, mein.size[0], mein.size[1], q, worst, mittel,
                   lw, lm, vw, vm, meingr, libgr))
        if schlimm:
            print("FAIL  " + header + " -- " + "; ".join(schlimm))
            bad_2 += 1
        else:
            print("OK    " + header)
    print("pruefen: %d Faelle, %d schlecht" % (len(FAELLE), bad_2))
    return 0 if bad_2 == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
