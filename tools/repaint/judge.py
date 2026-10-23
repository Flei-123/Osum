#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/repaint/judge.py <outdir> [--png <dir>] [--max N]
# Compares every inc-<x>.ppm (incremental damage tracking) with ref-<x>.ppm (full recompose after Ctrl+Alt+R).
# Masked: the taskbar clock / tray corner (bottom right 260x48), it changes between the two pictures.
# Prints `repaint: <x> diff=<n> bbox=x0,y0,x1,y1 rows=<n>` and exits 1 when any pair has more than --max differing pixels.
import sys, os, glob
from PIL import Image, ImageChops

def main():
    args = sys.argv[1:]
    out = args[0]
    png = None
    mx = 0
    i = 1
    while i < len(args):
        if args[i] == "--png":
            png = args[i + 1]; i += 2
        elif args[i] == "--max":
            mx = int(args[i + 1]); i += 2
        else:
            i += 1
    if png:
        os.makedirs(png, exist_ok=True)
    bad = 0
    pairs = 0
    for a in sorted(glob.glob(os.path.join(out, "inc-*.ppm"))):
        key = os.path.basename(a)[4:-4]
        b = os.path.join(out, "ref-" + key + ".ppm")
        if not os.path.exists(b):
            print("repaint: %s missing reference" % key); bad += 1; continue
        ia = Image.open(a).convert("RGB"); ib = Image.open(b).convert("RGB")
        if ia.size != ib.size:
            print("repaint: %s size differs" % key); bad += 1; continue
        w, h = ia.size
        d = ImageChops.difference(ia, ib).convert("L").point(lambda v: 255 if v > 12 else 0)
        for x in range(w - 260, w):
            for y in range(h - 48, h):
                d.putpixel((x, y), 0)
        bb = d.getbbox()
        n = sum(1 for v in d.getdata() if v)
        pairs += 1
        rows = len({y for y in range(h) if d.crop((0, y, w, y + 1)).getbbox()}) if n else 0
        print("repaint: %s diff=%d bbox=%s rows=%d" % (key, n, ",".join(map(str, bb)) if bb else "none", rows))
        if png and n:
            ia.save(os.path.join(png, "inc-%s.png" % key)); ib.save(os.path.join(png, "ref-%s.png" % key))
            m = Image.merge("RGB", (d, Image.new("L", (w, h), 0), Image.new("L", (w, h), 0)))
            Image.blend(ib, m, 0.0).save(os.path.join(png, "diff-%s.png" % key))
            ImageChops.screen(ib, m).save(os.path.join(png, "diff-%s.png" % key))
        if n > mx:
            bad += 1
    if pairs == 0:
        print("repaint: no picture pairs"); return 1
    print("repaint: %d pairs, %d over the limit" % (pairs, bad))
    return 1 if bad else 0

sys.exit(main())
