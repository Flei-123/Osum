#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    leistenvergleich.py <output.png> [--height=28] [--x0=0] [--x1=530]
    [--vx0=300] [--vx1=1100] [--zoom=2]
    <image.png>=<Beschriftung> ...
"""
import sys

from PIL import Image, ImageDraw, ImageFont

import glascheck

FONT = "assets/osum-sans.ttf"


def var_von(im, height, x0, x1):
    px = [im.getpixel(p) for p in glascheck.bar(im, height, x0, x1)]
    l = [glascheck.bright(p) for p in px]
    m = sum(l) / len(l)
    return int(sum((v - m) ** 2 for v in l) / len(l) * 100), len(set(px))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    target = argv[1]
    height, x0, x1, zoom = 28, 0, 530, 2
    vx0, vx1 = 300, 1100
    paare = []
    for a in argv[2:]:
        if a.startswith("--height="):
            height = int(a.split("=", 1)[1])
        elif a.startswith("--x0="):
            x0 = int(a.split("=", 1)[1])
        elif a.startswith("--x1="):
            x1 = int(a.split("=", 1)[1])
        elif a.startswith("--vx0="):
            vx0 = int(a.split("=", 1)[1])
        elif a.startswith("--vx1="):
            vx1 = int(a.split("=", 1)[1])
        elif a.startswith("--zoom="):
            zoom = int(a.split("=", 1)[1])
        else:
            file_2, _, text = a.partition("=")
            paare.append((file_2, text))
    try:
        font = ImageFont.truetype(FONT, 14)
    except OSError:
        font = ImageFont.load_default()
    width_2 = (x1 - x0) * zoom
    line = height * zoom
    header = 20
    aus = Image.new("RGB", (width_2, (header + line + 8) * len(paare) + 4),
                    (255, 255, 255))
    mal = ImageDraw.Draw(aus)
    y = 4
    for file_2, text in paare:
        im = Image.open(file_2).convert("RGB")
        w, h = im.size
        var, farben = var_von(im, height, vx0, vx1)
        streifen = im.crop((x0, h - height, min(x1, w), h))
        streifen = streifen.resize((width_2, line), Image.NEAREST)
        mal.text((2, y), "%s   --   var %d, %d Farben" % (text, var, farben),
                 fill=(16, 16, 16), font=font)
        aus.paste(streifen, (0, y + header))
        mal.rectangle([0, y + header, width_2 - 1, y + header + line - 1],
                      outline=(160, 160, 168))
        y = y + header + line + 8
    aus.save(target)
    print("leistenvergleich: %s %dx%d aus %d Aufnahmen"
          % (target, aus.size[0], aus.size[1], len(paare)))
    return 0


if __name__ == "__main__":
    sys.path.insert(0, "tools/themestore")
    sys.exit(main(sys.argv))
