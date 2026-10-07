#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/board.py -- put pictures side by side on one labelled board.

    board.py <out.png> [--crop x0,y0,x1,y1] [--zoom N] <label>=<image> ...

Every image is cropped with the same box (default: whole picture), scaled by
the same integer zoom (nearest neighbour, so pixels stay visible) and placed
left to right under its label.  The design audit (r399) uses it for the
before/after boards in docs/shots/design-audit/.
"""
import sys
from PIL import Image, ImageDraw, ImageFont


def main(argv):
    out = argv[0]
    crop = None
    zoom = 1
    items = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--crop":
            crop = tuple(int(v) for v in argv[i + 1].split(","))
            i += 2
        elif a == "--zoom":
            zoom = int(argv[i + 1])
            i += 2
        else:
            lab, _, path = a.partition("=")
            items.append((lab, path))
            i += 1
    ims = []
    for lab, path in items:
        im = Image.open(path).convert("RGB")
        if crop:
            im = im.crop(crop)
        if zoom != 1:
            im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        ims.append((lab, im))
    pad, head = 12, 30
    W = sum(im.width for _l, im in ims) + pad * (len(ims) + 1)
    H = max(im.height for _l, im in ims) + head + pad * 2
    board = Image.new("RGB", (W, H), (32, 32, 36))
    d = ImageDraw.Draw(board)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    except Exception:
        f = ImageFont.load_default()
    x = pad
    for lab, im in ims:
        d.text((x, pad // 2 + 4), lab, fill=(240, 240, 240), font=f)
        board.paste(im, (x, head + pad // 2))
        x += im.width + pad
    board.save(out)
    print("%s %dx%d" % (out, W, H))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
