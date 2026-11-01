#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    count.py <ppm> <x> <y> <w> <h> <r> <g> <b>
"""
import sys


def load(path_2):
    d = open(path_2, "rb").read()
    parts = []
    i = 0
    while len(parts) < 4:
        while d[i:i + 1] in b" \t\r\n":
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in b"\r\n":
                i += 1
            continue
        j = i
        while d[j:j + 1] not in b" \t\r\n":
            j += 1
        parts.append(d[i:j])
        i = j
    i += 1
    if parts[0] != b"P6":
        raise SystemExit("not a P6 PPM: %s" % parts[0])
    return int(parts[1]), int(parts[2]), d[i:]


def main():
    if len(sys.argv) < 9:
        print(__doc__)
        return 2
    ppm = sys.argv[1]
    x0, y0, w, h = (int(v) for v in sys.argv[2:6])
    target = tuple(int(v) for v in sys.argv[6:9])
    W, H, px = load(ppm)
    n = 0
    for y in range(y0, min(y0 + h, H)):
        for x in range(x0, min(x0 + w, W)):
            o = (y * W + x) * 3
            if (px[o], px[o + 1], px[o + 2]) == target:
                n += 1
    print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
