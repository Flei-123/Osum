#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import difflib
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageOps, ImageStat

OCR_ZOOMS = (2, 3, 4)
OCR_MIN_RATIO = 0.75
DARK_MEAN = 128
USAGE = """Usage:
    scene.py ocr <ppm> <x> <y> <w> <h> <text>
    scene.py changed <ppm_a> <ppm_b> <x> <y> <w> <h> <min_pixels>
    scene.py colors <ppm> <x> <y> <w> <h> <min_colors>
    scene.py area <ppm> <x> <y> <w> <h> <r> <g> <b> <min_pixels>
"""


def crop(path, x, y, w, h):
    return Image.open(path).convert("RGB").crop((x, y, x + w, y + h))


def normalize(text):
    return "".join(text.lower().split())


def read_text(image, zoom):
    gray = ImageOps.grayscale(image)
    if ImageStat.Stat(gray).mean[0] < DARK_MEAN:
        gray = ImageOps.invert(gray)
    gray = gray.resize((gray.width * zoom, gray.height * zoom), Image.LANCZOS)
    gray = ImageOps.expand(gray, border=12 * zoom, fill=255)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "crop.png"
        gray.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "-l", "eng+deu", "--psm", "7"],
                             capture_output=True, text=True, check=False)
    return run.stdout.strip()


def cmd_ocr(args):
    x, y, w, h = (int(v) for v in args[1:5])
    expected = args[5]
    image = crop(args[0], x, y, w, h)
    best = 0.0
    seen = ""
    for zoom in OCR_ZOOMS:
        text = read_text(image, zoom)
        score = difflib.SequenceMatcher(None, normalize(text), normalize(expected)).ratio()
        if score >= best:
            best = score
            seen = text
    ratio = best
    print("ocr '%s' vs '%s' ratio %.2f" % (seen, expected, ratio))
    return 0 if ratio >= OCR_MIN_RATIO else 1


def cmd_changed(args):
    x, y, w, h = (int(v) for v in args[2:6])
    minimum = int(args[6])
    diff = ImageChops.difference(crop(args[0], x, y, w, h), crop(args[1], x, y, w, h))
    count = sum(n for n, px in diff.getcolors(diff.width * diff.height) if px != (0, 0, 0))
    print("%d changed pixels (minimum %d)" % (count, minimum))
    return 0 if count >= minimum else 1


def cmd_colors(args):
    x, y, w, h = (int(v) for v in args[1:5])
    minimum = int(args[5])
    image = crop(args[0], x, y, w, h)
    count = len(image.getcolors(image.width * image.height))
    print("%d distinct colours (minimum %d)" % (count, minimum))
    return 0 if count >= minimum else 1


def cmd_area(args):
    x, y, w, h = (int(v) for v in args[1:5])
    want = tuple(int(v) for v in args[5:8])
    minimum = int(args[8])
    image = crop(args[0], x, y, w, h)
    count = sum(n for n, px in image.getcolors(image.width * image.height) if px == want)
    print("%d pixels of %s (minimum %d)" % (count, want, minimum))
    return 0 if count >= minimum else 1


COMMANDS = {"ocr": (cmd_ocr, 6), "changed": (cmd_changed, 7), "colors": (cmd_colors, 6), "area": (cmd_area, 9)}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(USAGE)
        return 2
    handler, count = COMMANDS[sys.argv[1]]
    if len(sys.argv) - 2 != count:
        print(USAGE)
        return 2
    return handler(sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
