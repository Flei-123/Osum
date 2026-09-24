#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/namecheck.py -- der Name auf der Vorschaukachel,
Zeichen fuer Zeichen gegen die Vorlage, aus der er stammt.

    namecheck.py <bild.png> <serial.txt> <assets/themes> [<lochbild.png>]

WARUM ES DIESES WERKZEUG GIBT.

Auf Bild 09 der Runde GLAS stand auf der vierten Vorschaukachel
"Mittemacht" statt "Mitternacht", und links davon, am Rand der Kachel,
ein heller Keil, der wie ein abgerutschtes Zeichen aussah. Zwei
Verdaechtige, und beide muessen ausgeschlossen werden koennen, bevor
man etwas repariert:

  1. Die Zeile verliert am Feldrand ein Zeichen (die Kachel kuerzt und
     sagt es nicht).
  2. Der Zeichensatz verschluckt das 'r' (die Glyphe kommt nicht an).

GEMESSEN wurde beides, und keines von beiden war es. Der Keil war ein
Loch in der FLAECHE der Kachel (`glascheck.py kachel innen=`, behoben in
kernel/user/wlib.fi `paint_tile`), und die Schrift steht vollstaendig
da: alle elf Zeichen liegen auf genau den Stellen, die der zweite
Rasterer (`tools/ttf/raster.py`) fuer diese Schrift und diese Groesse
ausrechnet. Dass ein Mensch "Mittemacht" liest, kommt vom Schriftbild
selbst -- der Arm des 'r' reicht bei 15 Bildpunkten bis in die Schulter
des 'n' (die Unterschneidung des Paares ist -36/64 Bildpunkte), und das
Paar 'rn' sieht dann aus wie ein 'm'. Das ist eine Eigenschaft der
Schrift und keine verlorene Glyphe -- und weil das ein Satz ist, den
man behaupten kann, steht hier die Messung dazu.

