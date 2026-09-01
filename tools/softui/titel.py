#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/titel.py -- DER KONTRAST DER TITELSCHRIFT, AUS DEM BILD.

Die Auflage lautet, der Kontrast duerfe nicht schlechter werden.  Fuer
das TOKENMODELL ist das trivial wahr -- diese Runde hat keine einzige
Farbe geaendert.  Interessant ist die andere Frage: was steht WIRKLICH
auf dem Schirm, nachdem die Titelleiste den Akzent verloren und einen
Verlauf bekommen hat?

Also wird der Balken des scharfen Fensters aus dem Bild geschnitten und
`tools/softui/kontrast.py band` darauf angewandt -- Schrift gegen ihren
eigenen Grund, WCAG 2.1, an der Stelle, an der ein Mensch liest.  Der
Verlauf ist dabei ausdruecklich MIT drin: er macht den Grund an der
Oberkante um wenige Stufen dunkler, und wenn das den Kontrast unter die
Marke druecken wuerde, muss es hier auffallen.

    titel.py <bild.ppm> <serial.txt>
"""
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
import kontrast  # noqa: E402

BORDER = 2
TITLE_H = 22
CAP_W = 30
CAP_N = 3

WIN = re.compile(r"^wm: win nr=(\d+) id=(\d+) .*deco=(\d+) x=(-?\d+) "
                 r"y=(-?\d+) w=(\d+) h=(\d+) focus=(\d+) .*ow=(\d+) "
                 r"oh=(\d+) t=\[(.*)\]$")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    ziel = None
    for ln in open(argv[2], "rb").read().decode("utf-8", "replace").splitlines():
        m = WIN.match(ln.strip())
        if m and m.group(3) == "1" and m.group(8) == "1":
            ziel = dict(x=int(m.group(4)), y=int(m.group(5)),
                        ow=int(m.group(9)), t=m.group(11))
    if ziel is None:
        print("kein scharfes Fenster mit Schmuck im Mitschnitt")
        return 1
    # Nur der Teil mit der Beschriftung: hinter dem Netzzeichen, vor den
    # drei Schaltflaechen.
    x = ziel["x"] + BORDER + 4
    y = ziel["y"] + BORDER
    w = ziel["ow"] - 2 * BORDER - CAP_N * CAP_W - 8
    h = TITLE_H - 1 - BORDER
    print("titel '%s' band %d,%d %dx%d" % (ziel["t"], x, y, w, h))
    return kontrast.band(argv[1], x, y, w, h, 12)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
