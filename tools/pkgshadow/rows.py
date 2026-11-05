#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import sys

import cairosvg
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rowicons"))
import rows as base

REFS = ["editor", "nedit", "explorer", "launcher"]
ROW_COUNT = 4
MATCH_LIMIT = 2.0


def reference(root, app, tile):
    svg = os.path.join(root, "assets/apps/%s.osp/symbol.svg" % app)
    png = cairosvg.svg2png(url=svg, output_width=tile, output_height=tile)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(np.float64)


def main(out, root):
    serial = open(os.path.join(out, "serial.txt"), errors="replace").read()
    shot = base.load_ppm(os.path.join(out, "01-search.ppm"))
    (gx, gy, _, _), (_, row_base, zh), (lx, _, _, _) = base.geometry(serial)
    tile = 32
    refs = {app: reference(root, app, tile) for app in REFS}
    errs = []
    editors = 0
    for row in range(ROW_COUNT):
        top = gy + row_base + zh * row
        x0 = gx + lx
        fits = {app: base.best_fit(shot, ref, x0, x0 + 30, top - 12, top + zh - tile)[0] for app, ref in refs.items()}
        app = min(fits, key=fits.get)
        print("row %d best %s error %.2f" % (row, app, fits[app]))
        errs.append(fits[app])
        if app in ("editor", "nedit") and fits[app] <= MATCH_LIMIT:
            editors += 1
    print("ROWS %d" % editors)
    print("MEAN %.3f" % (sum(errs) / len(errs)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ".")
