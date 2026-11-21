#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

from PIL import Image, ImageChops

BAR_ROWS = 40
STEP_MIN_PIXELS = 200
CHANGE_LEVEL = 6
MOVED_MIN_PIXELS = 2000
STEPS = ["g-01", "g-02", "g-03", "g-04"]


def changed_pixels(a, b, box):
    diff = ImageChops.difference(a.crop(box), b.crop(box)).convert("L")
    return sum(diff.histogram()[CHANGE_LEVEL + 1:])


def main():
    out = sys.argv[1]
    shots = {n: Image.open("%s/%s.ppm" % (out, n)).convert("RGB") for n in STEPS}
    width, height = shots[STEPS[0]].size
    bar = (0, height - BAR_ROWS, width, height)
    above = (0, height - 300, width, height - BAR_ROWS)
    ok = 0
    bad = 0
    moved = 0
    live = 0
    for a, b in zip(STEPS, STEPS[1:]):
        win = changed_pixels(shots[a], shots[b], above)
        glass = changed_pixels(shots[a], shots[b], bar)
        print("  step %s -> %s: window area %d px, bar %d px" % (a, b, win, glass))
        if win >= MOVED_MIN_PIXELS:
            moved += 1
            if glass >= STEP_MIN_PIXELS:
                live += 1
    if moved >= 2:
        ok += 1
        print("  OK    window moved in %d steps" % moved)
    else:
        bad += 1
        print("  FAIL  window moved in only %d steps" % moved)
    if moved >= 2 and live == moved:
        ok += 1
        print("  OK    bar pixels changed in every moving step (%d/%d)" % (live, moved))
    else:
        bad += 1
        print("  FAIL  bar pixels changed in %d of %d moving steps" % (live, moved))
    print("GLASSDRAG: %d passed, %d failed" % (ok, bad))
    sys.exit(1 if bad else 0)


main()
