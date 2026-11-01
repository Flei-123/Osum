#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    wachstum.py <ppm> [<ppm> ...]
    <file> area=<n> gemischt=<n>
    SEQ bilder=<n> min=<n> max=<n> stufen=<n> gemischt_max=<n>
"""
import sys

FRAME = (0x2E, 0x6F, 0xD9)
AREA = (0xE8, 0xEE, 0xF7)
NAH = 40


def ppm_read(path_2):
    with open(path_2, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM")
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
    w, h, _ = felder
    return w, h, roh[i:i + w * h * 3]


def nahe(px, target):
    return (abs(px[0] - target[0]) <= NAH
            and abs(px[1] - target[1]) <= NAH
            and abs(px[2] - target[2]) <= NAH)


def count(path_2):
    w, h, dat = ppm_read(path_2)
    area = 0
    gemischt = 0
    for k in range(0, len(dat) - 2, 3):
        px = (dat[k], dat[k + 1], dat[k + 2])
        if nahe(px, FRAME) or nahe(px, AREA):
            area += 1
            if px != FRAME and px != AREA:
                gemischt += 1
    _ = (w, h)
    return area, gemischt


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    values = []
    gmax = 0
    for path_2 in sys.argv[1:]:
        try:
            f, g = count(path_2)
        except (OSError, ValueError) as e:
            print("%s FEHLER %s" % (path_2, e))
            return 2
        values.append(f)
        gmax = max(gmax, g)
        print("%s flaeche=%d gemischt=%d" % (path_2.split("/")[-1], f, g))
    if not values:
        return 2
    mitinhalt = [v for v in values if v > 0]
    stufen = len(set(mitinhalt))
    print("FOLGE bilder=%d min=%d max=%d stufen=%d gemischt_max=%d"
          % (len(values), min(values), max(values), stufen, gmax))
    return 0 if stufen >= 3 else 1


if __name__ == "__main__":
    sys.exit(main())
