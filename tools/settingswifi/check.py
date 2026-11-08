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
CONNECT = r"\bConnect\b"


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


def facts(text):
    return (re.search(MESSAGE, text, re.IGNORECASE) is not None,
            re.search(REFRESH, text) is not None,
            re.search(CONNECT, text) is not None)


def judge_noadapter(text):
    message, refresh, connect = facts(text)
    print("ocr message=%s refresh=%s connect=%s" % (message, refresh, connect))
    return message and not refresh and not connect


def judge_adapter(text):
    message, refresh, connect = facts(text)
    print("ocr message=%s refresh=%s connect=%s" % (message, refresh, connect))
    return refresh and connect and not message


JUDGES = {"noadapter": judge_noadapter, "adapter": judge_adapter}


def main():
    kind, shot = sys.argv[1], sys.argv[2]
    sys.exit(0 if JUDGES[kind](ocr_text(shot)) else 1)


if __name__ == "__main__":
    main()
