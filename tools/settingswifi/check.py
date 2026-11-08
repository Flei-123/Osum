#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3
PANE_LEFT_FRACTION = 0.2
PANE_TOP_FRACTION = 0.18
MESSAGE = r"no\s+wi-?fi\s+adapter\s+found"
REFRESH = r"\bRefresh\b"
BUTTON_BLUE_MAX_RED = 70
BUTTON_BLUE_MIN_BLUE = 200
BUTTON_BLUE_GREEN_RANGE = (70, 130)
BUTTON_MIN_ROWS = 15
BUTTON_MIN_WIDTH_FRACTION = 0.3


def ocr_text(path):
    image = Image.open(path).convert("RGB")
    left = int(image.width * PANE_LEFT_FRACTION)
    top = int(image.height * PANE_TOP_FRACTION)
    image = image.crop((left, top, image.width, image.height))
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "shot.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", "11"],
                             capture_output=True, text=True, check=False)
    return run.stdout


def is_button_blue(pixel):
    red, green, blue = pixel
    low, high = BUTTON_BLUE_GREEN_RANGE
    return red < BUTTON_BLUE_MAX_RED and low < green < high and blue > BUTTON_BLUE_MIN_BLUE


def has_primary_button(path):
    image = Image.open(path).convert("RGB")
    pixels = image.load()
    min_width = int(image.width * BUTTON_MIN_WIDTH_FRACTION)
    rows = 0
    for y in range(image.height):
        width = sum(1 for x in range(image.width) if is_button_blue(pixels[x, y]))
        rows = rows + 1 if width >= min_width else 0
        if rows >= BUTTON_MIN_ROWS:
            return True
    return False


def facts(text, shot):
    return (re.search(MESSAGE, text, re.IGNORECASE) is not None,
            re.search(REFRESH, text) is not None,
            has_primary_button(shot))


def judge_noadapter(text, shot):
    message, refresh, connect = facts(text, shot)
    print("ocr message=%s refresh=%s connect=%s" % (message, refresh, connect))
    return message and not refresh and not connect


def judge_adapter(text, shot):
    message, refresh, connect = facts(text, shot)
    print("ocr message=%s refresh=%s connect=%s" % (message, refresh, connect))
    return refresh and connect and not message


JUDGES = {"noadapter": judge_noadapter, "adapter": judge_adapter}


def main():
    kind, shot = sys.argv[1], sys.argv[2]
    sys.exit(0 if JUDGES[kind](ocr_text(shot), shot) else 1)


if __name__ == "__main__":
    main()
