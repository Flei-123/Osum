#!/usr/bin/env python3
"""tools/speicher/strlit.py -- die Zeichenkettenliterale einer Firn-Datei
auf ihre angegebene Laenge bringen.

WARUM ES DAS GIBT. Firn hat keine Zeichenkettenklasse: ein Text ist ein
Feld aus Oktetten mit fester Laenge, und die Laenge steht daneben --
`var s: [u8; 12] = "hallo\\0\\0\\0\\0\\0\\0\\0"`. Stimmt sie nicht auf das Oktett,
uebersetzt die Datei nicht ("array literal has 11 elements, 12 are
expected"). Das ist richtig so und es ist beim Schreiben laestig: wer
einen Text um ein Zeichen aendert, muss die Nullen nachzaehlen.

Dieses Werkzeug zaehlt sie. Es liest eine `.fi`-Datei, sucht jede Zeile
der Form `var <name>: [u8; N] = "<text>"` und fuellt den Text mit `\\0`
auf genau N Oktette auf -- oder meldet, dass er laenger ist als N und
deshalb NICHT stillschweigend abgeschnitten wird. Abschneiden waere die
schlimmere Hilfe: ein Text ohne abschliessende Null laeuft in den
naechsten hinein.

    python3 tools/speicher/strlit.py <datei.fi> [--pruefen]
"""
import re
import sys

MUSTER = re.compile(
    r'^(\s*(?:var|static mut)\s+\w+\s*:\s*\[u8;\s*(\d+)\s*\]\s*=\s*)"(.*)"(\s*)$'
)


def oktette(lit):
    """Wie viele Oktette dieses Literal wirklich hat."""
    n = 0
    i = 0
    while i < len(lit):
        if lit[i] == '\\':
            i += 2
        else:
            i += 1
        n += 1
    return n


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    pfad = argv[1]
    nur_pruefen = "--pruefen" in argv
    zeilen = open(pfad, encoding="utf-8").read().split("\n")
    aus = []
    geaendert = 0
    zu_lang = []
    for nr, z in enumerate(zeilen, 1):
        m = MUSTER.match(z)
        if not m:
            aus.append(z)
            continue
        kopf, will, lit, schwanz = (m.group(1), int(m.group(2)),
                                    m.group(3), m.group(4))
        ist = oktette(lit)
        if ist > will:
            zu_lang.append((nr, ist, will, lit))
            aus.append(z)
            continue
        if ist == will:
            aus.append(z)
            continue
        aus.append('%s"%s"%s' % (kopf, lit + "\\0" * (will - ist), schwanz))
        geaendert += 1
    for nr, ist, will, lit in zu_lang:
        print("%s:%d: %d Oktette, aber [u8; %d] -- zu lang: %s"
              % (pfad, nr, ist, will, lit), file=sys.stderr)
    if zu_lang:
        return 1
    if geaendert and not nur_pruefen:
        open(pfad, "w", encoding="utf-8").write("\n".join(aus))
    print("%s: %d Literale aufgefuellt" % (pfad, geaendert))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
