#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import re
import struct
import sys

import cairosvg
from PIL import Image

SIZES = (16, 24, 32, 48)
BACKGROUNDS = {"light": (255, 255, 255), "dark": (17, 28, 46)}
MAX_OPAQUE_PERCENT = 62
MAX_CENTER_OFFSET = 1.0
MAX_MEAN_ERROR = {16: 3.0, 24: 2.0, 32: 2.0, 48: 1.0}
MIN_CONTRAST = 1.5
MIN_CONTRAST_SHARE = 0.25
MIN_COLORS = 6


def load_osym(path):
    data = open(path, "rb").read()
    w, h = struct.unpack("<II", data[4:12])
    return Image.frombytes("RGBA", (w, h), data[12:], "raw", "BGRA")


def reference(svg, size):
    png = cairosvg.svg2png(url=svg, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def luminance(rgb):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check_fidelity(svg, osym, size):
    img = load_osym(osym)
    ref = reference(svg, size)
    a = img.getchannel("A").tobytes()
    b = ref.getchannel("A").tobytes()
    mean = sum(abs(x - y) for x, y in zip(a, b)) / len(a)
    return mean <= MAX_MEAN_ERROR[size], "mean alpha error %.2f" % mean


def check_center(img):
    box = img.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
    if box is None:
        return False, "empty"
    scale = img.width / 24.0
    dx = abs((box[0] + box[2]) / 2.0 / scale - 12)
    dy = abs((box[1] + box[3]) / 2.0 / scale - 12)
    return max(dx, dy) <= MAX_CENTER_OFFSET, "center offset x %.2f y %.2f" % (dx, dy)


def check_shape(img):
    alpha = img.getchannel("A").tobytes()
    opaque = sum(1 for v in alpha if v > 128)
    percent = opaque * 100 // len(alpha)
    colors = len(set(img.tobytes()[i:i + 4] for i in range(0, len(alpha) * 4, 4)))
    ok = 0 < percent <= MAX_OPAQUE_PERCENT and colors >= MIN_COLORS
    return ok, "%d %% opaque, %d colors" % (percent, colors)


def check_contrast(img, theme):
    bg = BACKGROUNDS[theme]
    raw = img.tobytes()
    pixels = [raw[i:i + 4] for i in range(0, len(raw), 4) if raw[i + 3] > 200]
    good = sum(1 for p in pixels if contrast(p[:3], bg) >= MIN_CONTRAST)
    share = good / max(1, len(pixels))
    return share >= MIN_CONTRAST_SHARE, "%s contrast share %.2f" % (theme, share)


def check_elements(svg):
    text = open(svg, encoding="ascii").read()
    allowed = {"svg", "g", "path", "rect", "circle", "line", "polyline", "polygon"}
    used = set(re.findall(r"<([a-zA-Z]+)", text))
    extra = used - allowed
    return not extra and "Gradient" not in text, "elements %s" % sorted(used)


def main(argv):
    svg, osym, size = argv[0], argv[1], int(argv[2])
    img = load_osym(osym)
    checks = [check_fidelity(svg, osym, size), check_center(img), check_shape(img)]
    checks += [check_contrast(img, t) for t in BACKGROUNDS]
    if size == SIZES[0]:
        checks.append(check_elements(svg))
    bad = [msg for ok, msg in checks if not ok]
    print("FAIL " + "; ".join(bad) if bad else "OK " + "; ".join(m for _, m in checks[:3]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
