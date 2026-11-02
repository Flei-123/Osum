#!/usr/bin/env python3
import os
import sys
from collections import Counter

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OLD_SLATE = {"0F172A", "1E293B", "020617", "334155", "475569"}
PASS = FAIL = 0


def load_palette():
    pal = {}
    for line in open(os.path.join(ROOT, "assets", "palette", "dark.tsv"), encoding="utf-8"):
        if line.startswith("#"):
            continue
        role, hexs, _ = line.rstrip("\n").split("\t")
        pal[role] = hexs
    return pal


def histogram(path):
    im = Image.open(path).convert("RGB")
    counts = Counter(im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata())
    total = sum(counts.values())
    return {"%02X%02X%02X" % c: n / total for c, n in counts.items()}


def check(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  OK    " + msg)
    else:
        FAIL += 1
        print("  FAIL  " + msg)


def share(h, colors):
    return sum(h.get(c, 0.0) for c in colors)


def main():
    outdir = sys.argv[1]
    pal = load_palette()
    grounds = [pal[r] for r in ("base", "surface", "surface_raised", "field")]
    for name in ("03-einstellungen", "04-explorer", "02-startmenue"):
        h = histogram(os.path.join(outdir, name + ".ppm"))
        floor = 0.35 if name == "02-startmenue" else 0.55
        check(share(h, grounds) >= floor, "%s: palette grounds cover >= %d%% (%.1f%%)" % (name, 100 * floor, 100 * share(h, grounds)))
        check(share(h, OLD_SLATE) < 0.0005, "%s: no slate-ramp pixel left (%.2f%%)" % (name, 100 * share(h, OLD_SLATE)))
    h = histogram(os.path.join(outdir, "03-einstellungen.ppm"))
    top = sorted(h.items(), key=lambda kv: -kv[1])[:2]
    check([c for c, _ in top] == [pal["surface_raised"], pal["surface"]],
          "settings: main surface is surface_raised, side is surface (%s)" % ",".join(c for c, _ in top))
    h = histogram(os.path.join(outdir, "04-explorer.ppm"))
    check(h.get(pal["accent"], 0) >= 0.005, "explorer: accent role present (%.2f%%)" % (100 * h.get(pal["accent"], 0)))
    check(h.get(pal["selection"], 0) >= 0.005, "explorer: selection role present (%.2f%%)" % (100 * h.get(pal["selection"], 0)))
    check(h.get(pal["text"], 0) > 0, "explorer: primary text colour present")
    print("palette pixels: %d ok, %d fail" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)


main()
