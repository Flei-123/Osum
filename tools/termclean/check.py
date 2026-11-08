#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3
BOOT_REPORT_WORDS = ("USB", "SINGLE", "DEVICE")


def terminal_text(shot, box):
    image = Image.open(shot).convert("RGB").crop(box)
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "terminal.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", "6"],
                             capture_output=True, text=True, check=False)
    return run.stdout


def main():
    shot, mode = sys.argv[1], sys.argv[2]
    box = tuple(int(v) for v in sys.argv[3:7])
    text = terminal_text(shot, box)
    found = [w for w in BOOT_REPORT_WORDS if w in text.upper()]
    print("ocr boot-report words=%s" % (found or "none"))
    clean = not found
    sys.exit(0 if clean == (mode == "clean") else 1)


if __name__ == "__main__":
    main()
