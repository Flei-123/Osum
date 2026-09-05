#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alltag/pad.py -- DIE LAENGE EINER TEXTKONSTANTE AUSRECHNEN.

Firn verlangt, dass ein `static`/`var` mit Feldtyp `[u8; N]` GENAU N
Zeichen bekommt, das abschliessende Null-Oktett eingerechnet:

    static mut t: [u8; 12] = "Löschen\0\0\0\0"

Das ist richtig so -- der Anfangswert steht im Objektcode, es gibt
niemanden, der ihn vorher ausrechnen koennte. Nur zaehlt ein Mensch
Umlaute falsch (Ö sind ZWEI Oktette), und ein falsch gezaehlter Puffer
ist ein Fehler, der erst im Bild auffaellt.

Also wird die Laenge hier ausgerechnet. Wer eine Zeile

    static mut t: [u8; ?] = "Löschen"

schreibt, bekommt daraus

    static mut t: [u8; 9] = "Löschen\0"

Das Fragezeichen ist die Bitte um Nachrechnen; eine Zeile mit einer
ZAHL wird nicht angefasst, damit Puffer, die absichtlich groesser sind
als ihr Anfangswert, groesser bleiben.

    python3 tools/alltag/pad.py <datei> [...]

Laeuft mehrfach ohne Schaden: nach dem ersten Lauf steht dort eine Zahl.
"""
import re
import sys

ZEILE = re.compile(
    r'^(?P<kopf>\s*(?:static\s+mut|static|var|let)\s+[A-Za-z_][A-Za-z_0-9]*'
    r'\s*:\s*\[u8;\s*)\?(?P<mitte>\s*\]\s*=\s*)"(?P<text>(?:[^"\\]|\\.)*)"'
    r'(?P<rest>.*)$'
)

ESCAPES = {"0": "\0", "n": "\n", "t": "\t", "r": "\r",
           "\\": "\\", '"': '"', "'": "'"}


def oktette(roh: str) -> bytes:
    out = bytearray()
    i = 0
    while i < len(roh):
        c = roh[i]
        if c == "\\" and i + 1 < len(roh):
            n = roh[i + 1]
            if n in ESCAPES:
                out += ESCAPES[n].encode("utf-8")
                i += 2
                continue
            if n == "x" and i + 3 < len(roh):
                out.append(int(roh[i + 2:i + 4], 16))
                i += 4
                continue
        out += c.encode("utf-8")
        i += 1
    return bytes(out)


def datei(pfad: str) -> int:
    alt = open(pfad, "r", encoding="utf-8").read()
    aus = []
    n = 0
    for zeile in alt.split("\n"):
        m = ZEILE.match(zeile)
        if not m:
            aus.append(zeile)
            continue
        text = m.group("text")
        laenge = len(oktette(text)) + 1
        aus.append('%s%d%s"%s\\0"%s' % (m.group("kopf"), laenge,
                                        m.group("mitte"), text,
                                        m.group("rest")))
        n += 1
    open(pfad, "w", encoding="utf-8").write("\n".join(aus))
    return n


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for p in sys.argv[1:]:
        print("pad.py: %s: %d Textkonstanten nachgerechnet" % (p, datei(p)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
