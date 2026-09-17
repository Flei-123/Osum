#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/pfadnennungen.py -- WELCHE PFADNENNUNG TUT WEH?
#
# `grep -c "kernel/sys.fi" tools/` zaehlt 88 Treffer. Die allermeisten
# stehen in KOMMENTAREN ("siehe kernel/sys.fi") und tun beim
# Verschieben gar nichts -- sie werden nur ungenau. Was wirklich
# bricht, ist die Nennung in AUSFUEHRBAREM Code: ein `grep`, ein `sed`,
# ein `cp`, ein Dateiname in einer Python-Liste.
#
# Dieses Werkzeug trennt beides, damit die Entscheidung "verschieben
# oder liegenlassen" auf der richtigen Zahl steht.
#
# REGEL: eine Zeile gilt als AUSFUEHRBAR, wenn sie nicht mit einem
# Kommentarzeichen beginnt (# in sh/py, // in Firn) und der Pfad nicht
# nur in einer Zeichenkette eines Kommentars steht. Das ist bewusst
# grob in Richtung "lieber zu viel melden als zu wenig".
#
# Aufruf:
#   python3 tools/struktur/pfadnennungen.py            # Uebersicht
#   python3 tools/struktur/pfadnennungen.py <modul>    # Fundstellen

import os
import re
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def kernmodule():
    """Alle Module, die vom Abbild erreicht werden."""
    sys.path.insert(0, os.path.join(WURZEL, "tools", "struktur"))
    import huelle
    kern = huelle.huelle(os.path.join(WURZEL, "kernel", "kmain.fi"))
    return {os.path.basename(p)[:-3] for p in kern}


def durchsuche():
    """Liefert modul -> (ausfuehrbar, kommentar) als Listen von
    (datei, zeilennr, text)."""
    ziele = {}
    for stamm, verz, namen in os.walk(WURZEL):
        verz[:] = [d for d in verz if d not in (".git", "kernel", "docs", "vendor")]
        for n in namen:
            if not n.endswith((".sh", ".py", ".yml", ".yaml", ".mk")) and n != "Makefile":
                continue
            p = os.path.join(stamm, n)
            rel = os.path.relpath(p, WURZEL)
            try:
                with open(p, "rb") as f:
                    txt = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            for i, z in enumerate(txt.splitlines(), 1):
                for m in re.finditer(r"kernel/([a-z0-9_]+)\.fi", z):
                    mod = m.group(1)
                    nackt = z.strip()
                    ist_komm = nackt.startswith("#") or nackt.startswith("//")
                    ziele.setdefault(mod, ([], []))[0 if not ist_komm else 1].append(
                        (rel, i, nackt[:100])
                    )
    return ziele


def main():
    ziele = durchsuche()
    kern = kernmodule()
    if len(sys.argv) > 1:
        mod = sys.argv[1]
        aus, kom = ziele.get(mod, ([], []))
        print("== %s: %d ausfuehrbar, %d in Kommentaren ==" % (mod, len(aus), len(kom)))
        for d, i, t in aus:
            print("  AUSFUEHRBAR %s:%d  %s" % (d, i, t))
        return 0

    frei, teuer = [], []
    for mod in sorted(kern):
        aus, kom = ziele.get(mod, ([], []))
        (teuer if aus else frei).append((mod, len(aus), len(kom)))

    print("== Pfadnennungen der %d Kernmodule ==" % len(kern))
    print()
    print("FREI verschiebbar (keine ausfuehrbare Nennung): %d" % len(frei))
    print("  " + " ".join(m for m, _, _ in frei))
    print()
    print("TEUER (ausfuehrbare Nennung): %d" % len(teuer))
    for m, a, k in sorted(teuer, key=lambda x: -x[1]):
        print("  %-12s %2d ausfuehrbar, %3d Kommentar" % (m, a, k))
    return 0


if __name__ == "__main__":
    sys.exit(main())
