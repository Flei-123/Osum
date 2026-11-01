#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    zerreiss.py <ppm> [<ppm> ...]
    <file> window=<n> zerrissen=<n> farben=<items>
    SUM bilder=<n> window=<n> zerrissen=<n>
"""
import sys

SIG = {
    (0xFF, 0x00, 0x00): 0,
    (0x00, 0xFF, 0x00): 1,
    (0x00, 0x00, 0xFF): 2,
    (0xFF, 0xFF, 0x00): 3,
    (0xFF, 0x00, 0xFF): 4,
    (0x00, 0xFF, 0xFF): 5,
    (0xFF, 0x80, 0x00): 6,
    (0xFF, 0xFF, 0xFF): 7,
}
MIN_WIDE = 40


def ppm_read(path_2):
    with open(path_2, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % path_2)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1
    w, h, _mx = felder
    return w, h, roh[i:i + w * h * 3]


def streifen_der_line(w, line):
    aus = []
    x = 0
    while x < w:
        px = (line[x * 3], line[x * 3 + 1], line[x * 3 + 2])
        k = SIG.get(px)
        if k is None:
            x += 1
            continue
        x0 = x
        while x < w:
            q = (line[x * 3], line[x * 3 + 1], line[x * 3 + 2])
            if SIG.get(q) != k:
                break
            x += 1
        if x - x0 >= MIN_WIDE:
            aus.append((x0, x, k))
    return aus


def image_check(path_2):
    w, h, dat = ppm_read(path_2)
    nach_spanne = {}
    for y in range(h):
        line = dat[y * w * 3:(y + 1) * w * 3]
        if len(line) < w * 3:
            break
        for (x0, x1, k) in streifen_der_line(w, line):
            nach_spanne.setdefault((x0, x1), []).append((y, k))
    window = 0
    zerrissen = 0
    farben = set()
    for (_spanne, treffer) in sorted(nach_spanne.items()):
        ys = [t[0] for t in treffer]
        ks = set(t[1] for t in treffer)
        if len(ys) < 2:
            continue
        gap = False
        for a, b in zip(ys, ys[1:]):
            if b - a > 8:
                gap = True
                break
        if not gap:
            continue
        window += 1
        farben |= ks
        if len(ks) > 1:
            zerrissen += 1
    return window, zerrissen, sorted(farben)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    g_f = 0
    g_z = 0
    n = 0
    for path_2 in sys.argv[1:]:
        try:
            f, z, farben = image_check(path_2)
        except (OSError, ValueError) as e:
            print("%s FEHLER %s" % (path_2, e))
            return 2
        n += 1
        g_f += f
        g_z += z
        print("%s fenster=%d zerrissen=%d farben=%s"
              % (path_2.split("/")[-1], f, z,
                 ",".join(str(k) for k in farben) or "-"))
    print("SUMME bilder=%d fenster=%d zerrissen=%d" % (n, g_f, g_z))
    return 1 if g_z else 0


if __name__ == "__main__":
    sys.exit(main())
