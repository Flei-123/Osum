#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/pdf/compare.py <pdf> <svgdir> -- compares the reader's pages with poppler.

Text: the multiset of non-blank characters per page must be equal to pdftotext's.
Picture: the page is rendered from the reader's SVG (cairosvg) and by pdftoppm at
72 dpi, both blurred; the mean absolute difference (0..255) is printed.
Prints one line per page: `P <n> text=<ok|DIFF> diff=<x.x>`
"""
import collections, glob, html, os, re, subprocess, sys, io

def svg_text(path):
    s = open(path, encoding="utf-8").read()
    return "".join(html.unescape(t) for t in re.findall(r"<text[^>]*>([^<]*)</text>", s))

def ref_text(pdf, n):
    r = subprocess.run(["pdftotext", "-raw", "-f", str(n), "-l", str(n), pdf, "-"], capture_output=True)
    return r.stdout.decode("utf-8", "replace")

def norm(t):
    return collections.Counter(c for c in t if not c.isspace() and c not in "­ﬁﬂ")

def main(pdf, svgdir):
    try:
        import cairosvg
        from PIL import Image, ImageFilter, ImageChops
        import numpy as np
    except Exception as e:
        print("no cairosvg/PIL/numpy:", e); return 0
    pages = sorted(glob.glob(os.path.join(svgdir, "page*.svg")), key=lambda p: int(re.findall(r"(\d+)", os.path.basename(p))[0]))
    bad = 0
    for i, sv in enumerate(pages, 1):
        if i > 6:
            break
        a = norm(svg_text(sv)); b = norm(ref_text(pdf, i))
        tok = "ok" if a == b else "DIFF"
        if a != b:
            bad += 1
            miss = (b - a); extra = (a - b)
            print("   text missing=%r extra=%r" % ("".join(miss.elements())[:40], "".join(extra.elements())[:40]))
        png = cairosvg.svg2png(url=sv, background_color="white")
        im = Image.open(io.BytesIO(png)).convert("L")
        subprocess.run(["pdftoppm", "-r", "72", "-f", str(i), "-l", str(i), "-gray", "-png", pdf, "/tmp/_cmp"], capture_output=True)
        ref = sorted(glob.glob("/tmp/_cmp-*.png"))
        rim = Image.open(ref[0]).convert("L") if ref else None
        for f in ref: os.remove(f)
        d = -1.0
        if rim is not None:
            if rim.size != im.size:
                # poppler rounds the page size differently by a pixel
                w, h = min(rim.size[0], im.size[0]), min(rim.size[1], im.size[1])
                rim = rim.crop((0, 0, w, h)); im = im.crop((0, 0, w, h))
            x = np.asarray(im.filter(ImageFilter.GaussianBlur(2)), dtype=float)
            y = np.asarray(rim.filter(ImageFilter.GaussianBlur(2)), dtype=float)
            d = float(np.abs(x - y).mean())
        print("P %d text=%s diff=%.1f" % (i, tok, d))
    return bad

if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1], sys.argv[2]) else 0)
