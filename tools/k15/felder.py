#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/felder.py -- den Inhalt der beiden Textfelder aus dem
Mitschnitt holen, und zwar aus einer Zeile, die WIRKLICH vollstaendig ist.

    felder.py <mitschnitt> e1|e2

Die serielle Leitung teilen sich in diesem System der KERNEL und die
Anwendung in Ring 3.  Beide schreiben, wann sie fertig sind, und
gelegentlich schiebt sich eine Kernelzeile mitten in eine
Anwendungszeile:

    wigdemo: state klicks=0 ... sel=wm: go

Ein `sed 's/.*e2=\\[//'` darauf liefert Unsinn, und die Zusage faellt aus
einem Grund, der mit der Sache nichts zu tun hat -- genau das ist in
dieser Runde zweimal passiert.  Also wird hier nach dem VOLLSTAENDIGEN
Muster gesucht -- `e1=[...] e2=[...]` mit beiden schliessenden Klammern
-- und die letzte Zeile genommen, die es enthaelt.

Rueckgabe 0 und der Inhalt auf der Ausgabe; 1, wenn keine einzige
vollstaendige Zeile im Mitschnitt steht (dann hat die Anwendung nichts
gemeldet, und DAS ist ein Befund).
"""
import re
import sys

PAT = re.compile(r"e1=\[([^\]]*)\] e2=\[([^\]]*)\]")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    welches = sys.argv[2]
    treffer = None
    with open(sys.argv[1], "rb") as f:
        for roh in f:
            m = PAT.search(roh.decode("latin-1"))
            if m:
                treffer = m
    if treffer is None:
        return 1
    print(treffer.group(1) if welches == "e1" else treffer.group(2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
