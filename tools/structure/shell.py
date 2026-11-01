#!/usr/bin/env python3

import os
import sys

ROOT_2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(ROOT_2, "kernel")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erhebung import IMPORT_RE, read_2  # noqa: E402


def envelope(wurzeldatei):
    basis = os.path.dirname(wurzeldatei)
    seen = set()
    stack_2 = [wurzeldatei]
    while stack_2:
        p = stack_2.pop()
        rp = os.path.realpath(p)
        if rp in seen or not os.path.exists(p):
            continue
        seen.add(rp)
        own_2 = os.path.dirname(p)
        for z in read_2(p).splitlines():
            m = IMPORT_RE.match(z)
            if not m:
                continue
            parts_2 = m.group(1).split(".")
            kand = os.path.join(own_2, *parts_2) + ".fi"
            if not os.path.exists(kand):
                kand = os.path.join(basis, *parts_2) + ".fi"
            if os.path.exists(kand):
                stack_2.append(kand)
    return {os.path.relpath(p, KERN) for p in seen}


def main():
    kern = envelope(os.path.join(KERN, "kmain.fi"))
    uprog = envelope(os.path.join(KERN, "uprog.fi"))
    all_ = set()
    for stamm, _, names_2 in os.walk(KERN):
        for n in names_2:
            if n.endswith(".fi"):
                all_.add(os.path.relpath(os.path.join(stamm, n), KERN))
    aussen = all_ - kern - uprog

    if len(sys.argv) > 2 and sys.argv[1] == "--liste":
        set_ = {"kern": kern, "uprog": uprog, "aussen": aussen}[sys.argv[2]]
        for p in sorted(set_):
            print(p)
        return 0

    def lines_2(set_):
        s = 0
        for p in set_:
            s += read_2(os.path.join(KERN, p)).count("\n")
        return s

    print("files under kernel/ total    : %3d  (%d lines)" % (len(all_), lines_2(all_)))
    print("  KERN  (ab kmain.fi)        : %3d  (%d Zeilen)" % (len(kern), lines_2(kern)))
    print("  UPROG (ab uprog.fi)        : %3d  (%d Zeilen)" % (len(uprog), lines_2(uprog)))
    print("  OUTSIDE (not in the image) : %3d  (%d lines)" % (len(aussen), lines_2(aussen)))
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
