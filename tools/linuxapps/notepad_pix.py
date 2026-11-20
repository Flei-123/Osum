#!/usr/bin/env python3
import sys

import numpy

MIN_WHITE = 20000
MAX_BASELINE_WHITE = 2000
MIN_DARK_GAIN = 40
DARK_LEVEL = 90
WHITE_LEVEL = 250


def read_ppm(path):
    data = open(path, "rb").read()
    fields = data.split(None, 4)
    if fields[0] != b"P6":
        raise ValueError("not a P6 file")
    width, height = int(fields[1]), int(fields[2])
    pixels = numpy.frombuffer(fields[4][-width * height * 3:], dtype=numpy.uint8)
    return pixels.reshape(height, width, 3)


def white(image):
    return int((image.min(axis=2) >= WHITE_LEVEL).sum())


def dark(image):
    return int((image.max(axis=2) <= DARK_LEVEL).sum())


def verdict(baseline, window, typed):
    problems = []
    base_white = white(baseline)
    window_white = white(window)
    gain = dark(typed) - dark(window)
    if base_white > MAX_BASELINE_WHITE:
        problems.append("baseline already has %d white pixels" % base_white)
    if window_white < MIN_WHITE:
        problems.append("window not visible (%d white pixels)" % window_white)
    if gain < MIN_DARK_GAIN:
        problems.append("typed text not visible (dark pixel gain %d)" % gain)
    state = "red " + "; ".join(problems) if problems else "green"
    return "%s baseline_white=%d window_white=%d dark_gain=%d" % (state.split(" ", 1)[0], base_white, window_white, gain) + ("" if not problems else " :: " + "; ".join(problems))


if __name__ == "__main__":
    try:
        images = [read_ppm(path) for path in sys.argv[1:4]]
    except (OSError, ValueError, IndexError) as error:
        print("red unreadable screenshot: %s" % error)
        sys.exit(1)
    text = verdict(*images)
    print(text)
    sys.exit(0 if text.startswith("green") else 1)
