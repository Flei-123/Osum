#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/codec/nalzahl.py -- zaehlt die Slice-Einheiten eines Annex-B-Stroms.

Damit prueft die Abnahme, dass der Strom `slices` WIRKLICH mehrere
Slices je Bild hat. Ohne diese Zahl waere "mehrere Slices gehen" eine
Hoffnung: kodiert x264 doch nur einen, laeuft der Test durch, ohne den
Fall je zu beruehren.

    python3 tools/codec/nalzahl.py DATEI   ->  "<slices> <idr> <erste_first_mb...>"
"""
import sys

def nals(d):
    out = []; i = 0; n = len(d)
    while i + 2 < n:
        if d[i] == 0 and d[i+1] == 0 and d[i+2] == 1:
            st = i + 3; j = st
            while j + 2 < n and not (d[j] == 0 and d[j+1] == 0 and d[j+2] == 1):
                j += 1
            e = n if j + 2 >= n else j
            while e > st and d[e-1] == 0: e -= 1
            if e > st: out.append(d[st:e])
            i = j if j + 2 < n else n
        else:
            i += 1
    return out

def rbsp(x):
    o = bytearray(); i = 0
    while i < len(x):
        if i + 2 < len(x) and x[i] == 0 and x[i+1] == 0 and x[i+2] == 3:
            o += b'\x00\x00'; i += 3
        else:
            o.append(x[i]); i += 1
    return bytes(o)

class BR:
    def __init__(s, d): s.d = d; s.p = 0
    def u1(s):
        if s.p >= len(s.d) * 8: return 0
        b = (s.d[s.p >> 3] >> (7 - (s.p & 7))) & 1; s.p += 1; return b
    def ue(s):
        z = 0
        while z < 32 and s.u1() == 0: z += 1
        v = 0
        for _ in range(z): v = (v << 1) | s.u1()
        return (1 << z) - 1 + v

d = open(sys.argv[1], 'rb').read()
slices = 0; idr = 0; firsts = []
for nl in nals(d):
    t = nl[0] & 31
    if t in (1, 5):
        slices += 1
        if t == 5: idr += 1
        firsts.append(BR(rbsp(nl[1:])).ue())
print("%d %d %s" % (slices, idr, ",".join(str(x) for x in firsts)))
