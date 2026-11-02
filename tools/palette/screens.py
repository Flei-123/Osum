#!/usr/bin/env python3
import os
import sys
from collections import Counter

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CASES = {
    "glogin": (("ring", 300), ("border", 200)),
    "lock": (("ring", 300), ("border", 200)),
    "vault": (("surface", 50000), ("field", 9000), ("accent", 2000), ("border", 500), ("text", 400)),
}
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
    case, shot = sys.argv[1], sys.argv[2]
    pal = load_palette()
    im = Image.open(shot).convert("RGB")
    data = im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()
    counts = Counter("%02X%02X%02X" % c for c in data)
    for role, minimum in CASES[case]:
        n = counts.get(pal[role], 0)
        check(n >= minimum, "%s: role %s %s paints %d px (need >= %d)" % (case, role, pal[role], n, minimum))
    print("palette screen %s: %d ok, %d fail" % (case, PASS, FAIL))
    sys.exit(1 if FAIL else 0)


main()
