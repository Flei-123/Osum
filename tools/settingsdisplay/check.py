#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3
LAST_MODE = r"2560\s*[x×]\s*1600"
DEPTH = r"32\s*bit"
GLUED_DEPTH = "328"
DETAILS_LABEL = r"Connection\s+details"
DETAILS_PAGE_WORDS = ("Address", "Gateway", "MAC", "Speed")


def ocr_text(path):
    image = Image.open(path).convert("RGB")
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "shot.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", "11"],
                             capture_output=True, text=True, check=False)
    return run.stdout


def judge_display(text):
    last_mode = re.search(LAST_MODE, text) is not None
    depth = re.search(DEPTH, text, re.IGNORECASE) is not None
    glued = GLUED_DEPTH in text
    print("ocr last_mode=%s depth=%s glued=%s" % (last_mode, depth, glued))
    return last_mode and depth and not glued


def judge_network(text):
    found = re.search(DETAILS_LABEL, text, re.IGNORECASE) is not None
    print("ocr related_row=%s" % found)
    return found


def judge_details(text):
    hits = [w for w in DETAILS_PAGE_WORDS if re.search(w, text, re.IGNORECASE)]
    related_still = re.search(r"Related", text, re.IGNORECASE) is not None and \
        re.search(DETAILS_LABEL, text, re.IGNORECASE) is not None
    print("ocr details_words=%s related_still=%s" % (",".join(hits), related_still))
    return len(hits) >= 2 and not related_still


def judge_nocard(text):
    empty_row = re.search(r"no\s+card\s+found", text, re.IGNORECASE) is not None
    unprobed = re.search(r"not\s+probed", text, re.IGNORECASE) is not None
    print("ocr empty_row=%s unprobed=%s" % (empty_row, unprobed))
    return empty_row and unprobed


JUDGES = {"nocard": judge_nocard, "display": judge_display, "network": judge_network, "details": judge_details}


def main():
    kind, shot = sys.argv[1], sys.argv[2]
    sys.exit(0 if JUDGES[kind](ocr_text(shot)) else 1)


if __name__ == "__main__":
    main()
