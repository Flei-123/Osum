#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/count.py -- WIE VIELE STELLEN IM KERNEL AUF DIE GRAFIK
GREIFEN.

Die Aufgabe der Runde SERVERBUILD verlangt diese Zahl ausdruecklich:
sie sagt, wie sauber der Schnitt ist. Vor der Runde waren es 745
Stellen in acht Dateien, danach null -- ausser in `kernel/drivers/gfx/gfx.fi`, und
das ist die Naht selbst.

GEZAEHLT WIRD NUR CODE. Kommentare fliegen raus, bevor gesucht wird;
in diesem Repo steht in den Kommentaren mehr ueber `fb.fi` als in
manchen Modulen an Code, und eine Zahl, die Prosa mitzaehlt, ist keine.

    count.py <kernelverzeichnis> [--je-datei]

Ohne `--je-datei` kommt genau eine Zahl heraus, damit ein Testlaeufer
sie ohne `sed` weiterverwenden kann.
"""
import collections
import os
import re
import sys

GRAFIK = ["fb", "wm", "wig", "font", "ttf", "tile", "vmode", "ansi", "ps2m"]
# Die Dateien, DENEN die Grafik gehoert: die Module selbst, die Naht und
# die beiden Ausbauten aus `kmain.fi` und `sys.fi`.
EIGEN = set(g + ".fi" for g in GRAFIK) | {
    "gfx.fi", "gfx-aus.fi", "kgui.fi", "sysgui.fi",
    # MERGE-2 18 (customres): der gespeicherte Bildmodus. Sie ist selbst
    # eine Grafikdatei und wird bei --gui off mit geloescht.
    "dispsave.fi"}
MUSTER = re.compile(
    r"(?<![A-Za-z0-9_.])(" + "|".join(GRAFIK) + r")\.([A-Za-z_][A-Za-z0-9_]*)")


def ohne_kommentare(text):
    aus = []
    for zeile in text.split("\n"):
        i = zeile.find("//")
        aus.append(zeile[:i] if i >= 0 else zeile)
    return "\n".join(aus)


def zaehle(wurzel):
    je_datei = collections.Counter()
    namen = collections.Counter()
    for pfad, _, dateien in os.walk(wurzel):
        for d in sorted(dateien):
            if not d.endswith(".fi") or d in EIGEN:
                continue
            p = os.path.join(pfad, d)
            with open(p, "rb") as f:
                roh = f.read().decode("utf8", "replace")
            treffer = MUSTER.findall(ohne_kommentare(roh))
            if treffer:
                je_datei[os.path.relpath(p, wurzel)] = len(treffer)
                for a, b in treffer:
                    namen[a + "." + b] += 1
    return je_datei, namen


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    wurzel = sys.argv[1]
    if not os.path.isdir(wurzel):
        print(-1)
        return 1
    je_datei, namen = zaehle(wurzel)
    if "--je-datei" in sys.argv:
        for k, v in je_datei.most_common():
            print("  %-26s %d" % (k, v))
        print("  SUMME %d Stellen, %d verschiedene Funktionen, in %d Dateien"
              % (sum(je_datei.values()), len(namen), len(je_datei)))
    else:
        print(sum(je_datei.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
