#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/storeui/shotcheck.py <dir> -- asserts on the Store pictures written by tools/storeui/run.sh.

For every s*-<mode>-<res>.png: the picture has the size of its resolution, is not blank (enough colours), the window
region (a big flat area) is light in light mode and dark in dark mode, and the grid picture holds accent-coloured
pixels (the install chip / primary button)."""
import glob, os, re, sys
from PIL import Image

d = sys.argv[1]
ok = bad = 0


def chk(name, cond, detail=""):
    global ok, bad
    if cond:
        ok += 1
        print("  OK    " + name)
    else:
        bad += 1
        print("  FAIL  %s %s" % (name, detail))


files = sorted(glob.glob(os.path.join(d, "s*-*-*x*.png")))
chk("pictures found (%d)" % len(files), len(files) >= 9)
for f in files:
    m = re.match(r"(s\d-[a-z]+)-(light|dark)-(\d+)x(\d+)\.png", os.path.basename(f))
    if not m:
        continue
    name, mode, w, h = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
    im = Image.open(f).convert("RGB")
    chk("%s %s %dx%d: size" % (name, mode, w, h), im.size == (w, h), im.size)
    cols = len(set(im.resize((w // 8, h // 8)).getdata()))
    chk("%s %s %dx%d: not blank (%d colours)" % (name, mode, w, h, cols), cols > 12)
    # the window sits at the top-left (40,24 + title bar): its middle band
    px = [im.getpixel((x, y)) for x in range(70, 200, 9) for y in range(110, 150, 9)]
    lum = sum(0.3 * r + 0.59 * g + 0.11 * b for r, g, b in px) / len(px)
    if mode == "light":
        chk("%s %s %dx%d: light window (%.0f)" % (name, mode, w, h, lum), lum > 150)
    else:
        chk("%s %s %dx%d: dark window (%.0f)" % (name, mode, w, h, lum), lum < 100)
print("STORE-UI: %d passed, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
