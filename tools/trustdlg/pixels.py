# SPDX-License-Identifier: GPL-2.0-only
import re
import sys
from PIL import Image

PALETTES = {
    "light": {"head": 0xE6E6E6, "body": 0xFFFFFF, "foot": 0xF0F0F0, "text": 0x1B1B1B, "accent": 0x0067C0,
              "button": 0xFBFBFB, "ring": 0x1B1B1B},
    "dark": {"head": 0x383838, "body": 0x202020, "foot": 0x2B2B2B, "text": 0xFFFFFF, "accent": 0x4CC2FF,
             "button": 0x3A3A3A, "ring": 0xFFFFFF},
}
TOLERANCE = 4
SAMPLE_INSET_RIGHT = 90
SAMPLE_BODY_INSET = 30


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def near(a, b, tol=TOLERANCE):
    return all(abs(a[i] - b[i]) <= tol for i in range(3))


def luma(p):
    return (p[0] * 30 + p[1] * 59 + p[2] * 11) // 100


def layout(line):
    fields = {}
    for key in ("y", "foot", "btn", "bh", "h", "x", "w", "yes", "no", "bw", "k", "rem"):
        m = re.search(r" %s=(\d+)" % key, line)
        fields[key] = int(m.group(1)) if m else None
    m = re.search(r" body=(\d+)-(\d+)", line)
    fields["body0"], fields["body1"] = (int(m.group(1)), int(m.group(2))) if m else (None, None)
    return fields


def run_len(px, x_in, y, foot):
    left = x_in
    while not near(px[left - 1, y], foot, 2):
        left -= 1
    right = x_in
    while not near(px[right + 1, y], foot, 2):
        right += 1
    return right - left + 1


def main(root, mode, line):
    pal = {k: rgb(v) for k, v in PALETTES[mode].items()}
    f = layout(line)
    if any(v is None for v in f.values()):
        print("PIXELS-FAIL layout line incomplete: %s" % line)
        return 1
    k = f["k"]
    bad = 0

    def check(ok, text):
        nonlocal bad
        print(("  ok    " if ok else "  FAIL  ") + text)
        if not ok:
            bad += 1

    up = Image.open("%s/2-up.png" % root).convert("RGB").load()
    tab = Image.open("%s/3-tab.png" % root).convert("RGB").load()
    done = Image.open("%s/4-done.png" % root).convert("RGB").load()
    mid = f["btn"] + f["bh"] // 2
    head_p = up[f["x"] + f["w"] - SAMPLE_INSET_RIGHT * k, f["y"] + 22 * k]
    body_p = up[f["x"] + f["w"] - SAMPLE_BODY_INSET * k, f["body0"] + 12 * k]
    foot_p = up[f["x"] + f["w"] // 2, f["foot"] + 8 * k]
    check(near(head_p, pal["head"]), "%s head surface %s (want %s)" % (mode, head_p, pal["head"]))
    check(near(body_p, pal["body"]), "%s body surface %s (want %s)" % (mode, body_p, pal["body"]))
    check(near(foot_p, pal["foot"]), "%s footer surface %s (want %s)" % (mode, foot_p, pal["foot"]))
    check(luma(head_p) != luma(body_p), "head and body differ")
    yes_p = up[f["yes"] + 14 * k, mid]
    no_p = up[f["no"] + 14 * k, mid]
    check(near(no_p, pal["accent"]), "No is the accent button %s (want %s)" % (no_p, pal["accent"]))
    check(near(yes_p, pal["button"]), "Yes is the neutral button %s (want %s)" % (yes_p, pal["button"]))
    wy = run_len(up, f["yes"] + 14 * k, mid, pal["foot"])
    wn = run_len(up, f["no"] + 14 * k, mid, pal["foot"])
    check(abs(wy - f["bw"]) <= 3 * k, "Yes button width %d px (layout bw %d)" % (wy, f["bw"]))
    check(abs(wn - (f["bw"] + 4 * k)) <= 3 * k, "No button width incl. focus ring %d px (bw %d + ring)" % (wn, f["bw"]))
    check(near(up[f["no"] - k, mid], pal["ring"], 12), "default focus ring on No")
    check(not near(up[f["yes"] - k, mid], pal["ring"], 12), "no ring on Yes by default")
    check(near(tab[f["yes"] - k, mid], pal["ring"], 12), "Tab moves the ring to Yes")
    check(near(tab[f["yes"] + 14 * k, mid], pal["button"]), "Yes stays neutral with focus")
    dim = luma(tab[4, 4])
    lit = luma(done[4, 4])
    check(dim * 100 <= lit * 75 or lit < 24, "desktop dimmed behind the dialog (%d vs %d)" % (dim, lit))
    print("PIXELS-OK" if bad == 0 else "PIXELS-FAIL %d" % bad)
    return 0 if bad == 0 else 1


sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
