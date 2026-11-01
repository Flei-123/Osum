#!/usr/bin/env python3
RADIUS_MAX = 16
SHIFT = 19

def main():
    nmax = 2 * RADIUS_MAX + 1
    rund = 1 << (SHIFT - 1)
    schlimm = 0
    faelle = 0
    for n in range(1, nmax + 1):
        rec = ((1 << SHIFT) + n - 1) // n
        if rec >> 32:
            print(f"  n={n}: reciprocal does not fit in 32 bits"); return 1
        for sum_2 in range(0, n * 255 + 1):
            exakt = (sum_2 + n // 2) // n
            got = (sum_2 * rec + rund) >> SHIFT
            faelle += 1
            d = abs(exakt - got)
            if d > schlimm:
                schlimm = d
    print(f"BLUR-KEHRWERT: shift={SHIFT}, n=1..{nmax}, {faelle} Faelle geprueft")
    if schlimm == 0:
        print("  OK    every case EXACTLY like the division")
        return 0
    print(f"  FEHL  groesster Fehler {schlimm}")
    return 1

raise SystemExit(main())
