#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import sys

import cairosvg
from PIL import Image, ImageDraw

SIZES = (16, 24, 32, 48, 72)
THEMES = (("light", (255, 255, 255)), ("dark", (17, 28, 46)))
PAD = 8
LABEL_H = 14


def render(path, size):
    png = cairosvg.svg2png(url=path, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def sheet(paths, out, columns=3):
    cell_w = 96 + sum(SIZES) + PAD * (len(SIZES) + 1)
    row_h = max(SIZES) + PAD
    rows = -(-len(paths) // columns)
    block_h = rows * row_h + PAD
    img = Image.new("RGB", (cell_w * columns, block_h * len(THEMES)), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    for t, (name, bg) in enumerate(THEMES):
        y0 = t * block_h
        draw.rectangle([0, y0, img.width, y0 + block_h], fill=bg)
        fg = (20, 30, 50) if name == "light" else (220, 228, 240)
        for i, path in enumerate(paths):
            col, row = divmod(i, rows)
            x = col * cell_w
            y = y0 + PAD // 2 + row * row_h
            draw.text((x + 4, y + max(SIZES) // 2 - 5), os.path.basename(path)[:-4][:14], fill=fg)
            x += 96
            for s in SIZES:
                icon = render(path, s)
                img.paste(icon, (x, y + (max(SIZES) - s) // 2), icon)
                x += s + PAD
    img.save(out)


if __name__ == "__main__":
    sheet(sorted(sys.argv[2:]), sys.argv[1])
