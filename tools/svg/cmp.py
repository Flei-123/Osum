#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import struct
import sys

import cairosvg
from PIL import Image


def load_osym(path):
    d = open(path, "rb").read()
    w, h = struct.unpack("<II", d[4:12])
    return Image.frombytes("RGBA", (w, h), d[12:], "raw", "BGRA")


def reference(svg, size):
    png = cairosvg.svg2png(url=svg, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main(argv):
    img = load_osym(argv[1])
    ref = reference(argv[0], img.width)
    a = list(img.getchannel("A").tobytes())
    b = list(ref.getchannel("A").tobytes())
    mean = sum(abs(x - y) for x, y in zip(a, b)) / len(a)
    worst = max(abs(x - y) for x, y in zip(a, b))
    print("%.3f %d %d %d" % (mean, worst, sum(1 for x in a if x), sum(1 for x in b if x)))


if __name__ == "__main__":
    main(sys.argv[1:])
