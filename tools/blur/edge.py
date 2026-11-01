#!/usr/bin/env python3
import sys
from PIL import Image

def line(px, y, x0, x1):
    big = small = 0
    for x in range(x0, x1 - 1):
        a = px[x, y]; b = px[x + 1, y]
        d = abs(a[0]-b[0]) + abs(a[1]-b[1]) + abs(a[2]-b[2])
        if d > 60: big += 1
        elif d >= 4: small += 1
    return big, small

def main():
    im = Image.open(sys.argv[1]).convert('RGB')
    px = im.load()
    print(f"{'Line':>6}  {'was':<28} {'harte Edges':>13} {'weiche Uebergaenge':>19}")
    proben = [
        (680, "blanker Grund",        600, 1270),
        (700, "blanker Grund",        600, 1270),
        (720, "HINTER der Leiste",    600, 1270),
        (735, "HINTER der Leiste",    600, 1270),
        (750, "HINTER der Leiste",    600, 1270),
        (500, "HINTER dem Menue",      90,  395),
        (600, "HINTER dem Menue",      90,  395),
        (500, "blanker Grund daneben",420,  725),
        (600, "blanker Grund daneben",420,  725),
    ]
    for y, was, x0, x1 in proben:
        g, k = line(px, y, x0, x1)
        print(f"{y:>6}  {was:<28} {g:>13} {k:>19}")

main()
