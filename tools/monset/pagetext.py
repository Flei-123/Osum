#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile

from PIL import Image

CONTENT_LEFT_FRACTION = 0.25
UPSCALE = 2


def page_text(ppm):
    image = Image.open(ppm).convert("L")
    width, height = image.size
    content = image.crop((int(width * CONTENT_LEFT_FRACTION), 0, width, height))
    content = content.resize((content.width * UPSCALE, content.height * UPSCALE), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = tmp + "/page.png"
        content.save(png)
        done = subprocess.run(["tesseract", png, "-", "--psm", "6"], capture_output=True, text=True)
    return done.stdout


def main():
    ppm, pattern = sys.argv[1:3]
    found = re.search(pattern, page_text(ppm), re.I) is not None
    sys.exit(0 if found else 1)


main()
