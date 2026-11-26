#!/usr/bin/env python3
import sys

MOVED_SHARE = 0.002
LIT_SHARE = 0.02
LIT_LEVEL = 24
EQUAL_MEAN = 1.0


def load(path):
    if path.endswith(".ppm"):
        data = open(path, "rb").read()
        parts = data.split(b"\n", 3)
        w, h = map(int, parts[1].split())
        px = parts[3]
        return w, h, [px[i:i + 3] for i in range(0, len(px), 3)]
    w, h = map(int, sys.argv[-1].split("x"))
    raw = open(path, "rb").read()
    return w, h, [bytes((raw[i + 2], raw[i + 1], raw[i])) for i in range(0, len(raw), 4)]


def moved(a, b):
    _, _, pa = load(a)
    _, _, pb = load(b)
    changed = sum(1 for x, y in zip(pa[::7], pb[::7]) if max(abs(x[k] - y[k]) for k in range(3)) > 8)
    return changed / max(1, len(pa[::7])) >= MOVED_SHARE


def lit(a):
    _, _, pa = load(a)
    bright = sum(1 for x in pa[::5] if max(x) > LIT_LEVEL)
    return bright / max(1, len(pa[::5])) >= LIT_SHARE


def equal(a, b):
    _, _, pa = load(a)
    _, _, pb = load(b)
    diff = sum(abs(x[k] - y[k]) for x, y in zip(pa[::3], pb[::3]) for k in range(3))
    return diff / max(1, 3 * len(pa[::3])) <= EQUAL_MEAN


def main(argv):
    mode = argv[1]
    if mode == "moved":
        return 0 if moved(argv[2], argv[3]) else 1
    if mode == "lit":
        return 0 if lit(argv[2]) else 1
    if mode == "equal":
        return 0 if equal(argv[2], argv[3]) else 1
    sys.stderr.write("usage: shots.py moved|lit|equal <a> [b] [WxH]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
