#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/speicher/pruefen.py -- die DRITTE Zahl.

Runde SPEICHER. Im Gast stehen zwei Zahlen gegeneinander: die des Index
(sofort) und die des vollstaendigen Durchlaufs (langsam). Stimmen sie
ueberein, ist das ein gutes Zeichen und mehr nicht -- beide kommen aus
derselben Datei (`kernel/user/nidx.fi`), beide lesen dieselben Inodes
ueber dieselben Systemaufrufe, und ein Denkfehler in der Regel, WAS
eigentlich gezaehlt wird ("zaehlt ein Verzeichnis seine eigene
Eintragstabelle mit?"), stuende in beiden gleich falsch drin.

Deshalb rechnet `tools/speicher/tree.py` auf dem WIRT aus der Liste, aus
der das Abbild gebaut wurde, dieselben Summen noch einmal -- in Python,
von einem anderen Programm, ohne Kenntnis des Kernels. Diese Datei haelt
die drei Zahlen nebeneinander. Erst wenn ALLE DREI auf dasselbe Oktett
kommen, ist die Zusage der Runde eingeloest.

WAS NICHT VERGLICHEN WIRD, UND WARUM: die Wurzel `/`. Im Abbild liegen
neben `/data` auch `/bin`, `/lib` und `/etc` -- Programme und
Schriften, die `baum.py` nicht kennt, weil `bauen.sh` sie dazulegt. Fuer
`/` bleibt deshalb nur der Vergleich Index gegen Durchlauf; ab `/data`
abwaerts gilt die volle Probe zu dritt.

    pruefen.py <soll-datei> <serielle-ausgabe> [...weitere Ausgaben]
"""

import re
import sys

# du: probe pfad=/data idx=419868 lauf=419868 idxkb=686 laufkb=686 ok=1
# ZWISCHENRAUM IST \s+ UND NICHT " ". Der Gast trennt seine Felder mit
# einem oder zwei Leerzeichen -- `kv()` schreibt eines, und manche
# Zeichenkette traegt selbst schon eines. Die erste Fassung dieser
# Datei stand auf EINEM Leerzeichen und fand daraufhin keine einzige
# Probe; sie meldete "der Lauf ist nicht durchgekommen", waehrend in
# der Ausgabe einundzwanzig richtige Zeilen standen.
PROBE = re.compile(
    r"du: probe pfad=(\S+)\s+idx=(\d+)\s+lauf=(\d+)\s+idxkb=(\d+)\s+"
    r"laufkb=(\d+)\s+ok=(\d+)")
FERTIG = re.compile(r"du: probe fertig geprueft=(\d+)\s+falsch=(\d+)")
# du: index [/data] okt=419868 kb=686  us10=158
MESS = re.compile(r"du: (index|durchlauf) \[(\S+)\] okt=(\d+) kb=(\d+)")


def soll_lesen(pfad):
    aus = {}
    with open(pfad) as f:
        for zeile in f:
            t = zeile.split()
            if len(t) >= 3:
                aus[t[0]] = (int(t[1]), int(t[2]))
    return aus


def text(pfad):
    with open(pfad, "rb") as f:
        return f.read().decode("latin-1")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    soll = soll_lesen(argv[1])
    roh = "\n".join(text(p) for p in argv[2:])

    geprueft = 0
    falsch = 0
    ohne_soll = 0
    dritt = 0
    zeilen = []

    for m in PROBE.finditer(roh):
        pfad, idx, lauf, ikb, lkb, ok = m.group(1), int(m.group(2)), \
            int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6))
        geprueft += 1
        gut = idx == lauf and ikb == lkb and ok == 1
        s = soll.get(pfad)
        anmerkung = ""
        if pfad == "/":
            anmerkung = "(Wurzel: nur Index gegen Durchlauf, s. Kopf)"
            ohne_soll += 1
        elif s is None:
            anmerkung = "(kein Sollwert)"
            ohne_soll += 1
        else:
            dritt += 1
            if idx != s[0] or ikb != s[1]:
                gut = False
                anmerkung = "WIRT SAGT okt=%d kb=%d" % s
        if not gut:
            falsch += 1
        zeilen.append("  %-24s idx=%-8d lauf=%-8d kb=%-6d %s %s"
                      % (pfad, idx, lauf, ikb, "OK " if gut else "FALSCH",
                         anmerkung))

    print("pruefen: %d Verzeichnisse aus dem Gast, davon %d auch gegen die "
          "Arithmetik des Wirts" % (geprueft, dritt))
    for z in zeilen:
        print(z)

    # Die Zusammenfassung, die der Gast selbst gezogen hat -- sie muss zu
    # dem passen, was hier herauskommt. Zwei Zaehler, die sich
    # widersprechen, sind selbst ein Fund.
    for m in FERTIG.finditer(roh):
        g, f = int(m.group(1)), int(m.group(2))
        print("pruefen: der Gast sagt geprueft=%d falsch=%d" % (g, f))
        if f != 0:
            falsch += f
        if g != geprueft:
            print("pruefen: ACHTUNG -- der Gast zaehlt %d Proben, hier "
                  "kommen %d an" % (g, geprueft))
            falsch += 1

    if geprueft == 0:
        print("pruefen: KEINE EINZIGE PROBE in der Ausgabe -- der Lauf ist "
              "nicht durchgekommen")
        return 1
    if dritt == 0:
        print("pruefen: keine Probe gegen den Wirt -- die Sollwerte passen "
              "zu keinem Pfad")
        return 1
    if falsch:
        print("pruefen: %d FALSCH" % falsch)
        return 1
    print("pruefen: alle %d Verzeichnisse Oktett fuer Oktett gleich "
          "(Index = Durchlauf = Wirt)" % geprueft)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
