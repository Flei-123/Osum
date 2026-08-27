#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/theme/model.py -- THE SECOND IMPLEMENTATION OF THE TOKEN SYSTEM.

`kernel/user/wlibc.fi` resolves the three token layers inside Osum, in
Firn, with 64-bit integers and no floating point.  This file resolves
the same three layers in Python.  Neither knows about the other; the
test runner (`tests/theme/run.sh`) prints both and compares them token
for token.

That is the only reason this file exists.  A colour table that is only
produced by the code under test proves nothing about the code under
test.

    model.py tokens <scheme.file> <light|dark> [accent-hex]
    model.py contrast <scheme.file> <light|dark> [accent-hex]
    model.py srgb                       the 256 linear-light values
    model.py table <scheme> [<scheme> ...]   the documentation table

THE ARITHMETIC IS DELIBERATELY THE INTEGER ARITHMETIC, not the obvious
floating-point one: the point is to reproduce what the operating system
computes, bit for bit.  `model.py srgb --float` prints the float
reference next to it so the integer routine itself can be judged.
"""
import os
import sys

# ---------------------------------------------------------------- fixed point
#
# One scale for everything: 1.0 == 1 << 24.  A product of two values in
# [0,1] fits in 48 bits, so u64 never overflows and Firn needs no
# 128-bit type.
SCALE = 1 << 24


def mulf(a, b):
    return (a * b) >> 24


def fifth_root(v):
    """v**(1/5) in fixed point, by Newton's method.

    r <- (4r + v/r^4) / 5.  Sixty iterations is far more than needed;
    the loop leaves early when it stops moving.  Firn has the same loop.
    """
    if v == 0:
        return 0
    r = SCALE
    for _ in range(60):
        r2 = mulf(r, r)
        r4 = mulf(r2, r2)
        if r4 == 0:
            break
        q = (v << 24) // r4
        nr = (4 * r + q) // 5
        if nr == r:
            break
        r = nr
    return r


def lin_of(c):
    """One sRGB channel (0..255) -> linear light, scaled by SCALE.

    WCAG 2.x:  c <= 0.03928 ? c/12.92 : ((c+0.055)/1.055)**2.4
    and x**2.4 == x**2 * (x**2)**(1/5), which is why the fifth root is
    all the machinery this needs.  0.03928*255 = 10.02, so the integer
    cut is at c <= 10 -- the same cut in both implementations.
    """
    x = (c * SCALE) // 255
    if c <= 10:
        return (x * 10000) // 129200
    t = ((x + (55 * SCALE) // 1000) * 1000) // 1055
    t2 = mulf(t, t)
    return mulf(t2, fifth_root(t2))


def luminance(rgb):
    """Relative luminance, scaled by SCALE."""
    return (2126 * lin_of((rgb >> 16) & 255)
            + 7152 * lin_of((rgb >> 8) & 255)
            + 722 * lin_of(rgb & 255)) // 10000


def contrast100(a, b):
    """(L1+0.05)/(L2+0.05), times 100.  452 means 4.52:1."""
    la, lb = luminance(a), luminance(b)
    if la < lb:
        la, lb = lb, la
    return ((la + SCALE // 20) * 100) // (lb + SCALE // 20)


def mix(a, b, p):
    """p percent of b into a, per sRGB channel.

    Mixing in sRGB and not in linear light.  That is a simplification
    and it is a visible one: a 50/50 mix comes out darker than the eye
    expects.  It is kept because the ramps are anchored on hand-picked
    values from the palette file, so the mix only has to interpolate
    BETWEEN anchors, and because the alternative needs the inverse
    transfer function on the hot path.
    """
    out = 0
    for s in (16, 8, 0):
        ca = (a >> s) & 255
        cb = (b >> s) & 255
        out |= (((ca * (100 - p) + cb * p) // 100) & 255) << s
    return out


# ------------------------------------------------------------ layer 1: ramps
WHITE = 0xFFFFFF
BLACK = 0x000000
# steps 100..500 are the base mixed towards white, 700..900 towards
# black.  The base itself is step 600.  The percentages are read off
# the Tailwind ramps that the palette file is built on, so a ramp
# generated from #2563EB lands within a few units of blue-100..blue-900.
LIGHTEN = [88, 76, 60, 38, 18]
DARKEN = [16, 33, 50]
A_100, A_200, A_300, A_400, A_500, A_600, A_700, A_800, A_900 = range(9)

NEUTRAL_KEYS = ["neutral0", "neutral50", "neutral100", "neutral200",
                "neutral300", "neutral400", "neutral500", "neutral600",
                "neutral700", "neutral800", "neutral900", "neutral950",
                "neutral1000"]
(N_0, N_50, N_100, N_200, N_300, N_400, N_500, N_600, N_700, N_800,
 N_900, N_950, N_1000) = range(13)


def ramp(base):
    r = [0] * 9
    for i, p in enumerate(LIGHTEN):
        r[i] = mix(base, WHITE, p)
    r[A_600] = base
    for i, p in enumerate(DARKEN):
        r[A_700 + i] = mix(base, BLACK, p)
    return r


# -------------------------------------------------------- layer 2: semantics
SEMANTIC = [
    "surface", "surface-raised", "surface-sunken", "surface-hover",
    "surface-pressed", "text-primary", "text-secondary", "text-disabled",
    "border", "border-strong", "border-focus", "accent", "accent-hover",
    "accent-pressed", "accent-disabled", "on-accent", "selection",
    "on-selection", "overlay", "danger", "warning", "success", "shadow",
]
S = {n: i for i, n in enumerate(SEMANTIC)}

# -------------------------------------------------------- layer 3: components
#
# Every entry is a SEMANTIC NAME.  There is no raw colour on this side
# of the file and there is none on the Firn side either; that is what
# tests/theme/rohfarben.py counts.
COMPONENT = [
    ("window-bg", "surface"),
    ("window-text", "text-primary"),
    ("text-muted", "text-secondary"),
    ("panel-bg", "surface-raised"),
    ("button-face", "surface-raised"),
    ("button-hover", "surface-hover"),
    ("button-pressed", "surface-pressed"),
    ("border", "border"),
    ("select-bg", "selection"),
    ("select-text", "on-selection"),
    ("focus-ring", "border-focus"),
    ("input-bg", "surface-sunken"),
    ("header-bg", "surface-hover"),
    ("scroll-track", "surface-sunken"),
    ("scroll-thumb", "border-strong"),
    ("accent", "accent"),
    ("dialog-bg", "overlay"),
    ("menu-bg", "overlay"),
    ("titlebar-bg", "accent"),
    ("titlebar-text", "on-accent"),
    ("titlebar-off-bg", "surface-raised"),
    ("titlebar-off-text", "text-secondary"),
    ("window-frame", "border-strong"),
    ("taskbar-bg", "surface-raised"),
    ("taskbar-text", "text-primary"),
    ("taskbar-active", "accent"),
    ("desktop-top", "surface-sunken"),
    ("desktop-bottom", "surface"),
    ("button-text", "text-primary"),
    ("button-disabled-text", "text-disabled"),
    ("input-text", "text-primary"),
    ("input-border", "border-strong"),
    ("list-bg", "surface-sunken"),
    ("menu-text", "text-primary"),
    ("shadow", "shadow"),
    ("danger", "danger"),
    ("warning", "warning"),
    ("success", "success"),
    ("on-accent", "on-accent"),
    ("accent-hover", "accent-hover"),
    ("accent-pressed", "accent-pressed"),
]


def read_scheme(path):
    """A scheme file is key=value, one per line, '#' starts a comment."""
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def hexval(s):
    return int(s, 16)


def pick_on(fg_candidates, bg):
    """The text colour for a surface: whichever candidate reads better.

    This is the piece that makes a badly chosen accent survivable.  It
    is not a fallback for the user's mistake -- the mistake is still
    reported -- it is the difference between "hard to read" and
    "invisible".
    """
    best = fg_candidates[0]
    bestr = 0
    for c in fg_candidates:
        r = contrast100(c, bg)
        if r > bestr:
            bestr, best = r, c
    return best, bestr


def resolve(scheme, dark, accent_override=None):
    """primitives -> semantics -> components.  Returns everything."""
    neutral = [hexval(scheme[k]) for k in NEUTRAL_KEYS]
    accent_base = hexval(accent_override if accent_override
                         else scheme["accent"])
    high = scheme.get("contrast", "normal") == "high"

    ra = ramp(accent_base)
    rd = ramp(hexval(scheme.get("danger", "dc2626")))
    rw = ramp(hexval(scheme.get("warning", "b45309")))
    rs = ramp(hexval(scheme.get("success", "15803d")))

    sem = [0] * len(SEMANTIC)

    def put(n, v):
        sem[S[n]] = v

    if not dark:
        if high:
            put("surface", neutral[N_0])
            put("surface-raised", neutral[N_0])
            put("surface-sunken", neutral[N_0])
            put("surface-hover", neutral[N_100])
            put("surface-pressed", neutral[N_200])
            put("text-primary", neutral[N_1000])
            put("text-secondary", neutral[N_1000])
            put("text-disabled", neutral[N_500])
            put("border", neutral[N_1000])
            put("border-strong", neutral[N_1000])
            put("shadow", neutral[N_1000])
        else:
            put("surface", neutral[N_50])
            put("surface-raised", neutral[N_0])
            put("surface-sunken", neutral[N_100])
            put("surface-hover", neutral[N_100])
            put("surface-pressed", neutral[N_200])
            put("text-primary", neutral[N_900])
            # n600 and not n500: n500 on surface-sunken measures 4.34:1
            # and that is below 4.5.  The number decided the token.
            put("text-secondary", neutral[N_600])
            put("text-disabled", neutral[N_400])
            put("border", neutral[N_200])
            # n500 and not n400: a control boundary is a user interface
            # component (WCAG 1.4.11) and needs 3:1.  n400 measures
            # 2.45:1 on this surface.  The number decided the token.
            put("border-strong", neutral[N_500])
            put("shadow", neutral[N_950])
        start, step = A_600, +1
    else:
        if high:
            put("surface", neutral[N_1000])
            put("surface-raised", neutral[N_1000])
            put("surface-sunken", neutral[N_1000])
            put("surface-hover", neutral[N_800])
            put("surface-pressed", neutral[N_700])
            put("text-primary", neutral[N_0])
            put("text-secondary", neutral[N_0])
            put("text-disabled", neutral[N_400])
            put("border", neutral[N_0])
            put("border-strong", neutral[N_0])
            put("shadow", neutral[N_1000])
        else:
            put("surface", neutral[N_900])
            put("surface-raised", neutral[N_800])
            put("surface-sunken", neutral[N_950])
            put("surface-hover", neutral[N_800])
            put("surface-pressed", neutral[N_700])
            put("text-primary", neutral[N_50])
            put("text-secondary", neutral[N_400])
            put("text-disabled", neutral[N_600])
            put("border", neutral[N_700])
            put("border-strong", neutral[N_500])
            put("shadow", neutral[N_1000])
        start, step = A_400, -1

    # ---- the accent, and the check that decides whether it may stay
    #
    # Two rules, both WCAG 2.1: text on the accent needs 4.5:1 (1.4.3),
    # and the accent is a user interface component against the surface
    # and needs 3:1 (1.4.11).  The high-contrast scheme raises both to
    # 7:1 and 4.5:1 -- that is what it is for.
    #
    # HOVER AND PRESSED ARE NOT RAMP STEPS.  They were, and the green
    # accent of `night` showed why that is wrong: on a green the
    # readable label is BLACK, so walking the ramp darker to satisfy
    # the surface rule walks the label rule off a cliff, and no step of
    # a green ramp satisfies both at once.  They are now derived from
    # the accent in the direction that can only HELP the label: if the
    # label is the light candidate the states go darker, if it is the
    # dark candidate they go lighter.  Then the label contrast of the
    # hover and pressed states is >= that of the accent itself, by
    # construction, and only one pairing has to be searched.
    need_text = 700 if high else 450
    need_ui = 450 if high else 300
    on_candidates = [neutral[N_0], neutral[N_1000], neutral[N_900]]

    def states_of(a):
        on, _ = pick_on(on_candidates, a)
        towards = BLACK if luminance(on) > luminance(a) else WHITE
        return mix(a, towards, 12), mix(a, towards, 26), on

    def judge(i):
        a = ra[i]
        _h, _p, on = states_of(a)
        return contrast100(on, a), contrast100(a, sem[S["surface"]])

    order = sorted(range(9),
                   key=lambda i: (abs(i - start),
                                  0 if (i - start) * step >= 0 else 1))
    idx = start
    ok = False
    for i in order:
        r_txt, r_bg = judge(i)
        if r_txt >= need_text and r_bg >= need_ui:
            idx, ok = i, True
            break
    if not ok:
        # Nothing on the ramp satisfies both rules.  Take the step that
        # comes closest instead of the one the user asked for -- and
        # keep ok = False, because the settings window has to say so.
        def score(i):
            r_txt, r_bg = judge(i)
            t = r_txt * 100 // need_text
            u = r_bg * 100 // need_ui
            return min(t, 100) + min(u, 100)
        idx = max(range(9), key=score)
    moved = abs(idx - start)
    accent = ra[idx]
    hov_c, prs_c, on_accent = states_of(accent)

    # The focus ring is not the accent.  It is the step of the accent
    # ramp that stands out most against the surface -- for a light
    # scheme the darkest, for a dark scheme the lightest.  Tying it to
    # the accent itself produced a 1.91:1 ring on `night` in light mode.
    focus = max(range(9), key=lambda i: contrast100(ra[i],
                                                    sem[S["surface"]]))

    # The three status colours are read off their own ramps by the same
    # rule as the accent: nearest step to the scheme's own that clears
    # the text bar against the surface, else the step with the most
    # contrast.  Without this the high-contrast scheme in dark mode
    # showed 5.32:1 for danger against its 7:1 bar.
    def fit_status(r):
        cand = sorted(range(9), key=lambda i: (abs(i - start),
                                               0 if (i - start) * step >= 0
                                               else 1))
        for i in cand:
            if contrast100(r[i], sem[S["surface"]]) >= need_text:
                return r[i]
        return max((r[i] for i in range(9)),
                   key=lambda c: contrast100(c, sem[S["surface"]]))

    put("accent", accent)
    put("accent-hover", hov_c)
    put("accent-pressed", prs_c)
    put("accent-disabled", mix(accent, sem[S["surface"]], 65))
    put("on-accent", on_accent)
    put("border-focus", ra[focus])
    put("selection", accent)
    put("on-selection", on_accent)
    put("overlay", sem[S["surface-raised"]])
    put("danger", fit_status(rd))
    put("warning", fit_status(rw))
    put("success", fit_status(rs))

    comp = [(name, sem[S[role]], role) for name, role in COMPONENT]
    return {
        "neutral": neutral, "accent_ramp": ra, "sem": sem, "comp": comp,
        "accent_ok": ok, "accent_moved": moved, "accent_index": idx,
        "dark": dark, "high": high,
    }


# ---------------------------------------------------------------- the checks
#
# Every text-on-surface pairing the system can actually produce.  Not a
# selection of the flattering ones.
TEXT_PAIRS = [
    ("text-primary", "surface", "normal"),
    ("text-primary", "surface-raised", "normal"),
    ("text-primary", "surface-sunken", "normal"),
    ("text-primary", "surface-hover", "normal"),
    ("text-primary", "surface-pressed", "normal"),
    ("text-primary", "overlay", "normal"),
    ("text-secondary", "surface", "normal"),
    ("text-secondary", "surface-raised", "normal"),
    ("text-secondary", "surface-sunken", "normal"),
    ("text-secondary", "surface-hover", "normal"),
    ("on-accent", "accent", "normal"),
    ("on-accent", "accent-hover", "normal"),
    ("on-accent", "accent-pressed", "normal"),
    ("on-selection", "selection", "normal"),
    ("danger", "surface", "normal"),
    ("warning", "surface", "normal"),
    ("success", "surface", "normal"),
    # non-text: a user interface component against its background, 3:1
    ("accent", "surface", "ui"),
    ("border-focus", "surface", "ui"),
    ("border-strong", "surface", "ui"),
    ("border", "surface", "decor"),
]
# A divider inside a panel is decoration and WCAG 1.4.11 exempts it
# outright.  It is measured and printed anyway -- a number that is
# allowed to be low still has to be looked at.
LIMIT = {"normal": 450, "large": 300, "ui": 300, "decor": 0}
LIMIT_HIGH = {"normal": 700, "large": 450, "ui": 450, "decor": 0}


def checks(res):
    sem = res["sem"]
    lim = LIMIT_HIGH if res["high"] else LIMIT
    out = []
    for fg, bg, kind in TEXT_PAIRS:
        r = contrast100(sem[S[fg]], sem[S[bg]])
        out.append((fg, bg, kind, sem[S[fg]], sem[S[bg]], r,
                    r >= lim[kind]))
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "srgb":
        for c in range(256):
            print("%d %d" % (c, lin_of(c)))
        return 0
    if cmd == "ratio":
        print(contrast100(hexval(sys.argv[2]), hexval(sys.argv[3])))
        return 0
    if cmd in ("tokens", "contrast", "semantic"):
        sch = read_scheme(sys.argv[2])
        dark = sys.argv[3] == "dark"
        acc = sys.argv[4] if len(sys.argv) > 4 else None
        res = resolve(sch, dark, acc)
        if cmd == "tokens":
            for i, (name, val, role) in enumerate(res["comp"]):
                print("%d %s %06x %s" % (i, name, val, role))
            print("accent_ok %d" % (1 if res["accent_ok"] else 0))
            print("accent_moved %d" % res["accent_moved"])
        elif cmd == "semantic":
            for i, n in enumerate(SEMANTIC):
                print("%d %s %06x" % (i, n, res["sem"][i]))
        else:
            for fg, bg, kind, cf, cb, r, good in checks(res):
                print("%s %s %s %06x %06x %d %d"
                      % (fg, bg, kind, cf, cb, r, 1 if good else 0))
        return 0
    if cmd == "table":
        for path in sys.argv[2:]:
            sch = read_scheme(path)
            nm = os.path.basename(path)
            for mode in ("light", "dark"):
                res = resolve(sch, mode == "dark")
                worst = min(c[5] for c in checks(res) if c[2] == "normal")
                bad = [c for c in checks(res) if not c[6]]
                print("| `%s` | %s | %s | %.2f:1 | %d |"
                      % (nm, sch.get("name", "?"), mode, worst / 100.0,
                         len(bad)))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
