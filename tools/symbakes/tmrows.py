#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import sys

import cairosvg
import numpy as np
from PIL import Image
from scipy.signal import fftconvolve

APPS = ("launcher",)


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


def reference(svg, size):
    png = cairosvg.svg2png(url=svg, output_width=size, output_height=size)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(np.float64)


def locate(shot, ref):
    alpha = ref[..., 3] / 255.0
    rgb = ref[..., :3]
    h, w = alpha.shape
    ones = np.ones((h, w))
    num = 0.0
    sq = 0.0
    for c in range(3):
        ch = shot[..., c]
        num = num + fftconvolve(ch, (alpha * rgb[..., c])[::-1, ::-1], mode="valid")
        sq = sq + fftconvolve(ch * ch, alpha[::-1, ::-1], mode="valid")
    tmpl = float((alpha[..., None] * rgb * rgb).sum())
    cost = sq - 2 * num + tmpl
    y, x = np.unravel_index(int(np.argmin(cost)), cost.shape)
    return int(x), int(y)


def tile_error(shot, ref, x, y):
    size = ref.shape[0]
    alpha = ref[..., 3:4] / 255.0
    bg = shot[max(y - 1, 0), max(x - 1, 0)]
    want = ref[..., :3] * alpha + bg * (1 - alpha)
    return float(np.abs(shot[y:y + size, x:x + size] - want).mean())


def main(out, scale, root):
    shot = load_ppm(os.path.join(out, "tm.ppm"))
    errs = []
    for app in APPS:
        svg = os.path.join(root, "assets/apps", app + ".osp", "symbol.svg")
        best = None
        for size in (22 * scale, 32 * scale):
            ref = reference(svg, size)
            x, y = locate(shot, ref)
            e = tile_error(shot, ref, x, y)
            if best is None or e < best[0]:
                best = (e, size, x, y)
        print("%s err=%.3f size=%d at=%d,%d" % ((app,) + best))
        errs.append(best[0])
    print("MEAN %.3f" % (sum(errs) / len(errs)))


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3])
