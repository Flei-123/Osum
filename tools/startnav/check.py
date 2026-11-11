#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

from PIL import Image

ACCENT = (37, 99, 235)
ACCENT_DISTANCE = 40
RING_MIN_PIXELS = 30
RING_MAX_PIXELS_OFF = 4
TILE_PATTERN = re.compile(r"launcher: tile i=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
GEOM_PATTERN = re.compile(r"launcher: geom x=(\d+) y=(\d+)")


def read_geometry(serial_path):
    geometry = None
    tiles = {}
    for line in open(serial_path, errors="replace"):
        match = GEOM_PATTERN.search(line)
        if match:
            geometry = (int(match.group(1)), int(match.group(2)))
        match = TILE_PATTERN.search(line)
        if match:
            tiles[int(match.group(1))] = tuple(int(match.group(k)) for k in range(2, 6))
    return geometry, tiles


def ring_pixels(image, rect):
    x, y, w, h = rect
    count = 0
    for py in range(y, y + h):
        for px in range(x, x + w):
            pixel = image.getpixel((px, py))
            if sum(abs(pixel[k] - ACCENT[k]) for k in range(3)) <= ACCENT_DISTANCE:
                count += 1
    return count


def main():
    shot, serial, expected = sys.argv[1], sys.argv[2], int(sys.argv[3])
    scale = int(sys.argv[4])
    geometry, tiles = read_geometry(serial)
    if geometry is None or not tiles:
        print("no launcher geometry in the serial log")
        sys.exit(1)
    image = Image.open(shot).convert("RGB")
    counts = {}
    for index, (tx, ty, tw, th) in sorted(tiles.items()):
        counts[index] = ring_pixels(image, (geometry[0] + tx, geometry[1] + ty, tw, th))
    print("ring pixels per tile %s, expected %s, scale %d" % (counts, expected if expected >= 0 else "none", scale))
    ok = True
    for index, count in counts.items():
        if index == expected:
            ok = ok and count >= RING_MIN_PIXELS * scale
        else:
            ok = ok and count <= RING_MAX_PIXELS_OFF * scale
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
