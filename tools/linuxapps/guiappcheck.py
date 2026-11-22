#!/usr/bin/env python3
import os
import sys

MIN_DISTINCT_COLORS = 6
MIN_INPUT_PIXELS = 20


def read_ppm(path):
    data = open(path, "rb").read()
    parts = data.split(None, 4)
    if parts[0] != b"P6":
        raise ValueError("not a P6 ppm: " + path)
    width, height = int(parts[1]), int(parts[2])
    return width, height, data[len(data) - width * height * 3:]


def box_rows(path, box):
    width, height, raw = read_ppm(path)
    x0, y0, bw, bh = box
    x1 = min(x0 + bw, width)
    return [raw[(y * width + x0) * 3:(y * width + x1) * 3] for y in range(y0, min(y0 + bh, height))]


def distinct_colors(rows):
    seen = set()
    for row in rows:
        for i in range(0, len(row), 3):
            seen.add(row[i:i + 3])
            if len(seen) > 64:
                return len(seen)
    return len(seen)


def diff_pixels(rows_a, rows_b):
    changed = 0
    for row_a, row_b in zip(rows_a, rows_b):
        if row_a != row_b:
            changed += sum(1 for i in range(0, len(row_a), 3) if row_a[i:i + 3] != row_b[i:i + 3])
    return changed


def measure(shot_dir, name, box):
    shot = os.path.join(shot_dir, name + ".ppm")
    pre = os.path.join(shot_dir, name + "-pre.ppm")
    typed = os.path.join(shot_dir, name + "-typed.ppm")
    if not os.path.exists(shot):
        return -1, -1
    colors = distinct_colors(box_rows(shot, box))
    moved = diff_pixels(box_rows(pre, box), box_rows(typed, box)) if os.path.exists(pre) and os.path.exists(typed) else -1
    return colors, moved


def main():
    shot_dir = sys.argv[1]
    for spec in sys.argv[2:]:
        name, _, geometry = spec.partition(":")
        box = tuple(int(v) for v in geometry.split(",")) if geometry else (0, 0, 0, 0)
        colors, moved = measure(shot_dir, name, box) if geometry else (-1, -1)
        print("%s colors=%d input=%d drawn_ok=%d input_ok=%d" % (name, colors, moved, colors >= MIN_DISTINCT_COLORS, moved >= MIN_INPUT_PIXELS))


if __name__ == "__main__":
    main()
