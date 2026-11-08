#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

from PIL import Image

PAD_POINTS = 8
X_SLACK_POINTS = 3
Y_SLACK_POINTS = 12
MIN_INK_PIXELS = 20
PROBE_INSET = 10


def run_start(is_bg, last):
    start = last
    while start > 0 and is_bg(start - 1):
        start -= 1
    return start


def margins(shot, box):
    image = Image.open(shot).convert("RGB").crop(box)
    colors = image.getcolors(image.width * image.height)
    background = max(colors, key=lambda item: item[0])[1]
    pixels = image.load()
    width, height = image.size
    xs = [x for x in range(width) for y in range(height) if pixels[x, y] == background]
    ys = [y for x in range(width) for y in range(height) if pixels[x, y] == background]
    if not xs:
        return None
    probe_x = max(xs) - PROBE_INSET
    probe_y = max(ys) - PROBE_INSET
    client_x = run_start(lambda x: pixels[x, probe_y] == background, probe_x)
    client_y = run_start(lambda y: pixels[probe_x, y] == background, probe_y)
    ink = [
        (x, y)
        for y in range(client_y, probe_y + 1)
        for x in range(client_x, probe_x + 1)
        if pixels[x, y] != background
    ]
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
