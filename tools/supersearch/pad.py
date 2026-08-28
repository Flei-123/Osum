#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/supersearch/pad.py -- EIN ZEICHENKETTENFELD IST SO LANG WIE SEIN
INHALT, und nicht so lang, wie jemand gezaehlt hat.

    pad.py --pruefe <datei.fi> ...    nur nachrechnen, nichts aendern
    pad.py --setze  <datei.fi> ...    `[u8; 0]` durch die richtige Zahl
                                      ersetzen und mit Nullen auffuellen

In Firn ist ein Zeichenkettenliteral ein Feld fester Laenge: steht dort
`[u8; 12]`, muessen genau zwoelf Oktette folgen, Nullen eingerechnet.
Beim Schreiben zaehlt man das von Hand, und beim Aendern eines Textes
zaehlt man es NICHT neu -- der Uebersetzer sagt es dann, aber erst nach
dem naechsten Bau, und bei einem Text mit einem Umlaut darin zaehlt man
ohnehin falsch (ein Umlaut sind zwei Oktette).

Dieses Werkzeug rechnet nach: es zaehlt OKTETTE (UTF-8), nicht Zeichen,
und `\\0` als eines. Mit `--pruefe` laeuft es in der Abnahme mit und
findet ein Feld, dessen Text laenger geworden ist, bevor es jemand
uebersetzt.
"""
import re
import sys

PAT = re.compile(
    r'((?:static mut |var )\s*)([A-Za-z_][A-Za-z0-9_]*): \[u8; (\d+)\] = '
    r'"((?:[^"\\]|\\.)*)"')


def oktette(lit):
    n = 0
    i = 0
    while i < len(lit):
        if lit[i] == "\\" and i + 1 < len(lit):
            n += 1
            i += 2
        else:
            n += len(lit[i].encode("utf-8"))
            i += 1
    return n


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    modus = argv[0]
    schlecht = 0
    geprueft = 0
    for datei in argv[1:]:
        s = open(datei, encoding="utf-8").read()

        def fix(m):
            nonlocal schlecht, geprueft
            geprueft += 1
            n = oktette(m.group(4))
            size = int(m.group(3))
            if modus == "--setze" and size == 0:
                total = n + 1
                if total % 2:
                    total += 1
                return '%s%s: [u8; %d] = "%s%s"' % (
                    m.group(1), m.group(2), total, m.group(4),
                    "\\0" * (total - n))
            if n != size:
                print("%s: %s hat %d Oktette, das Feld ist %d"
                      % (datei, m.group(2), n, size))
                schlecht += 1
            return m.group(0)

        s2 = PAT.sub(fix, s)
        if modus == "--setze" and s2 != s:
            open(datei, "w", encoding="utf-8").write(s2)
    print("pad: %d Felder geprueft, %d falsch" % (geprueft, schlecht))
    return 1 if schlecht else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
