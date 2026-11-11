#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3
WIDE_WIDTH = 1920
DIALOG_TITLE_WORD = re.compile(r"installieren\??$", re.IGNORECASE)
DIALOG_FIRST_WORD = re.compile(r"^Programm$", re.IGNORECASE)
TITLE_GOOD = re.compile(r"^Gru(ß|ss|s|B|8)$")
TITLE_RAW_ID = re.compile(r"^gru(ß|ss|s|B|8)$")
CROP_LEFT_PAD = 8
CROP_WIDTH = 300
CROP_TOP_GAP = 14
CROP_HEIGHT = 56


def run_tesseract(image, psm, output):
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "shot.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", str(psm)] + output,
                             capture_output=True, text=True, check=False)
    return run.stdout


def zoomed(image):
    return image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)


def find_dialog_title(image):
    tsv = run_tesseract(zoomed(image), 11, ["tsv"])
    rows = [line.split("\t") for line in tsv.splitlines()[1:] if line.count("\t") >= 11]
    words = [(row[11].strip(), int(row[6]), int(row[7]), int(row[8]), int(row[9])) for row in rows if row[11].strip()]
    for first in words:
        if not DIALOG_FIRST_WORD.match(first[0]):
            continue
        for second in words:
            same_row = abs(second[2] - first[2]) < first[4]
            if same_row and second[1] > first[1] and DIALOG_TITLE_WORD.search(second[0]):
                return first
    return None


def dialog_line(image):
    anchor = find_dialog_title(image)
    if anchor is None:
        return None
    scale = 2 if image.width >= WIDE_WIDTH else 1
    left = anchor[1] // OCR_ZOOM - CROP_LEFT_PAD * scale
    top = (anchor[2] + anchor[4]) // OCR_ZOOM + CROP_TOP_GAP * scale
    box = (max(left, 0), top, left + CROP_WIDTH * scale, top + CROP_HEIGHT * scale)
    text = run_tesseract(zoomed(image.crop(box)), 7, [])
    return re.sub(r"[^\wß]", "", text.strip())


def main():
    shot = Path(sys.argv[1])
    line = dialog_line(Image.open(shot).convert("RGB"))
    if line is None:
        print("ocr dialog_found=False")
        sys.exit(2)
    good = TITLE_GOOD.match(line) is not None
    raw_id = TITLE_RAW_ID.match(line) is not None
    print("ocr dialog_line=%s title=%s raw_id=%s" % (line, good, raw_id))
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
