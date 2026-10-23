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
# bundle -> (glyph, top colour, bottom colour, fill the closed shapes with a tint)
# r1016: NO tile.  The picture is the glyph itself: a coloured vertical gradient stroke with round
# caps/joins (so it is rounded by itself) over a soft tint of the same hue where the shape is
# closed.  Everything else stays transparent, so the taskbar, the start menu and the explorer show
# the glyph on their own background like Windows 11 does.
APPS = {
    "editor":    ("square-pen",       "fbbf24", "d97706", True),
    "nedit":     ("file-pen",         "fb923c", "ea580c", True),
    "explorer":  ("folder",           "fbbf24", "f59e0b", True),
    "launcher":  ("search",           "60a5fa", "2563eb", False),
    "settings":  ("settings",         "94a3b8", "64748b", True),
    "terminal":  ("square-terminal",  "4ade80", "16a34a", True),
    "installer": ("download",         "a78bfa", "7c3aed", False),
    "trashbin":  ("trash-2",          "2dd4bf", "0d9488", True),
    "pdfview":   ("file-text",        "f87171", "dc2626", True),
    "store":     ("shopping-bag",     "38bdf8", "0284c7", True),
    "taskmgr":   ("activity",         "22d3ee", "0891b2", False),
    "certus":    ("globe",            "818cf8", "4f46e5", True),
    "widgets":   ("layout-grid",      "c084fc", "9333ea", True),
    "welcome":   ("smile",            "f472b6", "db2777", True),
    "run":       ("square-play",      "fb923c", "ea580c", True),
    "cliphist":  ("clipboard-list",   "2dd4bf", "0d9488", True),
    "charmap":   ("omega",            "a78bfa", "7c3aed", False),
    # W-ICON: the programs that had no symbol (the bar showed the letter tile)
    "disks":     ("hard-drive",       "94a3b8", "475569", True),
    "snip":      ("scissors",         "f472b6", "be185d", False),
    "viewer":    ("image",            "38bdf8", "0369a1", True),
    "jarvismini": ("message-circle",  "60a5fa", "1d4ed8", True),
}
# bundles that do not live in assets/apps (the personal stick builds them from pakete/<name>)
EXTRA_DIRS = {"jarvismini": "pakete/jarvismini"}


def glyph_inner(svg_text):
    m = re.search(r"<svg[^>]*>(.*)</svg>", svg_text, re.S)
    return m.group(1)


def tile(inner, top, bot, tint=True):
    """Name kept for the callers: it draws the transparent glyph picture, not a tile."""
    pad = 1.5
    sc = (SIZE - 2 * pad) / 24.0
    fill = 'fill="url(#g)" fill-opacity="0.38"' if tint else 'fill="none"'
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="{pad}" x2="0" y2="{SIZE-pad}">
      <stop offset="0" stop-color="#{top}"/><stop offset="1" stop-color="#{bot}"/>
    </linearGradient>
  </defs>
  <g transform="translate({pad},{pad}) scale({sc})" {fill} stroke="url(#g)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">{inner}</g>
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
    for app, (glyph, top, bot, tint) in APPS.items():
        d = os.path.join(dst, app + ".osp")
        if not os.path.isdir(d) and app in EXTRA_DIRS:
            d = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(dst.rstrip("/")))), EXTRA_DIRS[app])
        if not os.path.isdir(d):
            print("skip", app)
            continue
        inner = glyph_inner(open(os.path.join(src, glyph + ".svg"), encoding="utf-8").read())
        im = render(tile(inner, top, bot, tint))
        with open(os.path.join(d, "symbol.osym"), "wb") as f:
            f.write(osym(im))
        im.save("/tmp/mkicons-%s.png" % app) if os.environ.get("MKICONS_PNG") else None
        print("%s/symbol.osym %dx%d" % (d, im.width, im.height))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
