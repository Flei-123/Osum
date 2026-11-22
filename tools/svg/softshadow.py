#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

import numpy as np
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from scipy.ndimage import gaussian_filter
from scipy.optimize import nnls

GRID = 256
SUPERSAMPLE = 4
OFFSETS = (-8, -5, -2, 1, 4, 7, 10, 13, 17, 21)
MIN_ALPHA = 0.004
OUT_SIZE = 72
SERIF_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"

SHADOW_RE = re.compile(
    r'<path d="M(?P<x>[\d.]+),(?P<y>[\d.]+) a(?P<rx>[\d.]+),(?P<ry>[\d.]+) 0 1 0 [\d.]+,0 a[^"]*"'
    r' fill="#000000" opacity="(?P<op>[\d.]+)" filter="url\(#blur\)"/>')
FILTER_RE = re.compile(r'<filter id="blur".*?</filter>\s*', re.S)
SIGMA_RE = re.compile(r'stdDeviation="([\d.]+)"')
TEXT_RE = re.compile(
    r'<text x="(?P<x>[\d.]+)" y="(?P<y>[\d.]+)" font-size="(?P<size>[\d.]+)"[^>]*fill="(?P<fill>#[0-9a-fA-F]+)">'
    r'&#(?P<code>\d+);</text>')
HIDDEN_RE = re.compile(r'<[^>]*opacity="0\.0"[^>]*/>\s*')
HEAD_RE = re.compile(r'<svg [^>]*>')


def ellipse_mask(cx, cy, rx, ry):
    axis = (np.arange(GRID * SUPERSAMPLE) + 0.5) / SUPERSAMPLE
    gx, gy = np.meshgrid(axis, axis)
    inside = ((gx - cx) / rx) ** 2 + ((gy - cy) / ry) ** 2 <= 1.0
    return inside.reshape(GRID, SUPERSAMPLE, GRID, SUPERSAMPLE).mean(axis=(1, 3))


def fit_layers(cx, cy, rx, ry, opacity, sigma):
    target = opacity * gaussian_filter(ellipse_mask(cx, cy, rx, ry), sigma)
    rows = [ellipse_mask(cx, cy, rx + t, max(ry + t, 1.0)).ravel() for t in OFFSETS]
    weights, _ = nnls(np.stack(rows, axis=1), -np.log(1.0 - np.clip(target.ravel(), 0.0, 0.999)))
    return [(t, 1.0 - float(np.exp(-w))) for t, w in zip(OFFSETS, weights)]


def stacked_ellipses(match, sigma):
    rx, ry = float(match["rx"]), float(match["ry"])
    cx, cy = float(match["x"]) + rx, float(match["y"])
    layers = fit_layers(cx, cy, rx, ry, float(match["op"]), sigma)
    out = []
    for t, alpha in sorted(layers, key=lambda item: -item[0]):
        if alpha >= MIN_ALPHA:
            out.append('<ellipse cx="%g" cy="%g" rx="%g" ry="%g" fill="#000000" opacity="%.3f"/>'
                       % (cx, cy, rx + t, max(ry + t, 1.0), alpha))
    return "\n".join(out)


def glyph_path(match):
    font = TTFont(SERIF_FONT)
    glyph_name = font.getBestCmap()[int(match["code"])]
    scale = float(match["size"]) / font["head"].unitsPerEm
    advance = font["hmtx"][glyph_name][0] * scale
    pen = SVGPathPen(font.getGlyphSet())
    flip = TransformPen(pen, (scale, 0, 0, -scale, float(match["x"]) - advance / 2, float(match["y"])))
    font.getGlyphSet()[glyph_name].draw(flip)
    return '<path d="%s" fill="%s"/>' % (pen.getCommands(), match["fill"])


def convert(text):
    sigma_match = SIGMA_RE.search(text)
    sigma = float(sigma_match.group(1)) if sigma_match else 0.0
    text = FILTER_RE.sub("", text)
    shadow = SHADOW_RE.search(text)
    if shadow is not None and sigma > 0.0:
        text = text.replace(shadow.group(0), stacked_ellipses(shadow, sigma))
    glyph = TEXT_RE.search(text)
    if glyph is not None:
        text = text.replace(glyph.group(0), glyph_path(glyph))
    text = HIDDEN_RE.sub("", text)
    return HEAD_RE.sub(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 256 256">' % (OUT_SIZE, OUT_SIZE),
        text, count=1)


def main(argv):
    if len(argv) != 3:
        print("usage: softshadow.py <in.svg> <out.svg>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as src:
        converted = convert(src.read())
    with open(argv[2], "w", encoding="utf-8") as dst:
        dst.write(converted)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
