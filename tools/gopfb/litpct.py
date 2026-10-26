#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys


def main():
    data = open(sys.argv[1], "rb").read()
    head = data.split(b"\n", 3)
    width, height = (int(v) for v in head[1].split())
    pixels = head[3]
    step = 3 * 97
    total = lit = 0
    for i in range(0, len(pixels) - 2, step):
        total += 1
        if pixels[i] | pixels[i + 1] | pixels[i + 2]:
            lit += 1
    print("%d %d %d" % (width, height, (1000 * lit) // max(total, 1)))


main()
