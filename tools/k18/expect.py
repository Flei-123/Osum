#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    expect.py perfctl <ratios> <profil>
    expect.py hwp     <ratios> <profil>
    expect.py misc    <orig>   <profil>
    expect.py skala   <rgb> <von> <nach>
    expect.py akku    <rest> <voll> <rate> <state>
"""
import sys

SPAREN, MITTE, LEISTUNG = 0, 1, 2

MISC_EIST = 1 << 16
MISC_NOTURBO = 1 << 38
PERF_NOTURBO = 1 << 32


def num(s):
    return int(s, 0)


def parts(ratios):
    return ratios & 0xFF, (ratios >> 8) & 0xFF, (ratios >> 16) & 0xFF


def perfctl(ratios, prof):
    lo, basis, hi = parts(ratios)
    r = {SPAREN: lo, MITTE: basis, LEISTUNG: hi}[prof]
    w = (r & 0xFF) << 8
    if prof == SPAREN:
        w |= PERF_NOTURBO
    return w


def hwp(ratios, prof):
    lo, basis, hi = parts(ratios)
    if prof == SPAREN:
        return lo | (basis << 8) | (255 << 24)
    if prof == MITTE:
        return lo | (hi << 8) | (128 << 24)
    return basis | (hi << 8)


def misc(orig, prof):
    w = orig & ~(MISC_EIST | MISC_NOTURBO)
    if prof == SPAREN:
        w |= MISC_EIST | MISC_NOTURBO
    elif prof == MITTE:
        w |= MISC_EIST
    return w


def skala(v, von, nach):
    if von == 0:
        return 0
    out = 0
    for schieb in (16, 8, 0):
        k = (v >> schieb) & 0xFF
        k = min(255, k * nach // von)
        out |= k << schieb
    return out


def akku(rest, voll, rate, state):
    if voll == 0:
        p = 0
    else:
        p = min(100, (rest * 100 + voll // 2) // voll)
    if rate in (0, 0xFFFFFFFF):
        m = 0
    else:
        set_2 = (voll - rest) if (state & 2) else rest
        m = 0 if set_2 <= 0 and (state & 2) else (set_2 * 60) // rate
    return p, m


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    b = sys.argv[1]
    a = [num(x) for x in sys.argv[2:]]
    if b == "perfctl":
        print(perfctl(a[0], a[1]))
    elif b == "hwp":
        print(hwp(a[0], a[1]))
    elif b == "misc":
        print(misc(a[0], a[1]))
    elif b == "skala":
        print(skala(a[0], a[1], a[2]))
    elif b == "akku":
        p, m = akku(a[0], a[1], a[2], a[3])
        print("%d %d" % (p, m))
    else:
        print("unbekannt: %s" % b, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
