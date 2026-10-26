#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/xfer/mkpng.py -- two test pictures for the image clipboard gate.

    mkpng.py <outdir>      writes a.png (96x64) and b.png (40x30)
"""
import os
import sys

from PIL import Image


def picture(w, h, seed):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ((x * 255 // max(w - 1, 1) + seed) & 255, (y * 255 // max(h - 1, 1)) & 255, ((x ^ y) * 7 + seed) & 255)
    return im


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    picture(96, 64, 3).save(os.path.join(out, "a.png"))
    picture(40, 30, 90).save(os.path.join(out, "b.png"))


if __name__ == "__main__":
    main()
