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
    w, h, _mx = felder
    return w, h, d[at:at + w * h * 3]


def main():
    iw, ih, ib = ppm(sys.argv[1])
    aw, ah, ab = ppm(sys.argv[2])
    print("innen  %dx%d  %d Oktette" % (iw, ih, len(ib)))
    print("aussen %dx%d  %d Oktette" % (aw, ah, len(ab)))
    if (iw, ih) != (aw, ah):
        print("MASSE VERSCHIEDEN")
        return 1
    if len(ib) != iw * ih * 3:
        print("THE IMAGE FROM INSIDE IS INCOMPLETE: %d instead of %d"
              % (len(ib), iw * ih * 3))
        return 1
    print("the image from inside is COMPLETE: %d octets" % len(ib))

    line = iw * 3
    verschieden = [y for y in range(ih)
                   if ib[y * line:(y + 1) * line] != ab[y * line:(y + 1) * line]]
    vs = set(verschieden)
    eq = ih - len(verschieden)
    print("lines equal: %d of %d" % (eq, ih))
    print("Zeilen verschieden: %d" % len(verschieden))

    changed = 0
    for y in range(ih):
        if y in vs:
            continue
        o = y * line
        if ib[o:o + line] != ab[o:o + line]:
            for i in range(o, o + line):
                if ib[i] != ab[i]:
                    changed += 1
    print("deviating octets in the same lines: %d" % changed)

    nichtschwarz = sum(1 for i in range(0, len(ib), 3)
                       if ib[i] or ib[i + 1] or ib[i + 2])
    print("non-black pixels inside: %d of %d" % (nichtschwarz, iw * ih))

    if verschieden:
        baender = []
        s0 = verschieden[0]
        pv = verschieden[0]
        for y in verschieden[1:]:
            if y != pv + 1:
                baender.append((s0, pv))
                s0 = y
            pv = y
        baender.append((s0, pv))
        print("Baender verschiedener Zeilen: %d, erste: %s"
              % (len(baender), baender[:4]))

    if eq > 0 and changed == 0 and nichtschwarz > 1000:
        print("GLEICH")
        return 0
    print("UNGLEICH")
    return 1


if __name__ == "__main__":
    sys.exit(main())
