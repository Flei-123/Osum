import os, re, sys

ROOT = sys.argv[1]
WCT = os.path.join(ROOT, "kernel/user/wlibc/wctheme.fi")
WLIBC = os.path.join(ROOT, "kernel/user/wlibc.fi")
OUT = os.path.join(ROOT, "kernel/user/uiicon.fi")


def rd(p):
    return open(p, encoding="latin1").read()


def wr(p, s):
    open(p, "w", encoding="latin1").write(s)


def split_fn(src, name):
    m = re.search(r"^fn %s\(" % name, src, re.M)
    if not m:
        raise SystemExit("missing fn " + name)
    start = m.start()
    end = src.index("\n}\n", start) + 3
    return start, end


def take(src, names):
    bodies = []
    for n in names:
        s, e = split_fn(src, n)
        bodies.append(src[s:e])
        tail = e
        while src[tail:tail + 1] == "\n":
            tail += 1
        src = src[:s] + src[tail:]
    return src, bodies


NAMES = ["icon_small", "icon_menu", "icon_taskbar", "icon_large", "icon_have", "icon_box", "icon_ink_w",
         "icon_ink_h", "icon_at", "icon_mid", "icon_mid_ink", "icon_role", "icon_ok", "icon_w", "icon_h",
         "icon_draw", "icon_draw_w", "icon_draw_h", "icon_ink_top", "icon_ink_hgt", "icon_ink_lft",
         "icon_ink_wid", "icon_draw_sc", "app_icon", "icon_vec", "icon_draw_fit"]

wct = rd(WCT)
wct, bodies = take(wct, NAMES)
for c in ("ICON_SMALL0", "ICON_MENU0", "ICON_TASKBAR0", "ICON_LARGE0"):
    wct = re.sub(r"const %s: u64 = \d+\n\n" % c, "", wct)
wr(WCT, wct)

text = "\n".join(bodies)
text = text.replace("wcbase.", "wcbase.").replace("theme(T_", "uitheme.theme(uitheme.T_")
for n in NAMES:
    text = re.sub(r"(?<![\w.])%s\(" % n, n + "(", text)

header = """// SPDX-License-Identifier: GPL-2.0-only
profile kernel

import appicon
import icons
import uiscale
import uitext
import uitheme
import wlibc.wcbase
import wlibc.wcpaint

export {
    %s,
}

const ICON_SMALL0: u64 = 16

const ICON_MENU0: u64 = 16

const ICON_TASKBAR0: u64 = 20

const ICON_LARGE0: u64 = 24

""" % ", ".join(NAMES)
wr(OUT, header + text)

wl = rd(WLIBC)
for n in NAMES:
    s, e = split_fn(wl, n)
    tail = e
    while wl[tail:tail + 1] == "\n":
        tail += 1
    wl = wl[:s] + wl[tail:]
    wl = re.sub(r"\b%s,\s*" % n, "", wl, count=1)
wl = re.sub(r"const ICON_ROLES: u64 = 5\n\n?", "", wl)
wl = re.sub(r"\bICON_ROLES,\s*", "", wl, count=1)
wr(WLIBC, wl)

pat = re.compile(r"\bwlibc\.(%s)\b" % "|".join(NAMES))
changed = []
for base, _, files in os.walk(os.path.join(ROOT, "kernel")):
    for f in files:
        if not f.endswith(".fi"):
            continue
        p = os.path.join(base, f)
        s = rd(p)
        if not pat.search(s):
            continue
        s = pat.sub(lambda m: "uiicon." + m.group(1), s)
        lines = s.split("\n")
        imports = [i for i, l in enumerate(lines) if l.startswith("import ")]
        at = next((i for i in imports if lines[i] > "import uiicon"), imports[-1] + 1)
        lines.insert(at, "import uiicon")
        rest = "\n".join(l for l in lines if not l.startswith("import "))
        if not re.search(r"\bwlibc\.", rest):
            lines = [l for l in lines if l != "import wlibc"]
        s = "\n".join(lines)
        wr(p, s)
        changed.append(os.path.relpath(p, ROOT))
print("\n".join(sorted(changed)))
