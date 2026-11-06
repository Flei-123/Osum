#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    kachelprobe.py <image.ppm> <serielle-output>
"""

import re
import sys

TILE = re.compile(
    r"storage: tile i=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) "
    r"color=(\d+) name=(\S+)")

VERSAETZE = [(x, y) for x in (40, 41, 42, 43) for y in
             (40, 42, 60, 61, 62, 63, 64, 65, 66)]


def ppm(path_2):
    with open(path_2, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise SystemExit("tile probe: not a P6 PPM")
    at, felder = 2, []
    while len(felder) < 3:
        while roh[at:at + 1].isspace():
            at += 1
        if roh[at:at + 1] == b"#":
            while roh[at:at + 1] != b"\n":
                at += 1
            continue
        a = at
        while not roh[at:at + 1].isspace():
            at += 1
        felder.append(int(roh[a:at]))
    at += 1
    return felder[0], felder[1], roh[at:]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    W, H, px = ppm(argv[1])
    txt = open(argv[2], "rb").read().decode("latin-1")

    def color(x, y):
        if x < 0 or y < 0 or x >= W or y >= H:
            return -1
        o = (y * W + x) * 3
        return (px[o] << 16) | (px[o + 1] << 8) | px[o + 2]

    kacheln = [(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                int(m.group(4)), int(m.group(5)), int(m.group(6)),
                m.group(7)) for m in TILE.finditer(txt)]
    if not kacheln:
        print("tile probe: not a single tile reported")
        return 1

    treffer = None
    for ox, oy in VERSAETZE:
        if all(color(x + w // 2 + ox, y + h // 2 + oy) == f
               for _i, x, y, w, h, f, _n in kacheln):
            treffer = (ox, oy)
            break
    if treffer is None:
        print("tile probe: NO offset at which all %d tiles have their "
              "colour" % len(kacheln))
        for _i, x, y, w, h, f, n in kacheln:
            print("  %-10s reported %06X, in image %06X"
                  % (n, f, color(x + w // 2 + 42, y + h // 2 + 62)))
        return 1
    ox, oy = treffer
    print("tile probe: %d tiles, offset of the window content %d,%d"
          % (len(kacheln), ox, oy))

    bad_2 = 0
    breiten = []
    for _i, x, y, w, h, f, n in kacheln:
        mitte = x + w // 2 + ox
        gemessen = 0
        for k in (4, 5, 6, 7):
            yy = y + h * k // 9 + oy
            if color(mitte, yy) != f:
                continue
            li = mitte
            while color(li - 1, yy) == f:
                li -= 1
            re_ = mitte
            while color(re_ + 1, yy) == f:
                re_ += 1
            gemessen = max(gemessen, re_ - li + 1)
        breiten.append((n, w, gemessen))
        gut = abs(gemessen - w) <= 4
        if not gut:
            bad_2 += 1
        print("  %-10s reported w=%-5d in image %-5d %s"
              % (n, w, gemessen, "" if gut else "<-- MISMATCH"))

    fallend = all(breiten[k][2] >= breiten[k + 1][2] - 4
                  for k in range(len(breiten) - 1))
    print("tile probe: the widths fall with the share: %s"
          % ("yes" if fallend else "NO"))
    if bad_2 or not fallend:
        print("tile probe: %d tiles do not match" % bad_2)
        return 1
    print("tile probe: all tiles have in the image the width that the "
          "program reported")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
