#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/tree.py -- der Verzeichnisbaum, den der Dateimanager zeigt.

Er wird HIER gebaut und nicht von Hand in `run.sh` aufgezaehlt, aus
einem Grund: der Laeufer muss wissen, was in der Liste stehen MUSS --
und zwar in derselben Reihenfolge, in der der Dateimanager sortiert.
Zwei Listen, die man getrennt pflegt, gehen auseinander; eine, die
beide benutzen, nicht.

    tree.py <verzeichnis>

Legt darin an:
    theme      das Farbschema, das `/etc/theme` wird
    liste      die Argumente fuer mkfs.py, eine Zeile je Stueck
    soll.txt   was der Dateimanager in /data zeigen MUSS, sortiert
               nach Namen -- Name, Groesse, Art
"""
import os
import sys

DATEIEN = [
    ("alpha.txt", b"eins\n"),
    ("beta.txt", b"zweizwei\n"),
    ("gamma.txt", b"drei" * 8 + b"\n"),
    ("delta.txt", b""),
    ("epsilon.txt", b"x" * 300),
    ("zeta.md", b"# zeta\n"),
]
FOLDER = ["bilder", "notizen"]
UNDER = {
    "bilder": [("rot.ppm", b"P6\n1 1\n255\n\xff\x00\x00"),
               ("blau.ppm", b"P6\n1 1\n255\n\x00\x00\xff")],
    "notizen": [("todo.txt", b"nichts\n")],
}

THEME = b"""# /etc/theme -- the Osum color scheme, round K15.
bg=1c2430
panel=26303c
btn=3a4a5e
btnhi=4e627a
btndn=161c24
entry=121820
head=32404e
sel=2f5f9c
accent=5cc8ff
focus=ffc020
dlg=222a34
menu=2a3542
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    roh = os.path.join(d, "roh")
    os.makedirs(roh, exist_ok=True)
    with open(os.path.join(d, "theme"), "wb") as f:
        f.write(THEME)

    zeilen = ["/data/"]
    soll = []
    for name, inhalt in DATEIEN:
        p = os.path.join(roh, name)
        with open(p, "wb") as f:
            f.write(inhalt)
        zeilen.append("/data/%s=%s@0644" % (name, p))
        soll.append((name, len(inhalt), "-"))
    for o in FOLDER:
        zeilen.append("/data/%s/" % o)
        soll.append((o, 0, "d"))
        for name, inhalt in UNDER.get(o, []):
            p = os.path.join(roh, "%s_%s" % (o, name))
            with open(p, "wb") as f:
                f.write(inhalt)
            zeilen.append("/data/%s/%s=%s@0644" % (o, name, p))

    with open(os.path.join(d, "liste"), "w") as f:
        for z in zeilen:
            f.write(z + "\n")
    soll.sort(key=lambda t: (0 if t[2] == "d" else 1, t[0]))
    with open(os.path.join(d, "soll.txt"), "w") as f:
        for name, size_2, art in soll:
            f.write("%s\t%d\t%s\n" % (name, size_2, art))
    print("tree: %d entries in /data, %d lines for mkfs"
          % (len(soll), len(zeilen)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
