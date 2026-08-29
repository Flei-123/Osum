#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/hover.py -- den Zeiger irgendwohin FAHREN, ohne zu klicken.

    hover.py <x,y>            > monitorbefehle.txt

`tools/themestore/click.py` macht dasselbe und klickt danach. Fuer diese
Runde reicht das nicht: der Ueberfahr-Zustand der drei Fensterknoepfe
IST der Messwert -- ein Klick auf das Kreuz schliesst das Fenster, und
dann gibt es nichts mehr zu fotografieren.

Der Weg ist derselbe und aus demselben Grund: `mouse_move` im
QEMU-Monitor ist RELATIV, weil das PS/2-Geraet dahinter nichts anderes
kann. Also erst in mehreren grossen Schritten in die linke obere Ecke
fahren -- dort bleibt der Zeiger stehen und die Vorgeschichte ist
geloescht --, dann in Schritten unter 128 herauslaufen. Ab da ist die
Stelle Rechnung und nicht Hoffnung.
"""
import sys


def go(x, y):
    out = ["mouse_move -120 -120"] * 6
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    # Ein letzter Ruettler um NULL: das Ereignis kommt trotzdem an, und
    # ohne ein Ereignis nach dem letzten Schritt hat der Server keinen
    # Anlass, den Ueberfahr-Zustand nachzurechnen.
    out.append("warte 1")
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    lines = []
    for p in argv[1:]:
        x, y = (int(v) for v in p.split(","))
        lines += go(x, y)
    lines.append("warte 2")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
