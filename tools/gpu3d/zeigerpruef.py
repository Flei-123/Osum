#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    zeigerpruef.py <mit-hardware.ppm> <without-hardware.ppm>
"""
import sys

MAXPX = 48
MIN_DUNKEL = 20
MIN_BRIGHT = 10


def load(path):
    d = open(path, "rb").read()
    i = 0
    f = []
    while len(f) < 4:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while i < len(d) and d[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        f.append(d[i:j])
        i = j
    i += 1
    if f[0] != b"P6":
        raise ValueError("%s ist kein P6-PPM" % path)
    w, h = int(f[1]), int(f[2])
    return w, h, d[i:i + w * h * 3]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    try:
        wh, hh, hw = load(sys.argv[1])
        ws, hs, sw = load(sys.argv[2])
    except Exception as e:
        print("FEHL: %s" % e)
        return 1

    if (wh, hh) != (ws, hs):
        print("FAIL: the photos have different sizes (%dx%d versus %dx%d)"
              % (wh, hh, ws, hs))
        return 1
    w, h = wh, hh
    print("Groesse: %dx%d, beide gleich" % (w, h))

    diff = []
    for y in range(h):
        z = y * w * 3
        for x in range(w):
            o = z + x * 3
            if hw[o:o + 3] != sw[o:o + 3]:
                diff.append((x, y))

    if not diff:
        print("FAIL: the photos are IDENTICAL -- then the new path")
        print("      changed nothing, and the measurement measures nothing.")
        return 1

    xs = [p[0] for p in diff]
    ys = [p[1] for p in diff]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    print("Unterschied: %d Bildpunkte in x %d..%d, y %d..%d (%dx%d)"
          % (len(diff), x0, x1, y0, y1, bw, bh))

    if bw > MAXPX or bh > MAXPX:
        print("FAIL: the difference is larger than a pointer")
        print("      (%dx%d, at most %dx%d expected) -- then more"
              % (bw, bh, MAXPX, MAXPX))
        print("      differs than just it.")
        return 1

    def points(buf):
        aus = []
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                o = (y * w + x) * 3
                aus.append(tuple(buf[o:o + 3]))
        return aus

    psw = points(sw)
    phw = points(hw)

    dunkel = sum(1 for p in psw if sum(p) < 120)
    bright = sum(1 for p in psw if sum(p) > 600)
    print("in the software image at this spot: %d dark, %d bright pixels"
          % (dunkel, bright))
    if dunkel < MIN_DUNKEL or bright < MIN_BRIGHT:
        print("FAIL: no painted pointer there (expected at least")
        print("      %d dunkle und %d helle)." % (MIN_DUNKEL, MIN_BRIGHT))
        return 1

    farben = set(phw)
    print("in the hardware image at the same spot: %d different colors"
          % len(farben))
    if len(farben) != 1:
        print("FAIL: something is painted there -- with a hardware pointer the")
        print("      spot must be plain background, otherwise it appears TWICE.")
        for f in sorted(farben)[:6]:
            print("      %r" % (f,))
        return 1
    print("       and indeed uniform %r -- plain background." % (phw[0],))

    print()
    print("PROOF: the pointer is ONLY in the software image. With the new path")
    print("       the device carries it, the image stays untouched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
