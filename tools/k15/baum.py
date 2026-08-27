#!/usr/bin/env python3
"""tools/k15/baum.py -- der Verzeichnisbaum, den der Dateimanager zeigt.

Er wird HIER gebaut und nicht von Hand in `run.sh` aufgezaehlt, aus
einem Grund: der Laeufer muss wissen, was in der Liste stehen MUSS --
und zwar in derselben Reihenfolge, in der der Dateimanager sortiert.
Zwei Listen, die man getrennt pflegt, gehen auseinander; eine, die
beide benutzen, nicht.

    baum.py <verzeichnis>

Legt darin an:
    theme      das Farbschema, das `/etc/theme` wird
    liste      die Argumente fuer mkfs.py, eine Zeile je Stueck
    soll.txt   was der Dateimanager in /daten zeigen MUSS, sortiert
               nach Namen -- Name, Groesse, Art
"""
import os
import sys

# Name, Inhalt.  Die Groessen sind absichtlich verschieden und
# absichtlich klein: die Zusage ist "die Spalte zeigt die Groesse, die
# `stat` meldet", und die prueft sich an 3 Oktetten so gut wie an 3000.
DATEIEN = [
    ("alpha.txt", b"eins\n"),
    ("beta.txt", b"zweizwei\n"),
    ("gamma.txt", b"drei" * 8 + b"\n"),
    ("delta.txt", b""),
    ("epsilon.txt", b"x" * 300),
    ("zeta.md", b"# zeta\n"),
]
ORDNER = ["bilder", "notizen"]
# Was in den Unterordnern liegt -- damit ein Doppelklick auf einen
# Ordner etwas ANDERES zeigt als vorher, und das im Bild zu sehen ist.
UNTER = {
    "bilder": [("rot.ppm", b"P6\n1 1\n255\n\xff\x00\x00"),
               ("blau.ppm", b"P6\n1 1\n255\n\x00\x00\xff")],
    "notizen": [("todo.txt", b"nichts\n")],
}

THEME = b"""# /etc/theme -- das Farbschema von Osum, Runde K15.
# Was hier nicht steht, behaelt den eingebauten Wert.
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

    zeilen = ["/daten/"]
    soll = []
    for name, inhalt in DATEIEN:
        p = os.path.join(roh, name)
        with open(p, "wb") as f:
            f.write(inhalt)
        # 0644 AUSDRUECKLICH, und hier steht warum. Seit K13 traegt jeder
        # Inode echte Rechte, und `mkfs.py` faellt ohne Angabe auf 0755
        # zurueck -- ein Wert, der fuer ein Programm richtig ist und fuer
        # eine Datendatei falsch. Der Dateimanager zeigt, was wirklich im
        # Inode steht; ohne diese Angabe stuende dort `-rwxr-xr-x` an einer
        # Textdatei. Die Rechte gehoeren an die Stelle, die die Datei
        # anlegt, nicht in einen Rueckfall.
        zeilen.append("/daten/%s=%s@0644" % (name, p))
        soll.append((name, len(inhalt), "-"))
    for o in ORDNER:
        zeilen.append("/daten/%s/" % o)
        soll.append((o, 0, "d"))
        for name, inhalt in UNTER.get(o, []):
            p = os.path.join(roh, "%s_%s" % (o, name))
            with open(p, "wb") as f:
                f.write(inhalt)
            zeilen.append("/daten/%s/%s=%s@0644" % (o, name, p))

    with open(os.path.join(d, "liste"), "w") as f:
        for z in zeilen:
            f.write(z + "\n")
    # Sortiert wie der Dateimanager: Verzeichnisse zuerst, dann Namen.
    soll.sort(key=lambda t: (0 if t[2] == "d" else 1, t[0]))
    with open(os.path.join(d, "soll.txt"), "w") as f:
        for name, groesse, art in soll:
            f.write("%s\t%d\t%s\n" % (name, groesse, art))
    print("baum: %d Stueck in /daten, %d Zeilen fuer mkfs"
          % (len(soll), len(zeilen)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
