#!/usr/bin/env python3
import re
import subprocess
import sys
import tempfile
from PIL import Image, ImageOps

KEYS = ["mode", "checks", "bad", "unstable", "pending", "skipped", "px", "card_checks", "card_bad", "win", "us", "renders"]


def read(path):
    im = Image.open(path).convert("L")
    im = ImageOps.invert(im.crop((20, 70, 600, 460)))
    im = im.resize((im.width * 3, im.height * 3))
    with tempfile.TemporaryDirectory() as d:
        f = d + "/crop.png"
        im.save(f)
        out = subprocess.run(["tesseract", f, "-", "--psm", "6"], capture_output=True, text=True).stdout
    out = re.sub(r"card[ _]checks", "card_checks", out, flags=re.I)
    out = re.sub(r"card[ _]bad", "card_bad", out, flags=re.I)
    return out


def main(paths):
    bad = 0
    for p in paths:
        txt = read(p)
        missing = [k for k in KEYS if not re.search(r"pixelguard\. *" + k + " ", txt, re.I)]
        print("%s: missing on screen %s" % (p, missing))
        if missing:
            bad = 1
    return bad


sys.exit(main(sys.argv[1:]))
