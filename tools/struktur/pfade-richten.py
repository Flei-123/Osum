#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/pfade-richten.py -- tote Pfade in den Werkzeugen
# auf den neuen Ort umbiegen.
#
# Nach dem raeumlichen Umbau nennen ueber neunzig Testlaeufer noch
# `kernel/kstate.fi`, obwohl die Datei `kernel/lib/kstate.fi` heisst.
# Das bricht den Bau NICHT -- es bricht die Messung: ein `grep` findet
# nichts, und der Laeufer wird rot oder, schlimmer, misst still eine
# falsche Zahl.
#
# Dieses Werkzeug ersetzt `kernel/<name>.fi` durch den Ort, an dem die
# Datei WIRKLICH liegt.
#
# ZWEI REGELN, die es vorsichtig machen:
#
#   1. NUR AUSFUEHRBARE ZEILEN. Eine Kommentarzeile ("siehe
#      kernel/fs.fi") wird nicht angefasst -- sie bricht nichts, und
#      ein Kommentar ueber eine Datei darf auch ihren alten Ort
#      nennen, wenn er von damals erzaehlt.
#   2. NUR, WENN DER ALTE PFAD WIRKLICH TOT IST. Existiert
#      `kernel/<name>.fi` noch (weil die Datei liegen blieb, wie die
#      Netzdateien), bleibt die Zeile unberuehrt.
#
#   python3 tools/struktur/pfade-richten.py --trocken
#   python3 tools/struktur/pfade-richten.py

import os
import re
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MUSTER = re.compile(r"kernel/([a-z0-9_]+)\.fi")


def ort_von(name):
    """Wo liegt <name>.fi wirklich? Ohne user/ und app/."""
    for stamm, verz, namen in os.walk(os.path.join(WURZEL, "kernel")):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        if name + ".fi" in namen:
            p = os.path.join(stamm, name + ".fi")
            return os.path.relpath(p, WURZEL)
    return None


def dateien():
    for stamm, verz, namen in os.walk(WURZEL):
        verz[:] = [d for d in verz
                   if d not in (".git", "kernel", "vendor", "docs", "lib")]
        for n in namen:
            if n.endswith((".sh", ".py")) or n == "test.sh":
                p = os.path.join(stamm, n)
                rel = os.path.relpath(p, WURZEL)
                if rel.startswith("tools/struktur/"):
                    continue          # die eigenen Werkzeuge
                yield p, rel


def main():
    trocken = "--trocken" in sys.argv
    cache = {}
    n_zeilen = 0
    n_dateien = 0
    for p, rel in dateien():
        try:
            with open(p, "rb") as f:
                roh = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        if "kernel/" not in roh:
            continue
        zeilen = roh.split("\n")
        geaendert = False
        for i, z in enumerate(zeilen):
            nackt = z.lstrip()
            if nackt.startswith("#") or nackt.startswith("//"):
                continue
            if "kernel/" not in z:
                continue

            def ersetze(m):
                nonlocal geaendert
                name = m.group(1)
                alt = "kernel/%s.fi" % name
                # Regel 2: nur wenn der alte Pfad tot ist.
                if os.path.exists(os.path.join(WURZEL, alt)):
                    return m.group(0)
                if name not in cache:
                    cache[name] = ort_von(name)
                neu = cache[name]
                if not neu or neu == alt:
                    return m.group(0)
                geaendert = True
                return neu

            neu_z = MUSTER.sub(ersetze, z)
            if neu_z != z:
                if trocken:
                    print("  %s:%d" % (rel, i + 1))
                    print("    - %s" % z.strip()[:110])
                    print("    + %s" % neu_z.strip()[:110])
                zeilen[i] = neu_z
                n_zeilen += 1
        if geaendert:
            n_dateien += 1
            if not trocken:
                with open(p, "w", encoding="utf-8") as f:
                    f.write("\n".join(zeilen))
    wort = "waeren zu richten" if trocken else "gerichtet"
    print("%d Zeilen in %d Dateien %s" % (n_zeilen, n_dateien, wort))
    return 0


if __name__ == "__main__":
    sys.exit(main())
