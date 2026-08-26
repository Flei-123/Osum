#!/usr/bin/env python3
"""tools/k15/keinname.py -- steht dieser Anzeigename als ZEICHENKETTE im
Quelltext?

    keinname.py <quelldatei> <name>

Die Zusage lautet: der Anzeigename eines Programms steht in Daten
(`/usr/share/apps/*.app`) und nicht im Code -- dieselbe Regel, nach der
dieses Projekt austauschbare Zeichenketten in `brands/*.toml` haelt.

EIN EINFACHES `grep` PRUEFT DAS NICHT.  Der Kopfkommentar von
`kernel/user/explorer.fi` ERKLAERT, warum das Programm "Datei-Explorer"
heisst -- und ein `grep -q 'Datei-Explorer'` schlaegt darauf an und
meldet einen Fehler, den es nicht gibt.  Genau das ist in dieser Runde
passiert.

Also wird hier unterschieden: Anmerkungen (`//` bis zum Zeilenende)
werden entfernt, und gesucht wird nur noch in dem, was uebrigbleibt --
also in Zeichenkettenliteralen und im Code.  Rueckgabe 0, wenn der Name
dort NICHT vorkommt.
"""
import re
import sys


def ohne_anmerkungen(text):
    """`//` bis zum Zeilenende weg -- aber nicht, wenn es in einem
    Zeichenkettenliteral steht.  Ein Zustandsautomat, weil ein
    `sed 's|//.*||'` an `"http://"` scheitert."""
    aus = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                aus.append(text[i:i + 2])
                i += 2
                continue
            if c == '"':
                in_str = False
            aus.append(c)
            i += 1
            continue
        if c == '"':
            in_str = True
            aus.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        aus.append(c)
        i += 1
    return "".join(aus)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    pfad, name = sys.argv[1], sys.argv[2]
    roh = open(pfad, encoding="utf-8", errors="replace").read()
    code = ohne_anmerkungen(roh)
    if name in code:
        for nr, zeile in enumerate(code.split("\n"), 1):
            if name in zeile:
                print("%s:%d: '%s' steht im Code: %s"
                      % (pfad, nr, name, zeile.strip()[:80]))
                return 1
    # Und die Gegenprobe zum Pruefer selbst: in den ANMERKUNGEN steht er
    # sehr wohl, und das ist in Ordnung -- ein Kopfkommentar darf
    # erklaeren, wie das Programm heisst.
    inkomm = name in roh and name not in code
    print("'%s' steht nicht im Code von %s%s"
          % (name, pfad, " (wohl aber in einer Anmerkung)" if inkomm else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
