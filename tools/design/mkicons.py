#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/mkicons.py -- the program icons of the bundles, as VECTOR drawings baked to 32x32.

    mkicons.py <lucide-svg-dir> <assets/apps>

r399 (design audit).  The program icons were 16x16 hand-made pixel art
(assets/apps/*/symbol.txt) that every consumer multiplied by an integer: on a
40 px bar a 16 px square among 24 px Win11 icons.  Here each program gets a
rounded tile with a vertical gradient and a white Lucide glyph (ISC licence,
https://lucide.dev), drawn as SVG at 4x and reduced with Lanczos, written as
`symbol.osym` (format OSYM: "OSYM", width, height, then B G R A per pixel)
into the bundle.  tools/k15/bundle.py takes `symbol.osym` before `symbol.txt`;
the consumers draw the picture at the size they need (wlibc.icon_draw_fit,
fuiscene.row_icon) -- bilinear when growing, a box filter when shrinking.
"""
import io
import os
import re
import struct
import sys

import cairosvg
from PIL import Image

SIZE = 32
# bundle -> (glyph, top colour, bottom colour)
APPS = {
    "editor":    ("square-pen",       "f59e0b", "d97706"),
    "nedit":     ("file-pen",         "fb923c", "ea580c"),
    "explorer":  ("folder",           "3b82f6", "1d4ed8"),
    "launcher":  ("search",           "64748b", "334155"),
    "settings":  ("settings",         "64748b", "334155"),
    "terminal":  ("square-terminal",  "22c55e", "15803d"),
    "installer": ("download",         "8b5cf6", "6d28d9"),
    "papierkorb": ("trash-2",         "14b8a6", "0f766e"),
    "pdfview":   ("file-text",        "ef4444", "b91c1c"),
    "store":     ("shopping-bag",     "0ea5e9", "0369a1"),
    "taskmgr":   ("activity",         "06b6d4", "0e7490"),
    "certus":    ("globe",            "6366f1", "4338ca"),
    "widgets":   ("layout-grid",      "a855f7", "7e22ce"),
}


def glyph_inner(svg_text):
    m = re.search(r"<svg[^>]*>(.*)</svg>", svg_text, re.S)
    return m.group(1)


def tile(inner, top, bot):
    pad = 7.0
    sc = (SIZE - 2 * pad) / 24.0
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#{top}"/><stop offset="1" stop-color="#{bot}"/>
    </linearGradient>
    <linearGradient id="h" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.28"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="1" y="1" width="{SIZE-2}" height="{SIZE-2}" rx="8" fill="url(#g)"/>
  <rect x="1" y="1" width="{SIZE-2}" height="{SIZE-2}" rx="8" fill="url(#h)"/>
  <g transform="translate({pad},{pad}) scale({sc})" fill="none" stroke="#ffffff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">{inner}</g>
</svg>'''
    return svg


def render(svg):
    big = cairosvg.svg2png(bytestring=svg.encode(), output_width=SIZE * 4, output_height=SIZE * 4)
    im = Image.open(io.BytesIO(big)).convert("RGBA")
    im = im.convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    return im


def osym(im):
    out = bytearray(b"OSYM" + struct.pack("<II", im.width, im.height))
    for r, g, b, a in im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata():
        out += bytes((b, g, r, a))
    return bytes(out)


def main(argv):
    src, dst = argv[0], argv[1]
    for app, (glyph, top, bot) in APPS.items():
        d = os.path.join(dst, app + ".osp")
        if not os.path.isdir(d):
            print("skip", app)
            continue
        inner = glyph_inner(open(os.path.join(src, glyph + ".svg"), encoding="utf-8").read())
        im = render(tile(inner, top, bot))
        with open(os.path.join(d, "symbol.osym"), "wb") as f:
            f.write(osym(im))
        im.save("/tmp/mkicons-%s.png" % app) if os.environ.get("MKICONS_PNG") else None
        print("%s/symbol.osym %dx%d" % (d, im.width, im.height))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
