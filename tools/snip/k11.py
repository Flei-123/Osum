#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/snip/k11.py -- DIE SKALARE EINES BLOCKS VON kstate.fi, PAARWEISE.
#
# WARUM ES DIESES SKRIPT GIBT. Runde SNIP suchte in `kstate.K11_OFF` ein
# freies Wort fuer `HK_MOD` und fand 0xB8 -- und erkannte es als
# AN_PAR[7] wieder. `AN_PAR` sind acht Woerter ab 0x80 und lagen damit
# auf KB_LAYOUT, KB_SWITCH, KB_SUPER, HK_SEQ, HK_KEY und HK_NS. Eine
# Farbfolge `ESC [ 1 ; 31 m` schrieb die Tastaturbelegung um.
#
# Das ist derselbe Fehler, den `tools/paint/scalars.py` in `kernel/wm.fi`
# gefunden hat (S_TILE und S_DECO auf 0x180), nur eine Datei weiter:
# zwei Runden, jede fuer sich gruen, keine gemeinsame ZEILE, nur eine
# gemeinsame ADRESSE. Ein Textverschmelzer sieht das nie.
#
# `scalars.py` kann diese Datei nicht pruefen: es gruppiert nach DATEI
# und nimmt an, eine Datei habe EINEN Skalarblock. `kstate.fi` hat
# dreissig, und die Zugehoerigkeit steht im PRAEFIX des Namens, nicht in
# der Datei. Also steht sie hier, mit der Zuordnung als Tabelle.
#
#   ./tools/snip/k11.py [kstate.fi]
#
# Beendigungscode 0 = keine Ueberschneidung.
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))

# Welche Praefixe in WELCHEM Block liegen. Die Zuordnung stammt aus den
# Aufrufstellen (`kstate.<BLOCK>_OFF + kstate.<NAME>`) und ist mit
# `grep` nachpruefbar -- der Testlaeufer tut genau das.
BLOECKE = {
    "K11_OFF": ("KB_", "HK_", "AN_", "ENV_"),
}

# Woerter, die KEINE Adresse sind, sondern ein Wert oder eine Anzahl.
# Sie stehen aus Gruenden der Nachbarschaft im selben Abschnitt und
# duerfen deshalb nicht als Versatz gelesen werden.
KEINE_ADRESSE = {
    "AN_MAXPAR", "ENV_MAX", "KB_HOTS",
    "HK_M_SHIFT", "HK_M_CTRL", "HK_M_ALT", "HK_TAP",
}

# Wie viele Oktette ein Eintrag belegt, wo es nicht acht sind. Die Zahl
# kommt aus dem Kommentar hinter der Zeile, wenn er sie nennt; diese
# Tabelle traegt die Faelle, wo er es nicht tut.
LAENGE = {
    "AN_PAR": 8 * 8,   # AN_MAXPAR Zahlen zu acht Oktetten
    "KB_HOT": 16 * 2,  # 16 Plaetze zu zwei Oktetten
    "ENV_BUF": 3584,   # ENV_MAX
}

ZEILE = re.compile(
    r"^const\s+([A-Z][A-Z0-9_]*)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*(//.*)?$")
AUS_KOMMENTAR = re.compile(r"(\d+)\s+(Woerter|Oktette|Plaetze)")


def laenge_von(name, kommentar):
    if name in LAENGE:
        return LAENGE[name]
    if kommentar:
        m = AUS_KOMMENTAR.search(kommentar)
        if m:
            n = int(m.group(1))
            return n * 8 if m.group(2) == "Woerter" else n
    return 8


def lies(pfad):
    eintraege = []
    with open(pfad, encoding="utf-8", errors="replace") as f:
        for nr, zeile in enumerate(f, 1):
            m = ZEILE.match(zeile.strip())
            if not m:
                continue
            name, wert, kom = m.group(1), m.group(2), m.group(3)
            if name in KEINE_ADRESSE:
                continue
            for block, praefixe in BLOECKE.items():
                if any(name.startswith(p) for p in praefixe):
                    off = int(wert, 0)
                    eintraege.append(
                        (block, name, off, laenge_von(name, kom), nr))
                    break
    return eintraege


def main():
    pfad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        WURZEL, "kernel", "kstate.fi")
    eintraege = lies(pfad)
    schlecht = 0
    for block in sorted(BLOECKE):
        drin = [e for e in eintraege if e[0] == block]
        drin.sort(key=lambda e: e[2])
        if not drin:
            print("  FEHLER %s: kein einziges Wort gefunden -- das Muster "
                  "passt nicht mehr" % block)
            return 1
        for i in range(len(drin)):
            for k in range(i + 1, len(drin)):
                _, n1, o1, l1, z1 = drin[i]
                _, n2, o2, l2, z2 = drin[k]
                if o1 + l1 > o2:
                    print("  FEHLER %s: %s (0x%X, %d Oktette, Zeile %d) und "
                          "%s (0x%X, Zeile %d) liegen aufeinander"
                          % (block, n1, o1, l1, z1, n2, o2, z2))
                    schlecht += 1
        print("SNIP-K11: %s -- %d Woerter, 0x%X..0x%X belegt"
              % (block, len(drin), drin[0][2],
                 max(e[2] + e[3] for e in drin)))
    if schlecht:
        print("  FEHLER %d Ueberschneidungen" % schlecht)
        return 1
    print("  OK    keine zwei Woerter des Blocks liegen aufeinander")
    return 0


if __name__ == "__main__":
    sys.exit(main())
