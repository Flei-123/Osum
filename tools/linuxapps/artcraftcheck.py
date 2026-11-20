#!/usr/bin/env python3
import sys

WINDOW_BOX = (16, 40, 1276, 728)
MIN_LIGHT_SHARE = 0.30
MIN_DIFF_PIXELS = 300


def read_ppm(path):
    data = open(path, "rb").read()
    parts = data.split(None, 4)
    if parts[0] != b"P6":
        raise ValueError("not a P6 ppm: " + path)
    width, height = int(parts[1]), int(parts[2])
    offset = len(data) - width * height * 3
    return width, height, data[offset:]


def window_pixels(path):
    width, height, raw = read_ppm(path)
    x0, y0, x1, y1 = WINDOW_BOX
    pixels = []
    for y in range(y0, min(y1, height)):
        row = raw[(y * width + x0) * 3:(y * width + min(x1, width)) * 3]
        pixels.append(row)
    return pixels


def light_share(rows):
    light = total = 0
    for row in rows:
        for i in range(0, len(row), 3):
            total += 1
            if row[i] > 200 and row[i + 1] > 200 and row[i + 2] > 200:
                light += 1
    return light / max(total, 1)


def diff_pixels(rows_a, rows_b):
    changed = 0
    for row_a, row_b in zip(rows_a, rows_b):
        if row_a == row_b:
            continue
        for i in range(0, len(row_a), 3):
            if row_a[i:i + 3] != row_b[i:i + 3]:
                changed += 1
    return changed


def main():
    shot = window_pixels(sys.argv[1])
    share = light_share(shot)
    print("ARTCRAFT-CHECK light_share=%.3f" % share)
    ok = share >= MIN_LIGHT_SHARE
    if len(sys.argv) > 2:
        changed = diff_pixels(shot, window_pixels(sys.argv[2]))
        print("ARTCRAFT-CHECK typed_diff_pixels=%d" % changed)
        ok = ok and changed >= MIN_DIFF_PIXELS
    print("ARTCRAFT-CHECK %s" % ("green" if ok else "red"))
    sys.exit(0 if ok else 1)


main()
