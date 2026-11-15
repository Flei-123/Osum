#!/usr/bin/env python3
import re
import sys

STRIP_WIDTH = 24
STRIP_TOP = 60
STRIP_HEIGHT = 400
MAX_BLACK_SHARE = 0.05
WINDOW_LINE = re.compile(rb"wayd: window c=\d+ x=(\d+) y=(\d+) inx=(\d+) iny=(\d+)")


def read_ppm(path):
    data = open(path, "rb").read()
    fields = data.split(None, 4)
    if fields[0] != b"P6":
        raise ValueError("not a P6 file")
    width, height = int(fields[1]), int(fields[2])
    return width, height, fields[4][-width * height * 3:]


def inner_origin(log_path):
    found = WINDOW_LINE.findall(open(log_path, "rb").read())
    if not found:
        raise ValueError("no wayd window line")
    x, y, inx, iny = (int(v) for v in found[-1])
    return x + inx, y + iny


def black_share(width, pixels, x0, y0, w, h):
    black = 0
    for y in range(y0, y0 + h):
        row = (y * width + x0) * 3
        for x in range(w):
            offset = row + x * 3
            if pixels[offset] + pixels[offset + 1] + pixels[offset + 2] < 12:
                black += 1
    return black / (w * h)


if __name__ == "__main__":
    try:
        width, height, pixels = read_ppm(sys.argv[1])
        left, top = inner_origin(sys.argv[2])
        share = black_share(width, pixels, left, top + STRIP_TOP, STRIP_WIDTH, STRIP_HEIGHT)
    except (OSError, ValueError, IndexError) as error:
        print("red window edge unreadable: %s" % error)
        sys.exit(1)
    state = "green" if share <= MAX_BLACK_SHARE else "red"
    print("%s %.0f%% black in the left window strip" % (state, share * 100))
    sys.exit(0 if state == "green" else 1)
