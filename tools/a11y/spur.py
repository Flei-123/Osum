#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/spur.py -- DURCHTABBEN UND ZAEHLEN.

    spur.py <mitschnitt>

Liest die letzte Zeile `a11ydemo: spur n=.. fokus=.. [ .. ]` und gibt

    erreicht=<verschiedene Nummern>  fokus=<fokussierbare Elemente>  n=<Wechsel>

aus.  Der Testlaeufer verlangt `erreicht == fokus`: JEDES fokussierbare
Bedienelement wurde durch Tabulator wirklich erreicht.  Das ist der
ehrliche Test -- eine Behauptung "alles ist per Tastatur bedienbar"
ohne diese beiden Zahlen ist keine.
"""
import re
import sys


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    letzte = None
    with open(sys.argv[1], "rb") as f:
        for zeile in f.read().split(b"\n"):
            if b"a11ydemo: spur" in zeile:
                letzte = zeile.decode("latin-1")
    if letzte is None:
        print("erreicht=0 fokus=0 n=0")
        return 1
    m = re.search(r"n=(\d+)\s+fokus=(\d+)\s+\[([^\]]*)\]", letzte)
    if not m:
        print("erreicht=0 fokus=0 n=0")
        return 1
    n, fokus, folge = int(m.group(1)), int(m.group(2)), m.group(3).split()
    print("erreicht=%d fokus=%d n=%d" % (len(set(folge)), fokus, n))
    return 0


sys.exit(main())
