#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

MIN_TABS = 12
MIN_OCR_RATIO = 0.7
OCR_ZOOM = 3
SIDEBAR_WIDTH_RATIO = 0.3


def read_messages(path):
    messages = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if " = " in line:
            key, value = line.split(" = ", 1)
            messages[key] = value
    return messages


def route_titles(pagemap, messages):
    titles = {}
    for line in Path(pagemap).read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "page":
            slug = parts[2][len("settings://"):].replace("/", "-")
            titles[int(parts[1])] = messages.get("settings.page.%s.title" % slug)
    return titles


def traced_tabs(serial):
    tabs = {}
    for raw in Path(serial).read_bytes().decode("utf-8", "replace").splitlines():
        match = re.search(r"wlib: tab i=(\d+) .* t=(.*)$", raw)
        if match:
            tabs[int(match.group(1))] = match.group(2).strip()
    return tabs


def ocr_sidebar(shot, lang):
    image = Image.open(shot).convert("RGB")
    image = image.crop((0, 0, int(image.width * SIDEBAR_WIDTH_RATIO), image.height))
    image = image.resize((image.width * OCR_ZOOM, image.height * OCR_ZOOM), Image.LANCZOS)
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "sidebar.png"
        image.save(png)
        run = subprocess.run(["tesseract", str(png), "-", "-l", lang, "--psm", "6"],
                             capture_output=True, text=True, check=False)
    return run.stdout.lower()


def main():
    serial, messages_path, pagemap, shot, lang = sys.argv[1:6]
    titles = route_titles(pagemap, read_messages(messages_path))
    tabs = traced_tabs(serial)
    mismatches = [(i, tabs[i], titles[i]) for i in sorted(tabs) if titles.get(i) and tabs[i] != titles[i]]
    text = ocr_sidebar(shot, lang)
    shown = [titles[i] for i in sorted(tabs) if titles.get(i)]
    found = [t for t in shown if t.lower() in text]
    ratio = len(found) / len(shown) if shown else 0.0
    print("tabs=%d mismatches=%d %s ocr=%d/%d" % (len(tabs), len(mismatches), mismatches[:3], len(found), len(shown)))
    ok = len(tabs) >= MIN_TABS and not mismatches and ratio >= MIN_OCR_RATIO
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
