#!/usr/bin/env python3

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(ROOT, "kernel")
SOLLDATEI = os.path.join(ROOT, "tools", "structure", "filing.txt")

sys.path.insert(0, os.path.join(ROOT, "tools", "struktur"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import read_2  # noqa: E402
import shell  # noqa: E402


def read_soll():
    soll = {}
    if not os.path.exists(SOLLDATEI):
        return soll
    for z in read_2(SOLLDATEI).splitlines():
        z = z.strip()
        if not z or z.startswith("#"):
            continue
        t = z.split()
        if len(t) == 2:
            soll[t[1]] = t[0]
    return soll


def ist_clipboard():
    kern = shell.envelope(os.path.join(KERN, "kmain.fi"))
    kern |= shell.envelope(os.path.join(KERN, "uprog.fi"))
    ist = {}
    for rel in kern:
        d = os.path.dirname(rel)
        ist[os.path.basename(rel)[:-3]] = d if d else "."
    return ist


def all_dateien():
    aus = {}
    for stamm, verz, names in os.walk(KERN):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        for n in names:
            if n.endswith(".fi"):
                rel = os.path.relpath(os.path.join(stamm, n), KERN)
                d = os.path.dirname(rel)
                aus[n[:-3]] = d if d else "."
    return aus


def vergleiche():
    soll = read_soll()
    ist = ist_clipboard()
    flach = all_dateien()
    for m, d in flach.items():
        if m in soll and m not in ist:
            ist[m] = d
    fits, wrong, without_soll, missing = [], [], [], []
    for m, d in sorted(ist.items()):
        s = soll.get(m)
        if s is None:
            without_soll.append((m, d))
        elif s == d:
            fits.append((m, d))
        else:
            wrong.append((m, d, s))
    for m in sorted(soll):
        if m not in ist and m not in flach:
            missing.append(m)
    return fits, wrong, without_soll, soll, ist, missing


def main():
    modus = sys.argv[1] if len(sys.argv) > 1 else ""
    fits, wrong, without_soll, soll, ist, missing = vergleiche()

    if modus == "--fehlend":
        for m, d in without_soll:
            print("%s (is in %s)" % (m, d))
        return 0

    if modus == "--offen":
        for m, d, s in wrong:
            print("%s %s %s" % (m, d, s))
        return 0

    if modus == "--pruefen":
        if not soll:
            print("NO target filing (tools/structure/filing.txt) -- nothing checked")
            return 1
        print("filing: %d files in the right place, %d in the wrong one, "
              "%d ohne Soll, %d vermisst"
              % (len(fits), len(wrong), len(without_soll), len(missing)))
        for m, d, s in wrong:
            print("  WRONG  %s is in '%s', soll nach '%s'" % (m, d, s))
        for m, d in without_soll:
            print("  NO TARGET  %s (is in '%s')" % (m, d))
        for m in missing:
            print("  MISSING  %s is in the target, but is nowhere" % m)
        return 1 if (wrong or without_soll or missing) else 0

    print("== ABLAGE ==")
    print("Soll-Eintraege: %d, Kerndateien: %d" % (len(soll), len(ist)))
    print("am richtigen Ort: %d" % len(fits))
    print("am falschen Ort : %d" % len(wrong))
    print("without target  : %d" % len(without_soll))
    print()
    nach = {}
    for m, d in ist.items():
        nach[d] = nach.get(d, 0) + 1
    print("-- Ist-Verteilung --")
    for d, c in sorted(nach.items(), key=lambda kv: (-kv[1], kv[0])):
        print("  %-12s %3d" % (d, c))
    if wrong:
        print()
        print("-- noch umzuziehen --")
        for m, d, s in wrong:
            print("  %-12s %s -> %s" % (m, d, s))
    if without_soll:
        print()
        print("-- without target entry --")
        for m, d in without_soll:
            print("  %-12s (%s)" % (m, d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
