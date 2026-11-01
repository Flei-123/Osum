#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys, os
from PIL import Image
a, b, c = sys.argv[1], sys.argv[2], sys.argv[3]
bad = 0
keep = os.environ.get("KEEPPICS")
for n in ("c1-idle", "c2-menu", "c3-explorer"):
    try:
        ia = Image.open("%s/%s.ppm" % (a, n)).convert("RGB")
        ib = Image.open("%s/%s.ppm" % (b, n)).convert("RGB")
        ic = Image.open("%s/%s.ppm" % (c, n)).convert("RGB")
    except Exception as e:
        print("  cannot read", n, e); bad += 1; continue
    if ia.size != ib.size or ia.size != ic.size:
        print("  size differs in", n); bad += 1; continue
    w, h = ia.size
    if os.environ.get("SHARED_CMP_TAMPER"):
        for ty in range(300, 330):
            for tx in range(600, 630):
                ib.putpixel((tx, ty), (255, 0, 255))
    pa, pb, pc = ia.load(), ib.load(), ic.load()
    diff = []
    noise = 0
    for y in range(h):
        for x in range(w):
            if (x >= w - 220 and y < 110) or (x >= w - 160 and y >= h - 80):
                continue
            if x < 100 and y >= 725:
                continue
            if x < 72 and 60 <= y < 460:
                continue
            if pa[x, y] != pb[x, y]:
                if pa[x, y] != pc[x, y]:
                    noise += 1
                else:
                    diff.append((x, y))
    print("  %-14s %d differing pixels (+%d that differ between two shared runs too: noise)" % (n, len(diff), noise), ("first " + str(diff[:3])) if diff else "")
    if keep:
        os.makedirs(keep, exist_ok=True)
        for tag, im in (("shr", ia), ("nsh", ib), ("shr2", ic)):
            im.save("%s/%s-%s.png" % (keep, n, tag))
    if len(diff) > 512:
        bad += 1
sys.exit(1 if bad else 0)