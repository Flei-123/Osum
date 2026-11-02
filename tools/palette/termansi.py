#!/usr/bin/env python3
import os
import sys
from collections import Counter

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ROLES = (
    ("red / 41", "error"),
    ("green / 42", "success"),
    ("yellow / 43", "warning"),
    ("blue / 44", "ring"),
    ("white / 47", "text"),
    ("bright black / 100", "text_muted"),
)
OLD_FIXED = ("CD3131", "0DBC79", "E5E510", "2472C8")
MIN_PIXELS = 1000
PASS = FAIL = 0


def load_palette():
    pal = {}
    for line in open(os.path.join(ROOT, "assets", "palette", "dark.tsv"), encoding="utf-8"):
        if line.startswith("#"):
            continue
        role, hexs, _ = line.rstrip("\n").split("\t")
        pal[role] = hexs
    return pal


def check(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  OK    " + msg)
    else:
        FAIL += 1
        print("  FAIL  " + msg)


def main():
    pal = load_palette()
    im = Image.open(os.path.join(sys.argv[1], "ansi.ppm")).convert("RGB")
    data = im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()
    counts = Counter("%02X%02X%02X" % c for c in data)
    for name, role in ROLES:
        n = counts.get(pal[role], 0)
        check(n >= MIN_PIXELS, "ANSI %s == role %s %s (%d px)" % (name, role, pal[role], n))
    for hexs in OLD_FIXED:
        check(counts.get(hexs, 0) == 0, "old fixed xterm colour %s is gone (%d px)" % (hexs, counts.get(hexs, 0)))
    print("terminal ANSI pixels: %d ok, %d fail" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)


main()
