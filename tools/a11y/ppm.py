#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/ppm.py -- ein PPM (P6) lesen. Eine Stelle, die es kann."""


def lesen(pfad):
    with open(pfad, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 10:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1
    b, h, _ = felder
    return b, h, roh[i:i + b * h * 3]


class Bild:
    def __init__(self, pfad):
        self.w, self.h, self.d = lesen(pfad)

    def px(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        o = (y * self.w + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])
