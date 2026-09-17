#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/ablage.py -- LIEGT JEDE DATEI, WO SIE LIEGEN SOLL?
#
# Liest `tools/struktur/ablage.txt` (Soll) und den Baum (Ist) und
# vergleicht beides. Das ist die zweite Haelfte der Ordnung: die
# Aufrufrichtung prueft `erhebung.py`, die tatsaechliche Ablage diese
# Datei.
#
# Aufruf:
#   python3 tools/struktur/ablage.py             # Uebersicht
#   python3 tools/struktur/ablage.py --pruefen   # Code 1 bei Abweichung
#   python3 tools/struktur/ablage.py --offen     # was noch umzuziehen ist
#   python3 tools/struktur/ablage.py --fehlend   # Module ohne Soll-Eintrag

import os
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(WURZEL, "kernel")
SOLLDATEI = os.path.join(WURZEL, "tools", "struktur", "ablage.txt")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import lies  # noqa: E402
import huelle  # noqa: E402


def lies_soll():
    """modul -> Sollverzeichnis (relativ zu kernel/, '.' = oben)."""
    soll = {}
    if not os.path.exists(SOLLDATEI):
        return soll
    for z in lies(SOLLDATEI).splitlines():
        z = z.strip()
        if not z or z.startswith("#"):
            continue
        t = z.split()
        if len(t) == 2:
            soll[t[1]] = t[0]
    return soll


def ist_ablage():
    """modul -> Istverzeichnis, nur fuer die Dateien des Kernabbilds.

    `kernel/user/` und `kernel/app/` sind eigene Programme und werden
    nicht betrachtet -- sonst zaehlte man `netmon` doppelt."""
    kern = huelle.huelle(os.path.join(KERN, "kmain.fi"))
    kern |= huelle.huelle(os.path.join(KERN, "uprog.fi"))
    ist = {}
    for rel in kern:
        d = os.path.dirname(rel)
        ist[os.path.basename(rel)[:-3]] = d if d else "."
    return ist


def alle_dateien():
    """Jede .fi im Kernbaum, unabhaengig von der Erreichbarkeit --
    ohne user/ und app/. Braucht man, um eine Datei zu bemerken, die
    am falschen Ort liegt UND deshalb gar nicht mehr erreicht wird."""
    aus = {}
    for stamm, verz, namen in os.walk(KERN):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        for n in namen:
            if n.endswith(".fi"):
                rel = os.path.relpath(os.path.join(stamm, n), KERN)
                d = os.path.dirname(rel)
                aus[n[:-3]] = d if d else "."
    return aus


def vergleiche():
    soll = lies_soll()
    ist = ist_ablage()
    # Eine Datei, die am falschen Ort liegt, faellt aus der Huelle
    # heraus (ihr import zeigt ins Leere) -- sie waere sonst unsichtbar.
    # Darum wird der Baum ZUSAETZLICH flach gelesen.
    flach = alle_dateien()
    for m, d in flach.items():
        if m in soll and m not in ist:
            ist[m] = d
    passt, falsch, ohne_soll, fehlt = [], [], [], []
    for m, d in sorted(ist.items()):
        s = soll.get(m)
        if s is None:
            ohne_soll.append((m, d))
        elif s == d:
            passt.append((m, d))
        else:
            falsch.append((m, d, s))
    # Und was im Soll steht, aber nirgends liegt, ist ein Verlust.
    for m in sorted(soll):
        if m not in ist and m not in flach:
            fehlt.append(m)
    return passt, falsch, ohne_soll, soll, ist, fehlt


def main():
    modus = sys.argv[1] if len(sys.argv) > 1 else ""
    passt, falsch, ohne_soll, soll, ist, fehlt = vergleiche()

    if modus == "--fehlend":
        for m, d in ohne_soll:
            print("%s (liegt in %s)" % (m, d))
        return 0

    if modus == "--offen":
        for m, d, s in falsch:
            print("%s %s %s" % (m, d, s))
        return 0

    if modus == "--pruefen":
        if not soll:
            print("KEINE Soll-Ablage (tools/struktur/ablage.txt) -- nichts geprueft")
            return 1
        print("Ablage: %d Dateien am richtigen Ort, %d am falschen, "
              "%d ohne Soll, %d vermisst"
              % (len(passt), len(falsch), len(ohne_soll), len(fehlt)))
        for m, d, s in falsch:
            print("  FALSCH  %s liegt in '%s', soll nach '%s'" % (m, d, s))
        for m, d in ohne_soll:
            print("  OHNE SOLL  %s (liegt in '%s')" % (m, d))
        for m in fehlt:
            print("  VERMISST  %s steht im Soll, liegt aber nirgends" % m)
        return 1 if (falsch or ohne_soll or fehlt) else 0

    print("== ABLAGE ==")
    print("Soll-Eintraege: %d, Kerndateien: %d" % (len(soll), len(ist)))
    print("am richtigen Ort: %d" % len(passt))
    print("am falschen Ort : %d" % len(falsch))
    print("ohne Soll       : %d" % len(ohne_soll))
    print()
    nach = {}
    for m, d in ist.items():
        nach[d] = nach.get(d, 0) + 1
    print("-- Ist-Verteilung --")
    for d, c in sorted(nach.items(), key=lambda kv: (-kv[1], kv[0])):
        print("  %-12s %3d" % (d, c))
    if falsch:
        print()
        print("-- noch umzuziehen --")
        for m, d, s in falsch:
            print("  %-12s %s -> %s" % (m, d, s))
    if ohne_soll:
        print()
        print("-- ohne Soll-Eintrag --")
        for m, d in ohne_soll:
            print("  %-12s (%s)" % (m, d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
