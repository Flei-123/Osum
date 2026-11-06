#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    bildref.py <file>              die numbers des Wirts
    bildref.py verify <serial.txt> <file> [<file> ...]
"""
import re
import sys

from PIL import Image


def nums(path):
    im = Image.open(path)
    art = im.format.lower()
    voll = True
    if art == "jpeg":
        for _id, hs, vs, _q in im.layer:
            if hs != 1 or vs != 1:
                voll = False
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    sr = sg = sb = 0
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            sr += r
            sg += g
            sb += b
    points = []
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
                 (w // 2, h // 2)):
        r, g, b, _a = px[x, y]
        points.append((x, y, (r << 16) | (g << 8) | b))
    if art == "jpeg":
        art = "jpeg"
    return dict(art=art, w=w, h=h, sr=sr, sg=sg, sb=sb, points=points,
                voll=voll)


def gast(text, name):
    brand = "viewer: file " + name
    at = text.find(brand)
    if at < 0:
        return None
    part = text[at:at + 1200]
    m = re.search(r"viewer: art=(\w+) w=(\d+) h=(\d+)", part)
    if not m:
        return None
    s = re.search(r"viewer: sum (\d+) w=(\d+) h=(\d+)", part)
    p = re.findall(r" (\d+),(\d+)=([0-9a-f]{6})", part)
    if not s or len(p) < 5:
        return None
    return dict(art=m.group(1), w=int(m.group(2)), h=int(m.group(3)),
                sr=int(s.group(1)), sg=int(s.group(2)), sb=int(s.group(3)),
                points=[(int(a), int(b), int(c, 16)) for a, b, c in p[:5]])


def kanaele(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def vergleich(g, w, name):
    error = []
    if (g["w"], g["h"]) != (w["w"], w["h"]):
        error.append("Groesse %dx%d statt %dx%d"
                      % (g["w"], g["h"], w["w"], w["h"]))
    verlustfrei = w["art"] in ("png", "bmp")
    punktweise = verlustfrei or w.get("voll", True)
    n = w["w"] * w["h"]
    for k in ("sr", "sg", "sb"):
        d = abs(g[k] - w[k])
        if verlustfrei:
            if d != 0:
                error.append("%s %d statt %d" % (k, g[k], w[k]))
        elif d > n:
            error.append("%s %d statt %d (%.2f je Bildpunkt)"
                          % (k, g[k], w[k], d / max(1, n)))
    for (gx, gy, gv), (wx, wy, wv) in ([] if not punktweise
                                       else zip(g["points"], w["points"])):
        if (gx, gy) != (wx, wy):
            error.append("Bildpunkt %d,%d statt %d,%d" % (gx, gy, wx, wy))
            continue
        gk, wk = kanaele(gv), kanaele(wv)
        d = max(abs(a - b) for a, b in zip(gk, wk))
        if (verlustfrei and d != 0) or (not verlustfrei and d > 3):
            error.append("Bildpunkt %d,%d: %06x statt %06x"
                          % (gx, gy, gv, wv))
    if error:
        print("  FAIL  %-16s %s" % (name, "; ".join(error[:3])))
        return False
    wie = "Summen und fuenf Bildpunkte"
    if not punktweise:
        wie = "Summen (4:2:0, Farbfilter verschieden)"
    print("  OK    %-16s %s %dx%d, %s stimmen"
          % (name, w["art"], w["w"], w["h"], wie))
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] != "pruefen":
        for p in argv[1:]:
            print(p, nums(p))
        return 0
    text = open(argv[2], "rb").read().decode("latin1")
    gut = 0
    bad = 0
    for path in argv[3:]:
        name = path.split("/")[-1]
        w = nums(path)
        g = gast(text, name)
        if g is None:
            print("  FAIL  %-16s the guest said nothing" % name)
            bad += 1
            continue
        if vergleich(g, w, name):
            gut += 1
        else:
            bad += 1
    print("bildref: %d of %d images match Pillow"
          % (gut, gut + bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