WAS GEPRUEFT WIRD, und jedes gegen eine zweite Quelle:

  gemalt      jede Kachelbeschriftung, die das Programm selbst gemeldet
              hat (`wlib: text ... kind=12 ... t=`)
  soll        jede `name=`-Zeile aus assets/themes/*.preset
  fehlt       ein Name der Vorlage, den keine Kachel gemalt hat
  gekuerzt    eine Kachel, die weniger Oktette gemalt als gemeldet hat
              (`nq` gegen `nv`, und beide gegen die Laenge des Namens)
  ohnetinte   eine GLYPHE, an deren gerechneter Stelle im Bild keine
              Tinte steht -- die Gegenprobe gegen "der Zeichensatz
              verschluckt ein Zeichen"

Mit einem vierten Argument schreibt das Werkzeug ein LOCHBILD: dasselbe
Bild, in dem das erste 'r' des ersten Namens mit der Flaechenfarbe
seiner Kachel uebermalt ist. Auf ihm MUSS `ohnetinte` groesser als 0
sein -- sonst misst die Probe oben nichts.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ttf"))
import raster                                      # noqa: E402
import fuiraster                                   # noqa: E402

from PIL import Image                              # noqa: E402

# Die Schrift und die Groesse der Oberflaeche: `wlibc.F_UI` ist
# assets/osum-sans.ttf, `wlibc.px_ui()` ist PX_UI0 = 15 bei
# Vervielfachung 1 -- die Groesse, mit der jeder Lauf dieser Abnahme
# faehrt.
SCHRIFT = "assets/osum-sans.ttf"
PX_UI = 15

ZEILE = re.compile(
    r"wlib: text win=(\d+) kind=12 x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+) ax=(\d+) ay=(\d+) nq=(\d+) nv=(\d+) t=(.*)")


def rgb(v):
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def glyphkasten(s, name, m):
    """(Zeichen, x, y, Glyphe) je Zeichen einer gemalten Kachelzeile."""
    x0 = int(m.group(7)) + int(m.group(2))
    base = int(m.group(8)) + int(m.group(3))
    for c, x26 in s.stellen(name):
        g = s.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        yield c, x0 + (x26 >> 6) + g.links, base - g.oben, g


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    bild, serial, themes = argv[1], argv[2], argv[3]
    roh = open(serial, "rb").read().decode("latin1")
    # Der Stand ZUM ZEITPUNKT DER AUFNAHME: alles nach dem letzten
    # vollstaendigen Bericht der Rechtecke. Dieselbe Regel wie in
    # shotcheck.py, und aus demselben Grund -- ein Mitschnitt traegt
    # jeden Anstrich, die Aufnahme zeigt den letzten.
    schnitt = roh.rfind("settings: rect name=waa ")
    schwanz = roh[schnitt:] if schnitt >= 0 else roh
    gemalt = {}
    for ln in schwanz.splitlines():
        m = ZEILE.search(ln)
        if m:
            gemalt[m.group(11)] = m

    soll = {}
    for p in sorted(glob.glob(os.path.join(themes, "*.preset"))):
        for ln in open(p, "rb").read().decode("latin1").splitlines():
            if ln.startswith("name="):
                soll[ln[5:].strip()] = os.path.basename(p)

    im = Image.open(bild).convert("RGB")
    # ROUND FUI-TEXT: the tile names are Ring 3 text, drawn by fUi.
    s = fuiraster.Schrift(SCHRIFT, PX_UI)

    if len(argv) > 4:
        # DAS LOCHBILD: die erste Glyphe 'r' der ersten Kachel, die eine
        # hat, mit der Flaechenfarbe ihrer Kachel uebermalt.
        loch = im.copy()
        gemacht = False
        for name, m in sorted(gemalt.items()):
            if gemacht:
                break
            bg = rgb(int(m.group(5)))
            for c, gx, gy, g in glyphkasten(s, name, m):
                if c != ord("r"):
                    continue
                for j in range(g.h):
                    for i in range(g.w):
                        if 0 <= gx + i < loch.size[0] and 0 <= gy + j < loch.size[1]:
                            loch.putpixel((gx + i, gy + j), bg)
                gemacht = True
                break
        loch.save(argv[4])

    fehlt = [n for n in soll if n not in gemalt]
    # GEKUERZT heisst hier dreierlei zugleich, und alle drei muessen
    # gelten: das Programm hat so viele Oktette gemalt, wie es gemeldet
    # hat (`nq == nv`), und so viele, wie der Name hat.
    kurz = [n for n, m in gemalt.items()
            if m.group(9) != m.group(10)
            or len(n.encode("latin1")) != int(m.group(10))]
    leer = []
    for name, m in sorted(gemalt.items()):
        if name not in soll:
            continue
        fg = rgb(int(m.group(4)))
        bg = rgb(int(m.group(5)))
        for c, gx, gy, g in glyphkasten(s, name, m):
            tinte = 0
            for j in range(g.h):
                for i in range(g.w):
                    # Nur die VOLL gedeckten Bildpunkte der Glyphe: die
                    # Raender sind Mischtoene und haengen an dem, was
                    # unter ihnen lag.
                    if g.a[j * g.w + i] < 128:
                        continue
                    X, Y = gx + i, gy + j
                    if not (0 <= X < im.size[0] and 0 <= Y < im.size[1]):
                        continue
                    p = im.getpixel((X, Y))
                    df = sum(abs(p[k] - fg[k]) for k in range(3))
                    db = sum(abs(p[k] - bg[k]) for k in range(3))
                    if df < db:
                        tinte += 1
            if tinte < 2:
                leer.append("%s: '%s' bei x=%d hat %d Tintenpunkte"
                            % (name, chr(c), gx, tinte))
    print("namen gemalt=%d soll=%d fehlt=%d gekuerzt=%d ohnetinte=%d"
          % (len(gemalt), len(soll), len(fehlt), len(kurz), len(leer)))
    for z in fehlt[:5]:
        print("    fehlt: %s" % z)
    for z in kurz[:5]:
        print("    gekuerzt: %s" % z)
    for z in leer[:5]:
        print("    %s" % z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
