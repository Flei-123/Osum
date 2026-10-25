#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import re
import sys

import cairosvg
import numpy as np
from PIL import Image

PINS = ["explorer", "settings"]


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
    return np.frombuffer(d[at + 1:at + 1 + w * h * 3], dtype=np.uint8).reshape(h, w, 3).astype(np.int32)


def bar_geometry(serial):
    g = re.findall(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", serial)
    x, y, w, h = [int(v) for v in g[-1]]
    return y, h


def segments(img, y0, h):
    band = img[y0 + 2:y0 + h - 2]
    bg = band[h // 2 - 2, 6]
    ink = (np.abs(band - bg).max(axis=2) > 14).any(axis=0)
    segs = []
    start = None
    gap = 0
    for x, v in enumerate(ink):
        if v:
            if start is None:
                start = x
            gap = 0
            last = x
        elif start is not None:
            gap += 1
            if gap >= 5:
                segs.append((start, last))
                start = None
    return bg, segs


def reference(svg_path, size, bg):
    png = cairosvg.svg2png(url=svg_path, output_width=size, output_height=size)
    im = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(np.float64)
    a = im[:, :, 3:4] / 255.0
    return im[:, :, :3] * a + np.asarray(bg, dtype=np.float64) * (1 - a)


def best_match(img, svg_path, seg, y0, h, bg):
    best = (1e9, 0, 0, 0)
    for size in range(20, 81):
        ref = reference(svg_path, size, bg)
        cy = y0 + h // 2
        for ox in range(seg[0] - 10, seg[0] + 3):
            for oy in range(cy - size // 2 - 4, cy - size // 2 + 5):
                crop = img[oy:oy + size, ox:ox + size]
                if crop.shape[:2] != (size, size):
                    continue
                err = float(np.abs(crop - ref).mean())
                if err < best[0]:
                    best = (err, size, ox, oy)
    return best


def main(argv):
    out, scale, root = argv[0], int(argv[1]), argv[2]
    serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
    img = load_ppm(os.path.join(out, "00-bar.ppm"))
    y0, h = bar_geometry(serial)
    bg, segs = segments(img, y0, h)
    print("bar y=%d h=%d segments=%s" % (y0, h, segs))
    errs = []
    sizes = []
    for i, app in enumerate(PINS):
        if i + 1 >= len(segs):
            print("MISSING %s" % app)
            return 1
        err, size, ox, oy = best_match(img, os.path.join(root, "assets/apps/%s.osp/symbol.svg" % app), segs[i + 1], y0, h, bg)
        print("%s err=%.2f size=%d at=%d,%d" % (app, err, size, ox, oy))
        errs.append(err)
        sizes.append(size)
    print("RESULT scale=%d err=%.2f size=%d" % (scale, max(errs), sizes[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
