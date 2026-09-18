#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bild/pruefen.py -- DER UMLAUF, MIT EINER ZAHL DAHINTER.

    python3 tools/bild/pruefen.py <bilderverzeichnis> <geholtverzeichnis>

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

# Welche geholte Datei kommt aus welcher Quelle, und wie streng?
#   (geholt, quelle, art, qualitaet)
FAELLE = [
    ("s-gif.png", "g-tafel.gif", "png", None),
    ("s-lace.png", "g-lace.gif", "png", None),
    ("s-bmp.png", "b-probe.bmp", "png", None),
    ("s-png.jpg", "b-probe.png", "jpeg", 90),
    ("s-jpg.jpg", "b-voll.jpg", "jpeg", 90),
    ("s-gif.jpg", "g-tafel.gif", "jpeg", 90),
]

# Die Schranken. `MITTEL_LIBJPEG` ist die wichtige: so weit darf mein
# Kodierer von libjpeg abweichen, bei gleicher Qualitaet und gleichem
# Bild.
MITTEL_LIBJPEG = 6.0
MAX_LIBJPEG = 40
GROESSE_FAKTOR = 1.35


def punkte(im):
    return list(im.convert("RGB").getdata())


def abstand(a, b):
    """Groesster und mittlerer Abstand je Bildpunkt (ueber die drei
    Kanaele das Maximum)."""
    worst = 0
    summe = 0
    nz = 0
    for x, y in zip(a, b):
        d = max(abs(x[0] - y[0]), abs(x[1] - y[1]), abs(x[2] - y[2]))
        if d:
            nz += 1
        summe += d
        if d > worst:
            worst = d
    n = max(1, len(a))
    return worst, summe / n, nz, n


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    quelldir, holdir = argv[1], argv[2]
    schlecht = 0
    for name, quelle, art, q in FAELLE:
        hp = os.path.join(holdir, name)
        qp = os.path.join(quelldir, quelle)
        if not os.path.exists(hp) or os.path.getsize(hp) == 0:
            print("FAIL  %-12s die Datei kam nicht vom Abbild" % name)
            schlecht += 1
            continue
        try:
            mein = Image.open(hp)
            mein.load()
        except Exception as e:
            print("FAIL  %-12s Pillow macht sie nicht auf: %s" % (name, e))
            schlecht += 1
            continue
        orig = Image.open(qp)
        orig.seek(0)
        if mein.size != orig.size:
            print("FAIL  %-12s Maße %s statt %s"
                  % (name, mein.size, orig.size))
            schlecht += 1
            continue
        fmt = (mein.format or "?").lower()
        if fmt != art:
            print("FAIL  %-12s Pillow nennt es %s, erwartet %s"
                  % (name, fmt, art))
            schlecht += 1
            continue
        pm, po = punkte(mein), punkte(orig)
        worst, mittel, nz, n = abstand(pm, po)
        if art == "png":
            # Verlustfrei: jede Zahl muss stimmen.
            if worst == 0:
                print("OK    %-12s %dx%d PNG verlustfrei, Abweichung 0 "
                      "(%d Bildpunkte)" % (name, mein.size[0],
                                           mein.size[1], n))
            else:
                print("FAIL  %-12s PNG ist NICHT verlustfrei: maxdiff=%d, "
                      "%d von %d Bildpunkten weichen ab"
                      % (name, worst, nz, n))
                schlecht += 1
            continue
        # JPEG: gegen libjpeg bei derselben Qualitaet.
        b = io.BytesIO()
        orig.convert("RGB").save(b, "JPEG", quality=q, subsampling=0)
        libp = punkte(Image.open(io.BytesIO(b.getvalue())))
        lw, lm, _lnz, _ln = abstand(libp, po)
        vw, vm, _vnz, _vn = abstand(pm, libp)
        libgr = len(b.getvalue())
        meingr = os.path.getsize(hp)
        schlimm = []
        if vm > MITTEL_LIBJPEG:
            schlimm.append("Abstand zu libjpeg %.2f > %.1f"
                           % (vm, MITTEL_LIBJPEG))
        if vw > MAX_LIBJPEG:
            schlimm.append("groesster Abstand zu libjpeg %d > %d"
                           % (vw, MAX_LIBJPEG))
        if meingr > libgr * GROESSE_FAKTOR:
            schlimm.append("Datei %d gegen %d Oktette (Faktor %.2f)"
                           % (meingr, libgr, meingr / max(1, libgr)))
        kopf = ("%-12s %dx%d JPEG q%d: gegen das Original maxdiff=%d "
                "mittel=%.2f | libjpeg selbst maxdiff=%d mittel=%.2f | "
                "gegen libjpeg maxdiff=%d mittel=%.2f | %d gegen %d Oktette"
                % (name, mein.size[0], mein.size[1], q, worst, mittel,
                   lw, lm, vw, vm, meingr, libgr))
        if schlimm:
            print("FAIL  " + kopf + " -- " + "; ".join(schlimm))
            schlecht += 1
        else:
            print("OK    " + kopf)
    print("pruefen: %d Faelle, %d schlecht" % (len(FAELLE), schlecht))
    return 0 if schlecht == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
