#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/count.py -- WIE VIELE STELLEN IM KERNEL AUF DIE GRAFIK
GREIFEN.

Die Aufgabe der Runde SERVERBUILD verlangt diese Zahl ausdruecklich:
sie sagt, wie sauber der Schnitt ist. Vor der Runde waren es 745
Stellen in acht Dateien, danach null -- ausser in `kernel/gfx/gfx.fi`, und
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
OWN = set(g + ".fi" for g in GRAFIK) | {
    "gfx.fi", "gfx-aus.fi", "kgui.fi", "kgbase.fi", "kgdisp.fi", "kgsvc.fi", "kgwm.fi", "kgrun.fi", "kgstage.fi", "sysgui.fi",
    "dispsave.fi",
    "zeiger.fi",
    "vgpu.fi",
    "beam.fi",
    "shot.fi",
    "pixelguard.fi",
    "vmsvga.fi",
    "drucke.fi",
    "fuiglyph.fi"}
MUSTER = re.compile(
    r"(?<![A-Za-z0-9_.])(" + "|".join(GRAFIK) + r")\.(?!(?:len|ptr)\b)([A-Za-z_][A-Za-z0-9_]*)")


def without_kommentare(text):
    aus = []
    for line in text.split("\n"):
        i = line.find("//")
        aus.append(line[:i] if i >= 0 else line)
    return "\n".join(aus)


def without_importe(text):
    """`import font.metrics` ist kein Zugriff auf die Grafik.

    RUNDE ROTABSCHNITTE.  `kernel/user/fuib.fi:72` stand mit genau einer
    Stelle in der Liste, und diese Stelle war die Zeile `import
    font.metrics` -- der Name eines MODULS aus `lib/`, nicht der Aufruf
    von `kernel/gfx/font.fi`.  Eine Einbindung sagt nichts darueber, ob
    jemand den Rahmenpuffer anfasst; sie nennt nur, woher ein Name
    kommt.  Gezaehlt werden soll der ZUGRIFF.
    """
    aus = []
    for line in text.split("\n"):
        if re.match(r"\s*import\s", line):
            aus.append("")
        else:
            aus.append(line)
    return "\n".join(aus)


def zaehle(root):
    je_file = collections.Counter()
    names = collections.Counter()
    for path_2, _, dateien in os.walk(root):
        for d in sorted(dateien):
            if not d.endswith(".fi") or d in OWN:
                continue
            p = os.path.join(path_2, d)
            with open(p, "rb") as f:
                roh = f.read().decode("utf8", "replace")
            foreign = set(re.findall(r"^\s*import\s+(?!(?:gfx|ui|drv)\.)[A-Za-z0-9_.]+\.([A-Za-z0-9_]+)", roh, re.M))
            treffer = [t for t in MUSTER.findall(without_importe(without_kommentare(roh))) if t[0] not in foreign]
            if treffer:
                je_file[os.path.relpath(p, root)] = len(treffer)
                for a, b in treffer:
                    names[a + "." + b] += 1
    return je_file, names


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    if not os.path.isdir(root):
        print(-1)
        return 1
    je_file, names = zaehle(root)
    if "--je-datei" in sys.argv:
        for k, v in je_file.most_common():
            print("  %-26s %d" % (k, v))
        print("  SUMME %d Stellen, %d verschiedene Funktionen, in %d Dateien"
              % (sum(je_file.values()), len(names), len(je_file)))
    else:
        print(sum(je_file.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
