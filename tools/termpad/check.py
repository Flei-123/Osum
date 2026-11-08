#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

from PIL import Image

PAD_POINTS = 8
X_SLACK_POINTS = 3
Y_SLACK_POINTS = 12
MIN_INK_PIXELS = 20


def margins(shot, box):
    image = Image.open(shot).convert("RGB").crop(box)
    colors = image.getcolors(image.width * image.height)
    background = max(colors, key=lambda item: item[0])[1]
    pixels = image.load()
    width, height = image.size
    xs, ys, ink = [], [], []
    for y in range(height):
        for x in range(width):
            if pixels[x, y] == background:
                xs.append(x)
                ys.append(y)
    client_x, client_y = min(xs), min(ys)
    client_right, client_bottom = max(xs), max(ys)
    for y in range(client_y, client_bottom + 1):
        for x in range(client_x, client_right + 1):
            if pixels[x, y] != background:
                ink.append((x, y))
    if len(ink) < MIN_INK_PIXELS:
        return None
    return min(x for x, _ in ink) - client_x, min(y for _, y in ink) - client_y


def main():
    shot, scale, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    box = tuple(int(v) for v in sys.argv[4:8])
    found = margins(shot, box)
    if found is None:
        print("no terminal text found")
        sys.exit(1)
    left, top = found
    pad = PAD_POINTS * scale
    padded = left >= pad and top >= pad
    bounded = left <= pad + X_SLACK_POINTS * scale and top <= pad + Y_SLACK_POINTS * scale
    print("margin left=%d top=%d px (pad %d px)" % (left, top, pad))
    good = padded and bounded
    sys.exit(0 if good == (mode == "padded") else 1)


if __name__ == "__main__":
    main()
