#!/usr/bin/env python3
"""tools/k15/wert.py -- EIN Feld aus einer gemeldeten Zeile holen.

    wert.py <mitschnitt> <zeilenanfang> <schluessel> [rgb]

Die Anwendungen dieser Runde melden Zeilen der Form

    wigdemo: rows x=18 base=287 zh=20 fg=15265524 bg=1185824 sel=... selfg=...

und ein `grep -oE '.*fg=[0-9]+'` darauf holt `selfg` statt `fg` -- weil
`.*` gierig ist und `selfg` auf `fg` endet.  Genau dieser Fehler hat in
der ersten Fassung des Laeufers vier Zusagen umgeworfen, und zwar mit
einer Meldung, die nach einem Zeichenfehler aussah: 195 von 195
Tintenpunkten falsch, weil gegen WEISS statt gegen die Textfarbe
gerechnet wurde.

Also wird hier auf WORTGRENZEN geachtet und nicht auf Teilzeichenketten.
Mit `rgb` kommt der Wert als "r g b" heraus, wie `schau.py` ihn will.
"""
import re
import sys


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    pfad, anfang, schluessel = sys.argv[1], sys.argv[2], sys.argv[3]
    alsrgb = len(sys.argv) > 4 and sys.argv[4] == "rgb"
    pat = re.compile(r"(?:^|\s)%s=(-?\d+)" % re.escape(schluessel))
    treffer = None
    with open(pfad, "rb") as f:
        for roh in f:
            z = roh.decode("latin-1").rstrip("\n")
            if not z.startswith(anfang):
                continue
            m = pat.search(z)
            if m:
                treffer = int(m.group(1))
    if treffer is None:
        return 1
    if alsrgb:
        print("%d %d %d" % ((treffer >> 16) & 255, (treffer >> 8) & 255,
                            treffer & 255))
    else:
        print(treffer)
    return 0


if __name__ == "__main__":
    sys.exit(main())
