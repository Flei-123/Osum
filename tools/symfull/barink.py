#!/usr/bin/env python3
import sys

from PIL import Image

BAR_HEIGHT = 40
SIDE_SKIP = 4
GAP = 6
MIN_WIDTH = 10
RATIO = 0.25


def ink_columns(image, top, bottom, background, threshold):
    width = image.size[0]
    columns = []
    for x in range(width):
        hit = False
        for y in range(top, bottom):
            r, g, b = image.getpixel((x, y))
            if abs(r - background[0]) + abs(g - background[1]) + abs(b - background[2]) > threshold:
                hit = True
                break
        columns.append(hit)
    return columns


def cells(columns, limit):
    found = []
    start = None
    gap = 0
    for x in range(limit):
        if columns[x]:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= GAP:
                if x - gap - start + 1 >= MIN_WIDTH:
                    found.append((start, x - gap))
                start = None
                gap = 0
    return found


def count_ink(image, x0, x1, y0, y1, background, threshold):
    total = 0
    for y in range(y0, y1):
        for x in range(x0, x1 + 1):
            r, g, b = image.getpixel((x, y))
            if abs(r - background[0]) + abs(g - background[1]) + abs(b - background[2]) > threshold:
                total += 1
    return total


def measure(path, blank_lower=False):
    image = Image.open(path).convert("RGB")
    width, height = image.size
    top = height - BAR_HEIGHT + SIDE_SKIP
    bottom = height - SIDE_SKIP
    background = image.getpixel((width // 2, height - BAR_HEIGHT // 2))
    columns = ink_columns(image, top, bottom, background, 60)
    spans = [c for c in cells(columns, min(width, 900)) if c[1] - c[0] <= 64]
    middle = (top + bottom) // 2
    report = []
    for x0, x1 in spans:
        if blank_lower:
            for y in range(middle, bottom):
                for x in range(x0, x1 + 1):
                    image.putpixel((x, y), background)
        upper = count_ink(image, x0, x1, top, middle, background, 60)
        lower = count_ink(image, x0, x1, middle, bottom, background, 60)
        report.append((x0, x1, upper, lower))
    return report


def verdict(report):
    bad = [r for r in report if r[2] > 0 and r[3] < RATIO * r[2]]
    return len(report), bad


def main():
    path = sys.argv[1]
    blank = len(sys.argv) > 2 and sys.argv[2] == "--blank-lower"
    report = measure(path, blank)
    count, bad = verdict(report)
    for x0, x1, upper, lower in report:
        print("cell x=%d..%d upper=%d lower=%d" % (x0, x1, upper, lower))
    print("cells=%d truncated=%d" % (count, len(bad)))
    if count < 3:
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
