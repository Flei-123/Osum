#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Blaustich B-R einer PPM-Aufnahme: gewichtet nach Flaeche.
Gemessen wird auf den FLAECHENFARBEN (die haeufigsten Toene), nicht auf
dem ganzen Bild -- Text und Symbole sind bunt und wuerden das Mittel
verwaschen."""
import sys, collections
def read_ppm(p):
    d=open(p,'rb').read()
    # P6\n<w> <h>\n<max>\n
    parts=[]; i=0
    while len(parts)<4:
        while i<len(d) and d[i:i+1].isspace(): i+=1
        if d[i:i+1]==b'#':
            while d[i:i+1] not in (b'\n',b''): i+=1
            continue
        s=i
        while i<len(d) and not d[i:i+1].isspace(): i+=1
        parts.append(d[s:i])
    i+=1
    w,h=int(parts[1]),int(parts[2])
    return w,h,d[i:i+w*h*3]
def main(p):
    w,h,px=read_ppm(p)
    c=collections.Counter()
    for k in range(0,len(px),3):
        c[(px[k],px[k+1],px[k+2])]+=1
    tot=w*h
    print(f"{p}  {w}x{h}")
    top=c.most_common(6)
    wsum=0; wtot=0
    for (r,g,b),n in top:
        pct=100.0*n/tot
        print(f"   #{r:02x}{g:02x}{b:02x}  {pct:5.1f}%  B-R={b-r:+4d}")
        wsum+=(b-r)*n; wtot+=n
    print(f"   -> flaechengewichteter Blaustich B-R = {wsum/wtot:+.1f}")
    return wsum/wtot
if __name__=='__main__':
    for f in sys.argv[1:]: main(f); print()
