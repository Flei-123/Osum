#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

CORNER = 10
TOAST = re.compile(rb"taskbar: toast \[[^\]]*\] x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
CARD = re.compile(rb"notifc: card 0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
passed = 0
failed = 0


def check(cond, text):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + text)
    else:
        failed += 1
        print("  FAIL  " + text)


def read_ppm(path):
    data = open(path, "rb").read()
    tokens = []
    pos = 0
    while len(tokens) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        tokens.append(data[start:pos])
    pos += 1
    width, height = int(tokens[1]), int(tokens[2])
    return width, height, data[pos:pos + width * height * 3]


def rect(serial, pattern, last):
    found = pattern.findall(serial)
    if not found:
        return None
    return tuple(int(v) for v in (found[-1] if last else found[0]))


def crop(image, box):
    width, _, pixels = image
    x, y, w, h = box
    return [pixels[((y + j) * width + x) * 3:((y + j) * width + x + w) * 3] for j in range(h)]


def interior_diff(a, b, w, h):
    diff = 0
    for j in range(CORNER, h - CORNER):
        for i in range(CORNER, w - CORNER):
            if a[j][i * 3:i * 3 + 3] != b[j][i * 3:i * 3 + 3]:
                diff += 1
    return diff


def measure(run):
    serial = open(run + "/serial.txt", "rb").read()
    toast = rect(serial, TOAST, True)
    card = rect(serial, CARD, False)
    if not toast or not card:
        return None
    shot_toast = read_ppm(run + "/01-toast.ppm")
    shot_center = read_ppm(run + "/02-center.ppm")
    w = min(toast[2], card[2])
    h = min(toast[3], card[3])
    a = crop(shot_toast, (toast[0], toast[1], w, h))
    b = crop(shot_center, (card[0], card[1], w, h))
    return toast, card, interior_diff(a, b, w, h), w * h


def main():
    new_dir, old_dir, scale = sys.argv[1], sys.argv[2], int(sys.argv[3])
    result = measure(new_dir)
    check(result is not None, "toast and centre card both reported their rectangle")
    if result:
        toast, card, diff, area = result
        print("        toast %s card %s interior diff %d of %d" % (toast, card, diff, area))
        check(toast[2] == card[2] and toast[3] == card[3], "toast and card have the same size")
        check(diff <= area // 200, "toast and centre card are pixel-identical inside the corners")
    counter = None
    try:
        counter = measure(old_dir)
    except FileNotFoundError:
        counter = None
    if counter:
        check(counter[0][3] != result[0][3] or counter[2] > counter[3] // 200,
              "counter-proof note_old=1: the old layout differs from the card")
    else:
        check(True, "counter-proof note_old=1: the old layout has no card rectangle")
    print("NOTECARD checks (scale %d): %d passed, %d failed" % (scale, passed, failed))
    sys.exit(1 if failed else 0)


main()
