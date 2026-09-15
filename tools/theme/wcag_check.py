#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/theme/wcag_check.py -- AN INDEPENDENT THIRD OPINION ON THE CONTRAST.

Written for round FARBE (15.09.2026), point A-021.  `model.py` already
computes contrast, but it does so with the SAME fixed-point arithmetic
the kernel uses, on purpose -- it is a bit-for-bit mirror of Firn, not
an independent judge.  If that shared arithmetic were wrong, both would
be wrong together and agree perfectly.

This file therefore computes the contrast the OTHER way: straight IEEE
double floating point, straight out of the WCAG 2.1 text, with no
lookup table and no Newton iteration.

    relative luminance (WCAG 2.1, "relative luminance"):
        c' = c/255
        c_lin = c'/12.92                     if c' <= 0.03928
              = ((c'+0.055)/1.055) ** 2.4    otherwise
        L = 0.2126*R + 0.7152*G + 0.0722*B

    contrast ratio:
        (L_lighter + 0.05) / (L_darker + 0.05)

If this file and `model.py` disagree by more than a rounding step, one
of the two is wrong and the difference is the finding.

    wcag_check.py pairs            every role pairing, every scheme,
                                   both modes, before/after table
    wcag_check.py ramp <hex>...    contrast of each ramp step on a bg
"""
import sys

# --------------------------------------------------------------- WCAG proper


def srgb_to_linear(c8):
    cs = c8 / 255.0
    if cs <= 0.03928:
        return cs / 12.92
    return ((cs + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r = (rgb >> 16) & 0xFF
    g = (rgb >> 8) & 0xFF
    b = rgb & 0xFF
    return (0.2126 * srgb_to_linear(r)
            + 0.7152 * srgb_to_linear(g)
            + 0.0722 * srgb_to_linear(b))


def contrast(fg, bg):
    a = luminance(fg)
    b = luminance(bg)
    if a < b:
        a, b = b, a
    return (a + 0.05) / (b + 0.05)


# ------------------------------------------------------- the schemes, parsed
#
# Read straight from assets/schemes/*.scheme so this file cannot drift
# away from the real ramps the way model.py drifted away from wlibc.fi.

RAMP_KEYS = ["neutral0", "neutral50", "neutral100", "neutral200",
             "neutral300", "neutral400", "neutral500", "neutral600",
             "neutral700", "neutral800", "neutral900", "neutral950",
             "neutral1000"]
# index into the ramp list, by the name the source uses
N = {k.replace("neutral", "N_"): i for i, k in enumerate(RAMP_KEYS)}


def load(path):
    d = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def ramp_of(scheme):
    return [int(scheme[k], 16) for k in RAMP_KEYS]


# ------------------------------------------------------- the semantic layer
#
# Mirrors kernel/user/wlibc.fi and tools/theme/model.py.  BEFORE is the
# state this round started from; AFTER is the state it proposes.  Only
# the entries that differ are listed in AFTER.

def semantics(ramp, dark, high, text_secondary_dark):
    """The neutral-derived roles.  Accent roles are generated and are
    checked by model.py; this file judges the neutral pairings, which
    is where A-021 sits."""
    n = ramp
    s = {}
    if not dark:
        if high:
            s = dict(surface=n[N["N_0"]], surface_raised=n[N["N_0"]],
                     surface_sunken=n[N["N_0"]], surface_hover=n[N["N_100"]],
                     surface_pressed=n[N["N_200"]],
                     text_primary=n[N["N_1000"]],
                     text_secondary=n[N["N_1000"]],
                     text_disabled=n[N["N_500"]], border=n[N["N_1000"]],
                     border_strong=n[N["N_1000"]])
        else:
            s = dict(surface=n[N["N_50"]], surface_raised=n[N["N_0"]],
                     surface_sunken=n[N["N_100"]], surface_hover=n[N["N_100"]],
                     surface_pressed=n[N["N_200"]],
                     text_primary=n[N["N_900"]],
                     text_secondary=n[N["N_600"]],
                     text_disabled=n[N["N_400"]], border=n[N["N_200"]],
                     border_strong=n[N["N_500"]])
    else:
        if high:
            s = dict(surface=n[N["N_1000"]], surface_raised=n[N["N_1000"]],
                     surface_sunken=n[N["N_1000"]], surface_hover=n[N["N_800"]],
                     surface_pressed=n[N["N_700"]], text_primary=n[N["N_0"]],
                     text_secondary=n[N["N_0"]],
                     text_disabled=n[N["N_400"]], border=n[N["N_0"]],
                     border_strong=n[N["N_0"]])
        else:
            s = dict(surface=n[N["N_900"]], surface_raised=n[N["N_800"]],
                     surface_sunken=n[N["N_950"]], surface_hover=n[N["N_700"]],
                     surface_pressed=n[N["N_600"]], text_primary=n[N["N_50"]],
                     text_secondary=n[N[text_secondary_dark]],
                     text_disabled=n[N["N_600"]], border=n[N["N_700"]],
                     border_strong=n[N["N_500"]])
    return s


# Every neutral pairing the system can produce, with its WCAG class.
# Taken from TEXT_PAIRS in model.py -- the accent pairings are left to
# model.py because the accent is generated, not tabulated.
PAIRS = [
    ("text_primary", "surface", "normal"),
    ("text_primary", "surface_raised", "normal"),
    ("text_primary", "surface_sunken", "normal"),
    ("text_primary", "surface_hover", "normal"),
    ("text_primary", "surface_pressed", "normal"),
    ("text_secondary", "surface", "normal"),
    ("text_secondary", "surface_raised", "normal"),
    ("text_secondary", "surface_sunken", "normal"),
    ("text_secondary", "surface_hover", "normal"),
    ("border_strong", "surface", "ui"),
    ("border", "surface", "decor"),
]
LIMIT = {"normal": 4.5, "large": 3.0, "ui": 3.0, "decor": 0.0}
LIMIT_HIGH = {"normal": 7.0, "large": 4.5, "ui": 4.5, "decor": 0.0}

SCHEMES = ["day", "paper", "night", "midnight", "contrast"]


def run_pairs():
    bad_before = bad_after = 0
    rows = []
    for name in SCHEMES:
        sc = load("assets/schemes/%s.scheme" % name)
        ramp = ramp_of(sc)
        high = sc.get("contrast", "normal") == "high"
        for dark in (False, True):
            before = semantics(ramp, dark, high, "N_400")
            after = semantics(ramp, dark, high, "N_300")
            lim = LIMIT_HIGH if high else LIMIT
            for fg, bg, kind in PAIRS:
                need = lim[kind]
                cb = contrast(before[fg], before[bg])
                ca = contrast(after[fg], after[bg])
                okb = cb >= need or need == 0.0
                oka = ca >= need or need == 0.0
                if not okb:
                    bad_before += 1
                if not oka:
                    bad_after += 1
                rows.append((name, "dark" if dark else "light", fg, bg,
                             kind, need, before[fg], before[bg], cb, okb,
                             after[fg], ca, oka))

    print("%-9s %-5s %-14s %-15s %-6s %6s | %-8s %7s %-4s | %-8s %7s %-4s"
          % ("schema", "modus", "vordergrund", "hintergrund", "art",
             "soll", "vorher", "wert", "ok", "nachher", "wert", "ok"))
    print("-" * 118)
    for (nm, md, fg, bg, kind, need, fgb, bgb, cb, okb,
         fga, ca, oka) in rows:
        mark = ""
        if okb != oka:
            mark = "  <== geaendert"
        print("%-9s %-5s %-14s %-15s %-6s %6s | #%06x %7.3f %-4s | #%06x %7.3f %-4s%s"
              % (nm, md, fg.replace("_", "-"), bg.replace("_", "-"), kind,
                 ("%.1f" % need) if need else "-",
                 fgb, cb, "OK" if okb else "ROT",
                 fga, ca, "OK" if oka else "ROT", mark))
    print("-" * 118)
    print("Paarungen gesamt: %d" % len(rows))
    print("unter der Schwelle VORHER  (text-secondary = N_400 dunkel): %d"
          % bad_before)
    print("unter der Schwelle NACHHER (text-secondary = N_300 dunkel): %d"
          % bad_after)
    return bad_after


def run_ramp(args):
    """Contrast of every ramp step against one background, so a token
    choice can be judged instead of guessed."""
    for name in SCHEMES:
        sc = load("assets/schemes/%s.scheme" % name)
        ramp = ramp_of(sc)
        print("== %s" % name)
        for bgname in ("N_700", "N_800", "N_900", "N_950"):
            bg = ramp[N[bgname]]
            out = []
            for step in ("N_200", "N_300", "N_400", "N_500"):
                out.append("%s #%06x %6.3f"
                           % (step, ramp[N[step]],
                              contrast(ramp[N[step]], bg)))
            print("   auf %s #%06x : %s" % (bgname, bg, "   ".join(out)))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "pairs"
    if cmd == "pairs":
        sys.exit(1 if run_pairs() else 0)
    elif cmd == "ramp":
        run_ramp(sys.argv[2:])
    else:
        print(__doc__)
        sys.exit(2)
