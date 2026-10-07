#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/mkboards.py -- the before/after boards of the design audit (r399).

    mkboards.py <outdir> <old-dir> <before-dir> <after-dir> [<view-name> ...]

<old-dir>     photographs of the OLD stand (before the fUi scene tree programs)
<before-dir>  photographs of main before this round
<after-dir>   photographs after

Every directory holds the PNGs of tools/design/audit.sh (01-schreibtisch.png,
02-startmenue.png, 03-einstellungen.png, 04-explorer.png, 05-dialog.png,
06-editor.png, 07-kontrollzentrum.png).  For every view that exists in all
directories one board <view>.png is written with the three pictures side by side
and labelled; zoomed detail boards (text, wallpaper, corner, icons) are made
by the extra functions below from the same pictures.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

VIEWS = ["01-schreibtisch", "02-startmenue", "03-einstellungen", "04-explorer",
         "05-dialog", "06-editor", "07-kontrollzentrum"]


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def board(path, panels, scale=1.0, crop=None, zoom=1):
    ims = []
    for lab, p in panels:
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        if crop:
            im = im.crop(crop)
        if zoom != 1:
            im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        elif scale != 1.0:
            im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
        ims.append((lab, im))
    if len(ims) < 2:
        return False
    pad, head = 10, 34
    W = sum(i.width for _l, i in ims) + pad * (len(ims) + 1)
    H = max(i.height for _l, i in ims) + head + pad
    b = Image.new("RGB", (W, H), (28, 30, 36))
    d = ImageDraw.Draw(b)
    f = font(17)
    x = pad
    for lab, im in ims:
        d.text((x, 8), lab, fill=(235, 235, 240), font=f)
        b.paste(im, (x, head))
        x += im.width + pad
    b.save(path)
    return True


def main(argv):
    out, old, before, after = argv[:4]
    only = argv[4:]
    os.makedirs(out, exist_ok=True)
    for v in VIEWS:
        if only and v not in only:
            continue
        panels = [("old stand (before the scene tree)", os.path.join(old, v + ".png")),
                  ("main before this round", os.path.join(before, v + ".png")),
                  ("after", os.path.join(after, v + ".png"))]
        if board(os.path.join(out, "vergleich-%s.png" % v), panels, scale=0.62):
            print("vergleich-%s.png" % v)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
