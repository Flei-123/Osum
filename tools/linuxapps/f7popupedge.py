#!/usr/bin/env python3
import sys

SCAN_X0 = 600
SCAN_X1 = 800
SCAN_Y0 = 470
SCAN_Y1 = 700
RIM_WIDTH = 4
WHITE = (255, 255, 255)
BLACK_SUM = 12
MIN_ROWS = 20
MAX_BLACK_ROWS = 2


def read_ppm(path):
    data = open(path, "rb").read()
    fields = data.split(None, 4)
    if fields[0] != b"P6":
        raise ValueError("not a P6 file")
    width, height = int(fields[1]), int(fields[2])
    return width, height, fields[4][-width * height * 3:]


def pixel(width, pixels, x, y):
    offset = (y * width + x) * 3
    return tuple(pixels[offset:offset + 3])


def rim_rows(width, pixels):
    rows = black = 0
    for y in range(SCAN_Y0, SCAN_Y1):
        for x in range(SCAN_X0 + RIM_WIDTH, SCAN_X1):
            if pixel(width, pixels, x, y) != WHITE:
                continue
            rows += 1
            rim = [pixel(width, pixels, x - 2 - i, y) for i in range(RIM_WIDTH)]
            if all(sum(p) < BLACK_SUM for p in rim):
                black += 1
            break
    return rows, black


if __name__ == "__main__":
    try:
        width, height, pixels = read_ppm(sys.argv[1])
        rows, black = rim_rows(width, pixels)
    except (OSError, ValueError, IndexError) as error:
        print("red popup screenshot unreadable: %s" % error)
        sys.exit(1)
    if rows < MIN_ROWS:
        print("red no dropdown rows found (%d)" % rows)
        sys.exit(1)
    state = "green" if black <= MAX_BLACK_ROWS else "red"
    print("%s %d of %d dropdown rows have a black rim" % (state, black, rows))
    sys.exit(0 if state == "green" else 1)
