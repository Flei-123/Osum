#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/sync/strfix.py -- die Groesse eines Zeichenkettenfeldes ausrechnen,
statt sie zu zaehlen.

In Firn muss bei

    var t: [u8; N] = "text\\0"

das N GENAU der Zahl der Oktette entsprechen. Beim Schreiben von
Meldungstexten ist das eine Fehlerquelle ohne jeden Erkenntniswert: der
Uebersetzer sagt zwar, wieviele es sind, aber jedes Nachbessern von Hand
ist eine Gelegenheit, eine andere Zeile kaputtzumachen.

Dieses Skript setzt N auf den richtigen Wert. Es fasst NUR Zeilen an,
die genau dieser Form entsprechen, und laesst alles andere in Ruhe.

    python3 tools/sync/strfix.py <datei> [...]
"""
import re
import sys

MUSTER = re.compile(r'^(\s*(?:var|let|static mut)\s+\w+\s*:\s*\[u8;\s*)(\d+)(\s*\]\s*=\s*)"(.*)"\s*$')


def oktette(s):
    """Die Zahl der Oktette, die Firn aus diesem Literal macht."""
    n = 0
    i = 0
    roh = s
    while i < len(roh):
        if roh[i] == "\\":
            i += 2
            n += 1
        else:
            n += len(roh[i].encode("utf-8"))
            i += 1
    return n


def eine(pfad):
    aus = []
    geaendert = 0
    for zeile in open(pfad, encoding="utf-8").read().split("\n"):
        m = MUSTER.match(zeile)
        if m:
            soll = oktette(m.group(4))
            if int(m.group(2)) != soll:
                zeile = '%s%d%s"%s"' % (m.group(1), soll, m.group(3), m.group(4))
                geaendert += 1
        aus.append(zeile)
    open(pfad, "w", encoding="utf-8").write("\n".join(aus))
    return geaendert


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print("%s: %d Groessen berichtigt" % (p, eine(p)))
