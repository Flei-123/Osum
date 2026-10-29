#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from iconpixels import ppm  # noqa: E402


def parts(blob):
    out = []
    at = 0
    while at + 12 <= len(blob) and blob[at:at + 4] == b"OSYM":
        w = int.from_bytes(blob[at + 4:at + 8], "little")
        h = int.from_bytes(blob[at + 8:at + 12], "little")
        end = at + 12 + w * h * 4
        if end > len(blob):
            break
        out.append((w, h, blob[at + 12:end]))
        at = end
    return out


def reference(blob, size):
    best = None
    for (w, h, raw) in parts(blob):
        if w == h and w >= size and w % size == 0:
            if best is None or w < best[0]:
                best = (w, raw)
    if best is None:
        raise SystemExit("no bake with a multiple of %d px" % size)
    w, raw = best
    k = w // size
    tile = {}
    for ty in range(size):
        for tx in range(size):
            acc = [0, 0, 0]
            solid = True
            for dy in range(k):
                for dx in range(k):
                    at = ((ty * k + dy) * w + tx * k + dx) * 4
                    b, g, r, a = raw[at:at + 4]
                    if a != 255:
                        solid = False
                    acc[0] += r
                    acc[1] += g
                    acc[2] += b
            if solid:
                n = k * k
                tile[(tx, ty)] = (acc[0] // n, acc[1] // n, acc[2] // n)
    return tile


def main(argv):
    if len(argv) != 7:
        print("usage: tile.py <screen.ppm> <x> <y> <size> <symbol> <max-mean-error>")
        return 2
    w, h, raw = ppm(argv[1])
    x0, y0, size = int(argv[2]), int(argv[3]), int(argv[4])
    limit = float(argv[6])
    tile = reference(open(argv[5], "rb").read(), size)
    if not tile:
        print("the symbol has no opaque tile pixel")
        return 1
    total = 0
    for (tx, ty), (r, g, b) in tile.items():
        px, py = x0 + tx, y0 + ty
        if px >= w or py >= h:
            total += 255
            continue
        at = (py * w + px) * 3
        total += (abs(raw[at] - r) + abs(raw[at + 1] - g) + abs(raw[at + 2] - b)) / 3
    mean = total / len(tile)
    print("%d opaque tile pixels, mean error %.2f (limit %.2f)" % (len(tile), mean, limit))
    return 0 if mean <= limit else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
