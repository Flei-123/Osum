#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3


def load_ppm(path):
    return Image.open(path).convert("RGB")


def ocr_text(path):
    image = load_ppm(path)
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "shot.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", "11"],
                             capture_output=True, text=True, check=False)
    return run.stdout


def field_value(text, label):
    match = re.search(r"^.*?%s:?[ \t]*(\S*)" % re.escape(label), text, re.IGNORECASE | re.MULTILINE)
    return match.group(1).lower() if match else ""


def main():
    shot, provider, target = sys.argv[1], sys.argv[2].lower(), sys.argv[3].lower()
    text = ocr_text(shot)
    got_provider = field_value(text, "Provider")
    got_target = field_value(text, "Target")
    print("ocr provider=[%s] target=[%s]" % (got_provider, got_target))
    sys.exit(0 if (got_provider == provider and got_target == target) else 1)


if __name__ == "__main__":
    main()
