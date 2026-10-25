#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import re
import sys
from collections import Counter

import cairosvg
import numpy as np
from PIL import Image

ROWS = {0: "explorer", 2: "settings"}


def load_ppm(path):
    d = open(path, "rb").read()
    fields = []
    at = 2
    while len(fields) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        fields.append(int(d[s:at]))
    w, h = fields[0], fields[1]
    return np.frombuffer(d[at + 1:at + 1 + w * h * 3], dtype=np.uint8).reshape(h, w, 3).astype(np.float64)


def geometry(serial):
    g = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", serial)[-1]
    r = re.findall(r"launcher: rows x=(\d+) base=(\d+) zh=(\d+)", serial)[-1]
    c = re.findall(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", serial)[-1]
    return [int(v) for v in g], [int(v) for v in r], [int(v) for v in c]


def best_fit(shot, ref_rgba, x_lo, x_hi, y_lo, y_hi):
    tile = ref_rgba.shape[0]
    alpha = ref_rgba[..., 3:4] / 255.0
    rgb = ref_rgba[..., :3]
    region = shot[y_lo:y_hi + tile, x_lo:x_hi + tile].reshape(-1, 3)
    bg = np.array(Counter(map(tuple, region.astype(int))).most_common(1)[0][0], dtype=np.float64)
    want = rgb * alpha + bg * (1 - alpha)
    best = (1e9, 0, 0)
    for y in range(y_lo, y_hi + 1):
        for x in range(x_lo, x_hi + 1):
            e = float(np.abs(shot[y:y + tile, x:x + tile] - want).mean())
            if e < best[0]:
                best = (e, x, y)
    return best


def main(out, scale, root):
    serial = open(os.path.join(out, "serial.txt"), errors="replace").read()
    shot = load_ppm(os.path.join(out, "01-search.ppm"))
    (gx, gy, _, _), (_, base, zh), (lx, _, _, _) = geometry(serial)
    tile = 32 * scale
    errs = []
    for row, app in sorted(ROWS.items()):
        svg = os.path.join(root, "assets/apps/%s.osp/symbol.svg" % app)
        ref = np.asarray(Image.open(io.BytesIO(cairosvg.svg2png(url=svg, output_width=tile, output_height=tile))).convert("RGBA")).astype(np.float64)
        top = gy + base + zh * row
        x0 = gx + lx
        e, x, y = best_fit(shot, ref, x0, x0 + 30 * scale, top - 12 * scale, top + zh - tile)
        print("row %d %s: tile %d error %.2f at %d,%d" % (row, app, tile, e, x, y))
        errs.append(e)
    print("MEAN %.3f" % (sum(errs) / len(errs)))
    return sum(errs) / len(errs)


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else ".")
