#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/theme/model.py -- THE SECOND IMPLEMENTATION OF THE TOKEN SYSTEM.

`kernel/user/uitheme/thengine.fi` resolves the three token layers inside Osum, in
Firn, with 64-bit integers and no floating point.  This file resolves
the same three layers in Python.  Neither knows about the other; the
test runner (`tests/theme/run.sh`) prints both and compares them token
for token.

That is the only reason this file exists.  A colour table that is only
produced by the code under test proves nothing about the code under
test.

    model.py tokens <scheme.file> <light|dark> [accent-hex]
    model.py contrast <scheme.file> <light|dark> [accent-hex]
    model.py fill <scheme.file> <light|dark>   fill rule: OKLab distances
    model.py srgb                       the 256 linear-light values
    model.py table <scheme> [<scheme> ...]   the documentation table

THE ARITHMETIC IS DELIBERATELY THE INTEGER ARITHMETIC, not the obvious
floating-point one: the point is to reproduce what the operating system
computes, bit for bit.  `model.py srgb --float` prints the float
reference next to it so the integer routine itself can be judged.
"""
import os
import re
import sys

SCALE = 1 << 24


def mulf(a, b):
    return (a * b) >> 24


def fifth_root(v):
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
    x = (c * SCALE) // 255
    if c <= 10:
        return (x * 10000) // 129200
    t = ((x + (55 * SCALE) // 1000) * 1000) // 1055
    t2 = mulf(t, t)
    return mulf(t2, fifth_root(t2))


def luminance(rgb):
    return (2126 * lin_of((rgb >> 16) & 255)
            + 7152 * lin_of((rgb >> 8) & 255)
            + 722 * lin_of(rgb & 255)) // 10000


def contrast100(a, b):
    la, lb = luminance(a), luminance(b)
    if la < lb:
        la, lb = lb, la
    return ((la + SCALE // 20) * 100) // (lb + SCALE // 20)


HOVER_PCT_LIGHT = 6
HOVER_PCT_DARK = 8


def mix(a, b, p):
    out = 0
    for s in (16, 8, 0):
        ca = (a >> s) & 255
        cb = (b >> s) & 255
        out |= (((ca * (100 - p) + cb * p) // 100) & 255) << s
    return out


WHITE = 0xFFFFFF
BLACK = 0x000000
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


SEMANTIC = [
    "surface", "surface-raised", "surface-sunken", "surface-hover",
    "surface-pressed", "text-primary", "text-secondary", "text-disabled",
    "border", "border-strong", "border-focus", "accent", "accent-hover",
    "accent-pressed", "accent-disabled", "on-accent", "selection",
    "on-selection", "overlay", "danger", "warning", "success", "shadow",
    "control", "control-hover", "control-pressed", "field",
]
S = {n: i for i, n in enumerate(SEMANTIC)}

COMPONENT = [
    ("window-bg", "surface"),
    ("window-text", "text-primary"),
    ("text-muted", "text-secondary"),
    ("panel-bg", "surface-raised"),
    ("button-face", "control"),
    ("button-hover", "control-hover"),
    ("button-pressed", "control-pressed"),
    ("border", "border"),
    ("select-bg", "selection"),
    ("select-text", "on-selection"),
    ("focus-ring", "border-focus"),
    ("input-bg", "field"),
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
    ("list-bg", "field"),
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


def palette_roles():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "palette", "dark.tsv")
    roles = {}
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        role, hexs, _ = line.rstrip("\n").split("\t")
        roles[role] = int(hexs, 16)
    return roles


def palette_bindings(name):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "palette", "gen.py")
    text = open(path, encoding="utf-8").read()
    block = text[text.index(name + " = ["):]
    block = block[:block.index("]")]
    return [(m.group(1)[2:].lower().replace("_", "-"), m.group(2))
            for m in re.finditer(r'\("(S_[A-Z_]+)", "([a-z_]+)"\)', block)]


def hexval(s):
    return int(s, 16)


def pick_on(fg_candidates, bg):
    best = fg_candidates[0]
    bestr = 0
    for c in fg_candidates:
        r = contrast100(c, bg)
        if r > bestr:
            bestr, best = r, c
    return best, bestr


def resolve(scheme, dark, accent_override=None):
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
            put("control", neutral[N_100])
            put("control-hover", neutral[N_200])
            put("control-pressed", neutral[N_300])
            put("field", neutral[N_100])
            put("text-primary", neutral[N_1000])
            put("text-secondary", neutral[N_1000])
            put("text-disabled", neutral[N_500])
            put("border", neutral[N_1000])
            put("border-strong", neutral[N_1000])
            put("shadow", neutral[N_1000])
        else:
            put("surface", neutral[N_50])
            put("surface-raised", neutral[N_0])
            put("surface-sunken", neutral[N_200])
            put("surface-hover", neutral[N_100])
            put("surface-pressed", neutral[N_200])
            put("control", neutral[N_200])
            put("control-hover", mix(neutral[N_200], neutral[N_900], HOVER_PCT_LIGHT))
            put("control-pressed", neutral[N_400])
            put("field", neutral[N_100])
            put("text-primary", neutral[N_900])
            put("text-secondary", neutral[N_600])
            put("text-disabled", neutral[N_400])
            put("border", neutral[N_300])
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
            put("control", neutral[N_800])
            put("control-hover", neutral[N_700])
            put("control-pressed", neutral[N_600])
            put("field", neutral[N_800])
            put("text-primary", neutral[N_0])
            put("text-secondary", neutral[N_0])
            put("text-disabled", neutral[N_400])
            put("border", neutral[N_0])
            put("border-strong", neutral[N_0])
            put("shadow", neutral[N_1000])
        else:
            put("surface", neutral[N_900])
            put("surface-raised", neutral[N_800])
            put("surface-sunken", neutral[N_1000])
            put("surface-hover", mix(neutral[N_800], neutral[N_0], HOVER_PCT_DARK))
            put("surface-pressed", neutral[N_600])
            put("control", neutral[N_700])
            put("control-hover", mix(neutral[N_700], neutral[N_0], HOVER_PCT_DARK))
            put("control-pressed", neutral[N_500])
            put("field", neutral[N_950])
            put("text-primary", neutral[N_50])
            put("text-secondary", neutral[N_300])
            put("text-disabled", neutral[N_600])
            put("border", neutral[N_700])
            put("border-strong", neutral[N_500])
            put("shadow", neutral[N_1000])
        start, step = A_400, -1

    pal = dark and not high and scheme.get("palette") != "own"
    roles = palette_roles() if pal else {}
    if pal:
        for sem_name, role in palette_bindings("SURFACE_BINDINGS"):
            put(sem_name, roles[role])

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
        def score(i):
            r_txt, r_bg = judge(i)
            t = r_txt * 100 // need_text
            u = r_bg * 100 // need_ui
            return min(t, 100) + min(u, 100)
        idx = max(range(9), key=score)
    moved = abs(idx - start)
    accent = ra[idx]
    hov_c, prs_c, on_accent = states_of(accent)

    focus = max(range(9), key=lambda i: contrast100(ra[i],
                                                    sem[S["surface"]]))

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
    if high:
        put("selection", accent)
        put("on-selection", on_accent)
    else:
        put("selection", mix(sem[S["surface-raised"]], accent, 22))
        put("on-selection", sem[S["text-primary"]])
    put("overlay", sem[S["surface-raised"]])
    put("danger", fit_status(rd))
    put("warning", fit_status(rw))
    put("success", fit_status(rs))

    if pal:
        if accent_override is None:
            for sem_name, role in palette_bindings("ACCENT_BINDINGS"):
                put(sem_name, roles[role])
        for sem_name, role in palette_bindings("STATUS_BINDINGS"):
            put(sem_name, roles[role])

    comp = [(name, sem[S[role]], role) for name, role in COMPONENT]
    return {
        "neutral": neutral, "accent_ramp": ra, "sem": sem, "comp": comp,
        "accent_ok": ok, "accent_moved": moved, "accent_index": idx,
        "dark": dark, "high": high,
    }


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
    ("text-primary", "control", "normal"),
    ("text-primary", "control-hover", "normal"),
    ("text-primary", "control-pressed", "normal"),
    ("text-primary", "field", "normal"),
    ("accent", "surface", "ui"),
    ("border-focus", "surface", "ui"),
    ("border-strong", "surface", "ui"),
    ("border", "surface", "decor"),
]
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


FILL_MIN = 0.012
FILL_PAIRS = [
    ("field", "surface"), ("field", "surface-raised"),
    ("field", "overlay"), ("field", "surface-sunken"),
    ("control", "surface"), ("control", "surface-raised"),
    ("control", "overlay"),
]


def _lin_f(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab(rgb):
    r, g, b = (_lin_f((rgb >> s) & 255) for s in (16, 8, 0))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def fill_distance(a, b):
    pa, pb = oklab(a), oklab(b)
    return sum((x - y) ** 2 for x, y in zip(pa, pb)) ** 0.5


def fill_checks(res):
    sem = res["sem"]
    out = []
    for w, g in FILL_PAIRS:
        d = fill_distance(sem[S[w]], sem[S[g]])
        out.append((w, g, d, d >= FILL_MIN))
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
        if os.environ.get("MODEL_NO_PALETTE"):
            sch["palette"] = "own"
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
    if cmd == "fill":
        sch = read_scheme(sys.argv[2])
        res = resolve(sch, sys.argv[3] == "dark")
        for w, g, d, good in fill_checks(res):
            print("%s %s %.4f %d" % (w, g, d, 1 if good else 0))
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
