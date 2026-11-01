#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bild/check.py -- DER UMLAUF, MIT EINER ZAHL DAHINTER.

    python3 tools/bild/check.py <bilderverzeichnis> <geholtverzeichnis>

Das System hat Dateien GESCHRIEBEN (`viewer -s`), und der Wirt hat sie
vom Abbild geholt. Hier wird gemessen, ob sie etwas wert sind -- mit
Pillow, also mit libpng und libjpeg-turbo, und nicht noch einmal mit dem
Kodierer, der geprueft werden soll.

DIE SCHRANKEN SIND NICHT FUER ALLE GLEICH, und das hat einen Grund:

  PNG IST VERLUSTFREI. Ein GIF oder BMP, als PNG gesichert, muss
  Bildpunkt fuer Bildpunkt DASSELBE Bild sein. Schranke: 0. Nicht
  "klein" -- null.

  JPEG IST EINE NAEHERUNG, und zwar eine, die die Norm nicht bis aufs
  letzte Bit festlegt. Die Frage ist also nicht "wie weit weg vom
  Original", sondern: LIEGT MEIN KODIERER DA, WO LIBJPEG AUCH LIEGT?
  Darum wird dreifach gemessen:

    1. gegen das Original -- was der Mensch sieht.
    2. gegen LIBJPEG BEI DERSELBEN QUALITAET auf demselben Quellbild.
       Das ist die eigentliche Messung: zwei richtige Kodierer duerfen
       sich unterscheiden, aber nicht weit. Schranke: 6 Stufen im
       Mittel.
    3. die Dateigroesse gegen libjpeg. Ein Kodierer, der die
       Huffman-Tabellen falsch benutzt, wird sofort deutlich groesser.

  WARUM DAS DIE HONEST MESSUNG IST: ein Bild mit harten Kanten (und die
  Testbilder haben welche, absichtlich) verliert auch bei libjpeg und
  Qualitaet 90 sieben Stufen im Mittel. Wer nur gegen das Original
  misst und eine kleine Zahl verlangt, misst nicht den Kodierer,
  sondern die Glattheit des Testbildes.
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


def points_2(im):
    return list(im.convert("RGB").getdata())


def spacing_2(a, b):
    """Groesster und mittlerer Abstand je Bildpunkt (ueber die drei
    Kanaele das Maximum)."""
    worst = 0
    sum_ = 0
    nz = 0
    for x, y in zip(a, b):
        d = max(abs(x[0] - y[0]), abs(x[1] - y[1]), abs(x[2] - y[2]))
        if d:
            nz += 1
        sum_ += d
        if d > worst:
            worst = d
    n = max(1, len(a))
    return worst, sum_ / n, nz, n


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    quelldir, holdir = argv[1], argv[2]
    bad = 0
    for name, source_2, art, q in FAELLE:
        hp = os.path.join(holdir, name)
        qp = os.path.join(quelldir, source_2)
        if not os.path.exists(hp) or os.path.getsize(hp) == 0:
            print("FAIL  %-12s the file did not come from the image" % name)
            bad += 1
            continue
        try:
            mein = Image.open(hp)
            mein.load()
        except Exception as e:
            print("FAIL  %-12s Pillow cannot open it: %s" % (name, e))
            bad += 1
            continue
        orig = Image.open(qp)
        orig.seek(0)
        if mein.size != orig.size:
            print("FAIL  %-12s dimensions %s instead of %s"
                  % (name, mein.size, orig.size))
            bad += 1
            continue
        fmt = (mein.format or "?").lower()
        if fmt != art:
            print("FAIL  %-12s Pillow nennt es %s, erwartet %s"
                  % (name, fmt, art))
            bad += 1
            continue
        pm, po = points_2(mein), points_2(orig)
        worst, mittel, nz, n = spacing_2(pm, po)
        if art == "png":
            if worst == 0:
                print("OK    %-12s %dx%d PNG verlustfrei, Abweichung 0 "
                      "(%d Bildpunkte)" % (name, mein.size[0],
                                           mein.size[1], n))
            else:
                print("FAIL  %-12s PNG is NOT lossless: maxdiff=%d, "
                      "%d von %d Bildpunkten weichen ab"
                      % (name, worst, nz, n))
                bad += 1
            continue
        b = io.BytesIO()
        orig.convert("RGB").save(b, "JPEG", quality=q, subsampling=0)
        libp = points_2(Image.open(io.BytesIO(b.getvalue())))
        lw, lm, _lnz, _ln = spacing_2(libp, po)
        vw, vm, _vnz, _vn = spacing_2(pm, libp)
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
            bad += 1
        else:
            print("OK    " + header)
    print("pruefen: %d Faelle, %d schlecht" % (len(FAELLE), bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
