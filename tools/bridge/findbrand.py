#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys


def ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("keine P6-Datei: " + path)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        s = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        felder.append(int(d[s:at]))
    at += 1
    w, h, _ = felder
    return w, h, d[at:at + w * h * 3]


def main():
    w, h, a = ppm(sys.argv[1])
    w2, h2, b = ppm(sys.argv[2])
    if (w, h) != (w2, h2):
        print("MASSE VERSCHIEDEN")
        return 1
    line = w * 3

    verschieden = [y for y in range(h)
                   if a[y * line:(y + 1) * line] != b[y * line:(y + 1) * line]]
    if not verschieden:
        print("NO LINE DIFFERENT -- the brand is nowhere")
        return 1

    baender = []
    s0 = verschieden[0]
    pv = verschieden[0]
    for y in verschieden[1:]:
        if y != pv + 1:
            baender.append((s0, pv))
            s0 = y
        pv = y
    baender.append((s0, pv))
    print("verschiedene Baender: %s" % baender)
    up = max(e - s + 1 for s, e in baender)
    print("highest band: %d lines (one text line is 16)" % up)

    def bright(image, von, bis):
        n = 0
        for y in range(von, bis + 1):
            o = y * line
            for i in range(o, o + line, 3):
                if image[i] > 96 or image[i + 1] > 96 or image[i + 2] > 96:
                    n += 1
        return n

    ha = sum(bright(a, s, e) for s, e in baender)
    hb = sum(bright(b, s, e) for s, e in baender)
    print("bright pixels in these bands: one=%d two=%d" % (ha, hb))

    if up <= 40 and hb > ha:
        print("MARKE-GEFUNDEN")
        return 0
    print("BRAND-NOT-FOUND")
    return 1


if __name__ == "__main__":
    sys.exit(main())
