#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/settingsaudit/ppm2png.py -- convert the PPM pictures of a run to small PNGs for docs/img/settings.

  python3 -I tools/settingsaudit/ppm2png.py <indir> <outdir> [scale_percent=75]
Page pictures are named page-a.ppm .. page-s.ppm (sidebar order, see PAGES in count.py).
"""
import os, sys
from PIL import Image

PAGE_IDS = ["appearance", "screen", "time", "network", "users", "netview", "language", "presets", "accounts", "sync",
            "bridge", "system", "approights", "log", "updates", "mouse", "power", "about", "apps", "screen2", "taskbar", "effects", "wifi", "usbnet", "scheme", "accent", "password", "pin"]

def main():
    indir, outdir = sys.argv[1], sys.argv[2]
    pct = int(sys.argv[3]) if len(sys.argv) > 3 else 75
    os.makedirs(outdir, exist_ok=True)
    for f in sorted(os.listdir(indir)):
        if not f.endswith(".ppm"):
            continue
        stem = f[:-4]
        if stem.startswith("page-") and len(stem) == 6:
            idx = ord(stem[5]) - ord("a") if stem[5].islower() else 26 + ord(stem[5]) - ord("A")
            if 0 <= idx < len(PAGE_IDS):
                stem = "page-%02d-%s" % (idx, PAGE_IDS[idx])
        im = Image.open(os.path.join(indir, f)).convert("RGB")
        if pct != 100:
            im = im.resize((im.width * pct // 100, im.height * pct // 100), Image.LANCZOS)
        im.save(os.path.join(outdir, stem + ".png"), optimize=True)
        print(stem)

main()
