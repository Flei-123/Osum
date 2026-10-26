#!/usr/bin/env python3
import sys

CURSOR_W = 26
CURSOR_H = 34


def load(path):
    f = open(path, "rb")
    f.readline()
    line = f.readline()
    while line.startswith(b"#"):
        line = f.readline()
    w, h = map(int, line.split())
    f.readline()
    return w, h, f.read()


def mean_rect(img, rect, skip):
    w, h, data = img
    x0, y0, x1, y1 = rect
    n = 0
    acc = [0, 0, 0]
    for y in range(y0, y1):
        for x in range(x0, x1):
            if skip and skip[0] - 3 <= x < skip[0] + CURSOR_W and skip[1] - 3 <= y < skip[1] + CURSOR_H:
                continue
            o = (y * w + x) * 3
            acc[0] += data[o]
            acc[1] += data[o + 1]
            acc[2] += data[o + 2]
            n += 1
    if n == 0:
        return None
    return [v / n for v in acc]


def delta(rest, hov, rect, skip):
    a = mean_rect(load(rest), rect, skip)
    b = mean_rect(load(hov), rect, skip)
    if a is None or b is None:
        return None, None, None
    return max(abs(a[i] - b[i]) for i in range(3)), a, b


def main():
    cmd, rest, hov = sys.argv[1:4]
    rect = tuple(int(v) for v in sys.argv[4:8])
    limit = float(sys.argv[8])
    skip = None
    if len(sys.argv) >= 11:
        skip = (int(sys.argv[9]), int(sys.argv[10]))
    d, a, b = delta(rest, hov, rect, skip)
    if d is None:
        print("rect fully covered by the pointer")
        sys.exit(1)
    print("delta=%.1f rest=%s hover=%s" % (d, tuple(round(v) for v in a), tuple(round(v) for v in b)))
    if cmd == "plate":
        sys.exit(0 if d >= limit else 1)
    sys.exit(0 if d <= limit else 1)


main()
