#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import io
import os
import sys

import cairosvg
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "k15"))
import symjoin  # noqa: E402

passed = failed = 0


def say(cond, msg):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + msg)
    else:
        failed += 1
        print("  FAIL  " + msg)


def alpha(png_or_arr, size=None):
    if isinstance(png_or_arr, bytes):
        im = Image.open(io.BytesIO(png_or_arr)).convert("RGBA")
    else:
        im = png_or_arr
    return np.asarray(im)[..., 3].astype(float)


def osym_image(blob):
    size = int.from_bytes(blob[4:8], "little")
    px = np.frombuffer(blob[12:12 + size * size * 4], dtype=np.uint8).reshape(size, size, 4)
    return Image.fromarray(px, "RGBA")


def reference(svg, size):
    return alpha(cairosvg.svg2png(url=svg, output_width=size, output_height=size))


def main(root):
    bundles = [d for d in sorted(glob.glob(os.path.join(root, "assets/apps/*.osp")) + [os.path.join(root, "pakete/jarvismini")])
               if os.path.isfile(os.path.join(d, "symbol.svg"))]
    say(len(bundles) >= 22, "%d bundles carry symbol.svg" % len(bundles))
    errs = {size: [] for size in (22, 32, 44, 64)}
    old_errs = {size: [] for size in (22, 32, 44, 64)}
    slot_bad = 0
    worst_native = 0.0
    for d in bundles:
        svg = os.path.join(d, "symbol.svg")
        joined = symjoin.joined(d)
        if len(joined) != 44900:
            slot_bad += 1
            continue
        blobs = {72: joined[:20748], 44: joined[20748:28504], 64: joined[28504:]}
        if not (symjoin.osym_ok(blobs[44], 44) and symjoin.osym_ok(blobs[64], 64)):
            slot_bad += 1
            continue
        img = {size: osym_image(blob) for size, blob in blobs.items()}
        for size in (44, 64):
            worst_native = max(worst_native, float(np.abs(alpha(img[size]) - reference(svg, size)).mean()))
        for size, src in ((22, 44), (32, 64), (44, 44), (64, 64)):
            ref = reference(svg, size)
            errs[size].append(float(np.abs(alpha(img[src].resize((size, size), Image.BOX)) - ref).mean()))
            old_errs[size].append(float(np.abs(alpha(img[72].resize((size, size), Image.BOX)) - ref).mean()))
    say(slot_bad == 0, "every bundle joins to one 44900-byte slot (72 + 44 + 64 pictures)")
    say(worst_native <= 1.5, "44 and 64 px bakes match cairosvg (worst alpha mean %.2f <= 1.5)" % worst_native)
    for size in (22, 32, 44, 64):
        new_mean = float(np.mean(errs[size]))
        old_mean = float(np.mean(old_errs[size]))
        say(new_mean <= 1.2 and max(errs[size]) <= 3.0,
            "row size %d from the exact bake: alpha mean %.2f (worst icon %.2f) <= 1.2 / 3.0" % (size, new_mean, max(errs[size])))
        say(old_mean >= 2.5 * new_mean,
            "counter-proof: size %d from the 72 px picture alone is worse (mean %.2f >= 2.5 x %.2f)" % (size, old_mean, new_mean))
    print("ROWICONS-HOST: %d passed, %d failed" % (passed, failed))
    return failed == 0


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv[1] if len(sys.argv) > 1 else ".") else 1)
