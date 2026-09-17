#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/huelle.py -- WAS IST EIGENTLICH DER KERNEL?
#
# `kernel/` enthaelt 346 .fi-Dateien, aber das Kernabbild besteht nicht
# aus ihnen allen. `tools/build-kernel.sh` uebersetzt ZWEI Wurzeln:
#
#     firnc -o k.o      kernel/kmain.fi
#     firnc -o uprog.o  kernel/uprog.fi
#
# Firn liest von einer Wurzel aus den ganzen Baum ueber `import`. Alles,
# was von keiner der beiden Wurzeln erreichbar ist, liegt zwar im
# Verzeichnis, ist aber NICHT im Abbild -- das sind die Anwendungen
# unter `kernel/user/` (eigene Programme, je mit eigener Wurzel) und
# `kernel/app/`.
#
# Dieses Werkzeug rechnet die Huellen aus und trennt damit die drei
# Mengen, die diese Runde auseinanderhalten MUSS:
#
#   KERN   -- von kmain.fi erreichbar. Nur diese Dateien wandern.
#   UPROG  -- von uprog.fi erreichbar (das eingebettete Ring-3-Programm).
#   AUSSEN -- alles uebrige: Anwendungen, Gegenfassungen (*-aus.fi),
#             Programme unter user/ und app/.
#
# Aufruf: python3 tools/struktur/huelle.py [--liste kern|uprog|aussen]

import os
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(WURZEL, "kernel")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import IMPORT_RE, lies  # noqa: E402


def huelle(wurzeldatei):
    """Folgt `import` von einer Wurzel aus -- mit DERSELBEN Suchordnung
    wie der Uebersetzer: erst neben der importierenden Datei, dann neben
    der Wurzel (modules.rs, Schritte 1 und 2). Liefert Pfade relativ zu
    `kernel/`."""
    basis = os.path.dirname(wurzeldatei)
    gesehen = set()
    stapel = [wurzeldatei]
    while stapel:
        p = stapel.pop()
        rp = os.path.realpath(p)
        if rp in gesehen or not os.path.exists(p):
            continue
        gesehen.add(rp)
        eigen = os.path.dirname(p)
        for z in lies(p).splitlines():
            m = IMPORT_RE.match(z)
            if not m:
                continue
            teile = m.group(1).split(".")
            kand = os.path.join(eigen, *teile) + ".fi"
            if not os.path.exists(kand):
                kand = os.path.join(basis, *teile) + ".fi"
            if os.path.exists(kand):
                stapel.append(kand)
    return {os.path.relpath(p, KERN) for p in gesehen}


def main():
    kern = huelle(os.path.join(KERN, "kmain.fi"))
    uprog = huelle(os.path.join(KERN, "uprog.fi"))
    alle = set()
    for stamm, _, namen in os.walk(KERN):
        for n in namen:
            if n.endswith(".fi"):
                alle.add(os.path.relpath(os.path.join(stamm, n), KERN))
    aussen = alle - kern - uprog

    if len(sys.argv) > 2 and sys.argv[1] == "--liste":
        menge = {"kern": kern, "uprog": uprog, "aussen": aussen}[sys.argv[2]]
        for p in sorted(menge):
            print(p)
        return 0

    def zeilen(menge):
        s = 0
        for p in menge:
            s += lies(os.path.join(KERN, p)).count("\n")
        return s

    print("Dateien unter kernel/ gesamt : %3d  (%d Zeilen)" % (len(alle), zeilen(alle)))
    print("  KERN  (ab kmain.fi)        : %3d  (%d Zeilen)" % (len(kern), zeilen(kern)))
    print("  UPROG (ab uprog.fi)        : %3d  (%d Zeilen)" % (len(uprog), zeilen(uprog)))
    print("  AUSSEN (nicht im Abbild)   : %3d  (%d Zeilen)" % (len(aussen), zeilen(aussen)))
    print()
    print("AUSSEN nach Ordner:")
    nach = {}
    for p in aussen:
        d = os.path.dirname(p) or "(kernel/)"
        nach[d] = nach.get(d, 0) + 1
    for d, c in sorted(nach.items(), key=lambda kv: -kv[1]):
        print("  %-12s %3d" % (d, c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
