#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/kontrast.py -- das Kontrastverhaeltnis zweier Farben.

    kontrast.py <fg> <bg>        (Dezimalzahlen, 0xRRGGBB)

Die Rechnung ist die von WCAG 2.1: relative Leuchtdichte in linearem
Licht, (L1 + 0.05) / (L2 + 0.05).  AA verlangt 4.5, AAA verlangt 7 --
und genau darum geht es bei einem Kontrastschema: nicht "dunkler",
sondern eine Zahl, die man nachrechnen kann.
"""
import sys


def linear(c):
    c = c / 255.0
    if c <= 0.03928:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def leucht(v):
    r, g, b = (v >> 16) & 255, (v >> 8) & 255, v & 255
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    a, b = int(sys.argv[1]), int(sys.argv[2])
    la, lb = leucht(a), leucht(b)
    if la < lb:
        la, lb = lb, la
    print("%.2f" % ((la + 0.05) / (lb + 0.05)))
    return 0


sys.exit(main())
