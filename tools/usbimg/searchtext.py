#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    searchtext.py <ppm> <ttf> <px> <text> [--tol N] [--min P] [--nicht]
"""
import os
import sys

import numpy as np

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, "..", "ttf"))
import raster  # noqa: E402


def ppm_read(path_2):
    roh = open(path_2, "rb").read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % path_2)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1
    w, h, _ = felder
    d = np.frombuffer(roh[i:i + w * h * 3], dtype=np.uint8)
    return d.reshape(h, w, 3).astype(np.int16)


def points(text, ttf, px, deckung):
    if ttf.startswith("fui:"):
        import fuiraster
        s = fuiraster.Font(ttf[4:], px)
    else:
        s = raster.Font(ttf, px)
    voll = []
    rand = []
    for (c, x26) in s.ask(text):
        g = s.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        gx = x26 >> 6
        for r in range(g.h):
            for k in range(g.w):
                a = g.punkt(k, r)
                dx = gx + g.left + k
                dy = 0 - g.top_2 + r
                if a >= deckung:
                    voll.append((dx, dy))
                elif a == 0:
                    rand.append((dx, dy))
    return voll, rand, s


def search(image, voll, rand, tol):
    h, w, _ = image.shape
    xs = [p[0] for p in voll] + [p[0] for p in rand]
    ys = [p[1] for p in voll] + [p[1] for p in rand]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    bw = x1 - x0 + 1
    bh = y1 - y0 + 1
    if bw >= w or bh >= h:
        return None
    nx = w - bw + 1
    ny = h - bh + 1

    def area(dx, dy):
        ax = dx - x0
        ay = dy - y0
        return image[ay:ay + ny, ax:ax + nx, :]

    first = area(voll[0][0], voll[0][1])
    treffer = np.zeros((ny, nx), dtype=np.int32)
    for (dx, dy) in voll:
        f = area(dx, dy)
        eq = (np.abs(f - first) <= tol).all(axis=2)
        treffer += eq.astype(np.int32)
    gegen = np.zeros((ny, nx), dtype=np.int32)
    schritt = max(1, len(rand) // 400)
    genommen = rand[::schritt]
    for (dx, dy) in genommen:
        f = area(dx, dy)
        changed = (np.abs(f - first) > tol).any(axis=2)
        gegen += changed.astype(np.int32)

    anteil_tinte = treffer / float(len(voll))
    anteil_gegen = gegen / float(max(1, len(genommen)))
    punktzahl = np.minimum(anteil_tinte, anteil_gegen)
    idx = int(np.argmax(punktzahl))
    yy, xx = divmod(idx, nx)
    return (xx - x0, yy - y0, float(anteil_tinte[yy, xx]),
            float(anteil_gegen[yy, xx]), float(punktzahl[yy, xx]),
            len(voll), len(genommen))


def main(argv):
    if len(argv) < 5:
        print(__doc__)
        return 2
    ppm, ttf, px, text = argv[1], argv[2], int(argv[3]), argv[4]
    tol = 12
    mind = 0.97
    deckung = 255
    nicht = "--nicht" in argv
    for i, a in enumerate(argv):
        if a == "--tol":
            tol = int(argv[i + 1])
        if a == "--min":
            mind = float(argv[i + 1])
        if a == "--deckung":
            deckung = int(argv[i + 1])
    image = ppm_read(ppm)
    voll, rand, _ = points(text, ttf, px, deckung)
    if not voll:
        print("die Zeile '%s' hat keinen einzigen vollgedeckten Punkt" % text)
        return 2
    e = search(image, voll, rand, tol)
    if e is None:
        print("the line is larger than the image")
        return 2
    x, y, at, ag, p, nv, ng = e
    wie = ("'%s' bei x=%d Grundlinie=%d: %d%% der %d Tintenpunkte, "
           "%d%% der %d Gegenpunkte" %
           (text, x, y, round(at * 100), nv, round(ag * 100), ng))
    if nicht:
        if p >= mind:
            print("FOUND although it must NOT be there -- %s" % wie)
            return 1
        print("not found (best value %d%%) -- %s" % (round(p * 100), wie))
        return 0
    if p >= mind:
        print(wie)
        return 0
    print("NOT found (best value %d%%) -- %s" % (round(p * 100), wie))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
