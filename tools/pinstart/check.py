#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

from PIL import Image


def changed(a, b, x0, y0, x1, y1):
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    pa, pb = ia.load(), ib.load()
    n = 0
    for y in range(y0, min(y1, ia.size[1])):
        for x in range(x0, min(x1, ia.size[0])):
            if pa[x, y] != pb[x, y]:
                n += 1
    return n


if __name__ == "__main__":
    print(changed(sys.argv[1], sys.argv[2], *[int(v) for v in sys.argv[3:7]]))
