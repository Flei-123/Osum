#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OCR_ZOOM = 3
MODE = r"\d{3,4}\s*[x×]\s*\d{3,4}"
PAGE_WORDS = (
    r"System\s*>\s*Display",
    r"Brightness",
    r"Night\s+light",
    r"Scale\s*&\s*layout",
    r"Display\s+resolution",
    r"Display\s+orientation",
    r"Multiple\s+displays",
)


def ocr_text(path):
    image = Image.open(path).convert("RGB")
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "shot.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "--psm", "11"],
                             capture_output=True, text=True, check=False)
    return run.stdout


def has(text, pattern):
    return re.search(pattern, text, re.IGNORECASE) is not None


def judge_page(text):
    missing = [w for w in PAGE_WORDS if not has(text, w)]
    readout = has(text, r"\b\d{2,3}\s*%")
    print("ocr missing=%s readout=%s" % (",".join(missing) or "-", readout))
    return not missing and readout


def judge_list(text):
    modes = set(re.sub(r"\s", "", m).lower() for m in re.findall(MODE, text))
    print("ocr modes=%d" % len(modes))
    return len(modes) >= 3


def judge_keep(text):
    card = has(text, r"Keep\s+these\s+display") and has(text, r"Revert")
    print("ocr keep_card=%s" % card)
    return card


def judge_back(text):
    card = has(text, r"Keep\s+these\s+display")
    mode = has(text, r"1280\s*[x×]\s*800")
    print("ocr keep_card=%s mode_1280x800=%s" % (card, mode))
    return mode and not card


def judge_boot_page(text):
    auto = has(text, r"Automatic")
    boot = has(text, r"next\s+restart")
    keep = has(text, r"Keep\s+these\s+display")
    print("ocr automatic=%s next_restart=%s keep_card=%s" % (auto, boot, keep))
    return auto and boot and not keep


def judge_boot_saved(text):
    saved = has(text, r"new\s+resolution\s+applies\s+after\s+the\s+next\s+restart")
    keep = has(text, r"Keep\s+these\s+display")
    print("ocr saved_note=%s keep_card=%s" % (saved, keep))
    return saved and not keep


JUDGES = {
    "page": judge_page,
    "list": judge_list,
    "keep": judge_keep,
    "back": judge_back,
    "bootpage": judge_boot_page,
    "bootsaved": judge_boot_saved,
}


def main():
    kind, shot = sys.argv[1], sys.argv[2]
    sys.exit(0 if JUDGES[kind](ocr_text(shot)) else 1)


if __name__ == "__main__":
    main()
