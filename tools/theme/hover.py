#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/theme/hover.py -- THE HOVER LAYER IS SUBTLE LIKE WINDOWS 11 (W-D r1002, 17.10.2026).

    python3 -I tools/theme/hover.py [<path to model.py>]

Windows 11: a hovered row/button is a faint layer (light ~ black 4-6 %, dark ~ white 6-8 %), not a
ramp step. For every scheme x mode (high contrast excluded: there hover must be loud) this
measures the largest channel distance between

    surface-hover  and its ground:  light surface, dark surface-raised (the card/menu fill)
    control-hover  and its button:  control

and requires  MIN <= distance <= MAX.  MIN keeps the old RUNDE HOVERSTIL promise (a pointer over a
tile changes the picture); MAX is the 'subtle' bar. The counter-proof runs this file on the
model.py of the old main: it MUST fail (23/24 levels).
"""
import os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
model = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "model.py")
schemes = os.path.join(here, "..", "..", "assets", "schemes")
MIN, MAX = 5, 18

def sem(path, mode):
    out = subprocess.run([sys.executable, "-I", model, "semantic", path, mode],
                         capture_output=True, text=True, check=True).stdout
    d = {}
    for ln in out.splitlines():
        i, n, v = ln.split()
        d[n] = int(v, 16)
    return d

def dist(a, b):
    return max(abs(((a >> s) & 255) - ((b >> s) & 255)) for s in (16, 8, 0))

bad = 0
for f in sorted(os.listdir(schemes)):
    if not f.endswith(".scheme"):
        continue
    p = os.path.join(schemes, f)
    if "contrast=high" in open(p).read().replace(" ", ""):
        continue
    for mode in ("light", "dark"):
        d = sem(p, mode)
        ground = d["surface"] if mode == "light" else d["surface-raised"]
        for name, base in (("surface-hover", ground), ("control-hover", d["control"])):
            dd = dist(d[name], base)
            good = MIN <= dd <= MAX
            bad += 0 if good else 1
            print("%s  %-14s %-5s %-13s %06x vs %06x  distance %2d (want %d..%d)" % (
                "OK  " if good else "FAIL", f, mode, name, d[name], base, dd, MIN, MAX))
print("hover: %d outside %d..%d" % (bad, MIN, MAX))
sys.exit(1 if bad else 0)
