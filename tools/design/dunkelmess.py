#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys


def ppm_read(p):
    d = open(p, 'rb').read()
    if not d.startswith(b'P6'):
        raise SystemExit("kein P6-PPM: " + p)
    tok, i = [], 2
    while len(tok) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b'#':
            while d[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j])); i = j
    i += 1
    w, h, _ = tok
    return w, h, d[i:i + w * h * 3]


def brightness(px, w, x0, y0, x1, y1, schritt=3):
    s = 0.0
    n = 0
    for y in range(y0, y1, schritt):
        for x in range(x0, x1, schritt):
            i = (y * w + x) * 3
            s += 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]
            n += 1
    return s / max(1, n)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    hp, dp = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else hp.split('/')[-1]
    wh, hh, ph = ppm_read(hp)
    wd, hd, pd = ppm_read(dp)
    if (wh, hh) != (wd, hd):
        raise SystemExit("verschieden gross: %dx%d gegen %dx%d" % (wh, hh, wd, hd))

    gh = brightness(ph, wh, 0, 0, wh, hh)
    gd = brightness(pd, wd, 0, 0, wd, hd)
    print("== %s ==" % name)
    print("  ganzes Bild      hell %6.1f   dunkel %6.1f   Differenz %+7.1f  %s"
          % (gh, gd, gd - gh, "OK" if gd < gh - 20 else "<-- ZIEHT NICHT MIT"))

    KX, KY = 8, 6
    stehen = []
    print()
    print("  Kachel        hell  dunkel   Diff")
    for ky in range(KY):
        zeile = []
        for kx in range(KX):
            x0, x1 = kx * wh // KX, (kx + 1) * wh // KX
            y0, y1 = ky * hh // KY, (ky + 1) * hh // KY
            a = brightness(ph, wh, x0, y0, x1, y1, 5)
            b = brightness(pd, wd, x0, y0, x1, y1, 5)
            zeile.append(b - a)
            if a > 60 and b > a - 20:
                stehen.append((kx, ky, a, b))
        print("   y%d  " % ky + " ".join("%+6.0f" % v for v in zeile))

    print()
    if stehen:
        print("  AREAS THAT DO NOT FOLLOW (stayed light):")
        for kx, ky, a, b in stehen:
            print("    Kachel x%d y%d   hell %5.1f -> dunkel %5.1f  (%+.1f)"
                  % (kx, ky, a, b, b - a))
        sys.exit(1)
    print("  every tile gets darker in dark mode -- nothing left behind")
