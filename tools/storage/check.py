#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/storage/check.py -- die DRITTE Zahl.

Runde SPEICHER. Im Gast stehen zwei Zahlen gegeneinander: die des Index
(sofort) und die des vollstaendigen Durchlaufs (langsam). Stimmen sie
ueberein, ist das ein gutes Zeichen und mehr nicht -- beide kommen aus
derselben Datei (`kernel/user/nidx.fi`), beide lesen dieselben Inodes
ueber dieselben Systemaufrufe, und ein Denkfehler in der Regel, WAS
eigentlich gezaehlt wird ("zaehlt ein Verzeichnis seine eigene
Eintragstabelle mit?"), stuende in beiden gleich falsch drin.

Deshalb rechnet `tools/storage/tree.py` auf dem WIRT aus der Liste, aus
der das Abbild gebaut wurde, dieselben Summen noch einmal -- in Python,
von einem anderen Programm, ohne Kenntnis des Kernels. Diese Datei haelt
die drei Zahlen nebeneinander. Erst wenn ALLE DREI auf dasselbe Oktett
kommen, ist die Zusage der Runde eingeloest.

WAS NICHT VERGLICHEN WIRD, UND WARUM: die Wurzel `/`. Im Abbild liegen
neben `/data` auch `/bin`, `/lib` und `/etc` -- Programme und
Schriften, die `baum.py` nicht kennt, weil `bauen.sh` sie dazulegt. Fuer
`/` bleibt deshalb nur der Vergleich Index gegen Durchlauf; ab `/data`
abwaerts gilt die volle Probe zu dritt.

    check.py <soll-datei> <serielle-ausgabe> [...weitere Ausgaben]
"""

import re
import sys

PROBE = re.compile(
    r"du: probe pfad=(\S+)\s+idx=(\d+)\s+lauf=(\d+)\s+idxkb=(\d+)\s+"
    r"laufkb=(\d+)\s+ok=(\d+)")
FERTIG = re.compile(r"du: probe done checked=(\d+)\s+falsch=(\d+)")
MEASURE = re.compile(r"du: (index|durchlauf) \[(\S+)\] okt=(\d+) kb=(\d+)")


def soll_read(path_2):
    aus = {}
    with open(path_2) as f:
        for line in f:
            t = line.split()
            if len(t) >= 3:
                aus[t[0]] = (int(t[1]), int(t[2]))
    return aus


def text(path_2):
    with open(path_2, "rb") as f:
        return f.read().decode("latin-1")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    soll = soll_read(argv[1])
    roh = "\n".join(text(p) for p in argv[2:])

    geprueft = 0
    wrong = 0
    without_soll = 0
    dritt = 0
    zeilen = []

    for m in PROBE.finditer(roh):
        path_2, idx, run_2, ikb, lkb, ok = m.group(1), int(m.group(2)), \
            int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6))
        geprueft += 1
        gut = idx == run_2 and ikb == lkb and ok == 1
        s = soll.get(path_2)
        anmerkung = ""
        if path_2 == "/":
            anmerkung = "(Wurzel: nur Index gegen Durchlauf, s. Kopf)"
            without_soll += 1
        elif s is None:
            anmerkung = "(kein Sollwert)"
            without_soll += 1
        else:
            dritt += 1
            if idx != s[0] or ikb != s[1]:
                gut = False
                anmerkung = "WIRT SAGT okt=%d kb=%d" % s
        if not gut:
            wrong += 1
        zeilen.append("  %-24s idx=%-8d lauf=%-8d kb=%-6d %s %s"
                      % (path_2, idx, run_2, ikb, "OK " if gut else "FALSCH",
                         anmerkung))

    print("check: %d directories from the guest, of which %d also against the "
          "Arithmetik des Wirts" % (geprueft, dritt))
    for z in zeilen:
        print(z)

    for m in FERTIG.finditer(roh):
        g, f = int(m.group(1)), int(m.group(2))
        print("check: the guest says checked=%d wrong=%d" % (g, f))
        if f != 0:
            wrong += f
        if g != geprueft:
            print("check: NOTE -- the guest counts %d probes, here "
                  "kommen %d an" % (g, geprueft))
            wrong += 1

    if geprueft == 0:
        print("check: NOT A SINGLE PROBE in the output -- the run is "
              "nicht durchgekommen")
        return 1
    if dritt == 0:
        print("check: no probe against the host -- the expected values fit "
              "zu keinem Pfad")
        return 1
    if wrong:
        print("pruefen: %d FALSCH" % wrong)
        return 1
    print("check: all %d directories identical octet for octet "
          "(Index = Durchlauf = Wirt)" % geprueft)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
