#!/usr/bin/env python3

import os
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(WURZEL, "kernel")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import IMPORT_RE, lies  # noqa: E402


def huelle(wurzeldatei):
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

    print("files under kernel/ total    : %3d  (%d lines)" % (len(alle), zeilen(alle)))
    print("  KERN  (ab kmain.fi)        : %3d  (%d Zeilen)" % (len(kern), zeilen(kern)))
    print("  UPROG (ab uprog.fi)        : %3d  (%d Zeilen)" % (len(uprog), zeilen(uprog)))
    print("  OUTSIDE (not in the image) : %3d  (%d lines)" % (len(aussen), zeilen(aussen)))
    print()
    print("OUTSIDE by folder:")
    nach = {}
    for p in aussen:
        d = os.path.dirname(p) or "(kernel/)"
        nach[d] = nach.get(d, 0) + 1
    for d, c in sorted(nach.items(), key=lambda kv: -kv[1]):
        print("  %-12s %3d" % (d, c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
