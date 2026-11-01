#!/usr/bin/env python3

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(ROOT, "kernel")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import IMPORT_RE, read_2  # noqa: E402


def envelope(wurzeldatei):
    basis = os.path.dirname(wurzeldatei)
    seen = set()
    stack = [wurzeldatei]
    while stack:
        p = stack.pop()
        rp = os.path.realpath(p)
        if rp in seen or not os.path.exists(p):
            continue
        seen.add(rp)
        own = os.path.dirname(p)
        for z in read_2(p).splitlines():
            m = IMPORT_RE.match(z)
            if not m:
                continue
            parts = m.group(1).split(".")
            kand = os.path.join(own, *parts) + ".fi"
            if not os.path.exists(kand):
                kand = os.path.join(basis, *parts) + ".fi"
            if os.path.exists(kand):
                stack.append(kand)
    return {os.path.relpath(p, KERN) for p in seen}


def main():
    kern = envelope(os.path.join(KERN, "kmain.fi"))
    uprog = envelope(os.path.join(KERN, "uprog.fi"))
    all_2 = set()
    for stamm, _, names in os.walk(KERN):
        for n in names:
            if n.endswith(".fi"):
                all_2.add(os.path.relpath(os.path.join(stamm, n), KERN))
    aussen = all_2 - kern - uprog

    if len(sys.argv) > 2 and sys.argv[1] == "--liste":
        set_2 = {"kern": kern, "uprog": uprog, "aussen": aussen}[sys.argv[2]]
        for p in sorted(set_2):
            print(p)
        return 0

    def lines(set_2):
        s = 0
        for p in set_2:
            s += read_2(os.path.join(KERN, p)).count("\n")
        return s

    print("files under kernel/ total    : %3d  (%d lines)" % (len(all_2), lines(all_2)))
    print("  KERN  (ab kmain.fi)        : %3d  (%d Zeilen)" % (len(kern), lines(kern)))
    print("  UPROG (ab uprog.fi)        : %3d  (%d Zeilen)" % (len(uprog), lines(uprog)))
    print("  OUTSIDE (not in the image) : %3d  (%d lines)" % (len(aussen), lines(aussen)))
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
