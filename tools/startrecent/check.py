#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys

DISPLAY_NAMES = {"settings": "Settings", "terminal": "Terminal", "explorer": "File Explorer"}
RECOMMENDED = re.compile(r"launcher: rec k=(\d+) name=\[([^\]]*)\]")
SAVED = re.compile(r"launcher: recent file n=(\d+)((?: \[[^\]]*\])*)")
OCR_SCALE = 2


def last_recommended(serial):
    rows = {}
    best = {}
    for line in open(serial, errors="replace"):
        match = RECOMMENDED.search(line)
        if not match:
            continue
        index = int(match.group(1))
        if index == 0:
            rows = {}
        rows[index] = match.group(2)
        best = dict(rows)
    return [best[k] for k in sorted(best)]


def last_saved(serial):
    found = None
    for line in open(serial, errors="replace"):
        match = SAVED.search(line)
        if match:
            found = re.findall(r"\[([^\]]*)\]", match.group(2))
    return found


def ocr_text(shot):
    from PIL import Image
    image = Image.open(shot).convert("L")
    image = image.resize((image.width * OCR_SCALE, image.height * OCR_SCALE))
    path = shot + ".ocr.png"
    image.save(path)
    result = subprocess.run(["tesseract", path, "-", "--psm", "11"], capture_output=True, text=True)
    return result.stdout.lower()


def check_order(serial, shot, seed, scale):
    wanted = [DISPLAY_NAMES[token] for token in seed.split(",")]
    shown = last_recommended(serial)
    print("recommended %s, wanted lead %s, scale %s" % (shown, wanted, scale))
    if shown[: len(wanted)] != wanted:
        return False
    text = ocr_text(shot)
    return all(name.lower() in text for name in wanted)


def check_saved(serial, seed):
    saved = last_saved(serial)
    wanted = ["explorer"] + seed.split(",")
    print("file recent=%s, wanted %s" % (saved, wanted))
    return saved == wanted


def main():
    mode, serial, shot, seed, scale = sys.argv[1:6]
    good = check_order(serial, shot, seed, scale) if mode == "order" else check_saved(serial, seed)
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
