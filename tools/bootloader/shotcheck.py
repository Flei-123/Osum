#!/usr/bin/env python3
import struct
import sys

SPINNER_BOX = 40


def read_ppm(path):
    data = open(path, "rb").read()
    parts = data.split(None, 4)
    width, height = int(parts[1]), int(parts[2])
    offset = len(data) - width * height * 3
    return width, height, data[offset:]


def read_logo(path):
    data = open(path, "rb").read()
    width, height = struct.unpack("<II", data[4:12])
    return width, height, data[12:]


def layout(sw, sh, lw, lh):
    scale = max(1, (sh + 540) // 1080)
    total = 40 * scale + lh * scale + 48 * scale
    top = (sh - total) // 2
    left = (sw - lw * scale) // 2
    return scale, top, left


def logo_match(ppm, logo):
    sw, sh, pix = read_ppm(ppm)
    lw, lh, rgba = read_logo(logo)
    scale, top, left = layout(sw, sh, lw, lh)
    good = total = 0
    for y in range(0, lh, 2):
        for x in range(0, lw, 2):
            r, g, b, a = rgba[(y * lw + x) * 4:(y * lw + x) * 4 + 4]
            if a != 255 or r + g + b < 90:
                continue
            px = left + x * scale
            py = top + y * scale
            o = (py * sw + px) * 3
            total += 1
            if abs(pix[o] - r) <= 3 and abs(pix[o + 1] - g) <= 3 and abs(pix[o + 2] - b) <= 3:
                good += 1
    return good, total


def spinner_pixels(ppm, logo):
    sw, sh, pix = read_ppm(ppm)
    lw, lh, _ = read_logo(logo)
    scale, top, left = layout(sw, sh, lw, lh)
    cy = top + lh * scale + 48 * scale + 20 * scale
    cx = sw // 2
    box = []
    for y in range(cy - 20 * scale, cy + 21 * scale):
        for x in range(cx - 20 * scale, cx + 21 * scale):
            o = (y * sw + x) * 3
            box.append(pix[o:o + 3])
    return box


def main(argv):
    mode, logo = argv[1], argv[3]
    if mode == "logo":
        good, total = logo_match(argv[2], logo)
        print("logo match %d/%d" % (good, total))
        return 0 if total > 100 and good * 100 >= total * 98 else 1
    if mode == "nologo":
        good, total = logo_match(argv[2], logo)
        print("logo match %d/%d" % (good, total))
        return 0 if total > 100 and good * 100 < total * 50 else 1
    if mode == "spinner":
        a = spinner_pixels(argv[2], logo)
        b = spinner_pixels(argv[4], logo)
        lit = sum(1 for p in a if p != b"\x00\x00\x00")
        changed = sum(1 for p, q in zip(a, b) if p != q)
        print("spinner lit %d changed %d" % (lit, changed))
        return 0 if lit >= 40 and changed >= 20 else 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
