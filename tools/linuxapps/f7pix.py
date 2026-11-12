#!/usr/bin/env python3
import sys

TOLERANCE = 8
MIN_PIXELS = 20000


def read_ppm(path):
    data = open(path, "rb").read()
    fields = data.split(None, 4)
    if fields[0] != b"P6":
        raise ValueError("not a P6 file")
    width, height = int(fields[1]), int(fields[2])
    return width, height, fields[4][-width * height * 3:]


def count_color(pixels, target):
    hits = 0
    for offset in range(0, len(pixels) - 2, 3):
        if all(abs(pixels[offset + i] - target[i]) <= TOLERANCE for i in range(3)):
            hits += 1
    return hits


def parse_color(text):
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


if __name__ == "__main__":
    try:
        width, height, pixels = read_ppm(sys.argv[1])
    except (OSError, ValueError, IndexError) as error:
        print("red unreadable screenshot: %s" % error)
        sys.exit(1)
    hits = count_color(pixels, parse_color(sys.argv[2]))
    state = "green" if hits >= MIN_PIXELS else "red"
    print("%s %d pixels of #%s in %dx%d" % (state, hits, sys.argv[2], width, height))
    sys.exit(0 if state == "green" else 1)
