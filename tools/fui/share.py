#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fui/share.py [<repo root>] -- how much of Osum's GUI is a fUi scene tree (measured, not estimated).

Prints one line per GUI part: source lines, how the window is built, the number of fuiscene calls and of direct pixel painting calls.
Classes: SCENE = window is `fuiscene.open*`; PARTIAL = scene host plus an own painting routine; OWN = own painting only (fUi painter or
wlibc/fb primitives); KERNEL = painted by the kernel window server / text grid. The last line is the share of lines on a scene tree
(programs with a window, `kernel/user`), the number that docs/FUI-ALL.md section 11 calls "fUi-Szenenbaum-Anteil".
"""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
U = os.path.join(root, "kernel", "user")

def src(p):
    with open(os.path.join(root, p), "rb") as f:
        return f.read().decode("utf-8", "replace")

def count(text, pat):
    return len(re.findall(pat, text))

def fn_lines(text, name_re):
    # lines of every top-level `fn` whose name matches name_re (a function runs to the next top-level `fn` or the file's end)
    lines = text.split("\n")
    starts = [i for i, l in enumerate(lines) if re.match(r"fn \w+", l)]
    total = 0
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(lines)
        if re.match(r"fn (%s)\b" % name_re, lines[s]):
            total += e - s
    return total

# part, files, class override (None = decide from the source)
PARTS = [
    ("sign-in screen", ["glogin", "signin"], None),
    ("lock screen", ["lock", "lockclaim", "idlelock"], None),
    ("task bar", ["taskbar"], "PARTIAL"),
    ("start menu", ["launcher"], None),
    ("file manager", ["explorer"], None),
    ("settings", ["settings", "settingsd"], None),
    ("installer", ["installer"], None),
    ("store", ["store", "bstore", "stored"], None),
    ("task manager", ["taskmgr", "taskview"], None),
    ("snip / paint", ["snip"], None),
    ("PDF viewer", ["pdfview"], None),
    ("text viewer / editor", ["viewer", "nedit"], None),
    ("quick settings", ["qs"], None),
    ("tooltip + toast", ["barpop"], None),
    ("desktop", ["desktop"], None),
    ("calculator", ["calc"], None),
    ("other small (netmon, powermon, storage/disks, friends, trash, certus, demos)", ["netmon", "powermon", "storage", "disks", "freunde", "trashbin", "certus", "a11ydemo", "themetest", "scenedemo", "termfull"], None),
    ("widget demo (K15 anchor)", ["widgetdemo"], None),
]
OWN_WINDOW = {"taskbar", "desktop", "widgetdemo"}   # programs with a window that is not a scene tree
rows = []
scene_lines = 0
all_lines = 0
nowin = {}
for name, files, force in PARTS:
    n = fu = wc = 0
    cls_set = set()
    for f in files:
        p = "kernel/user/%s.fi" % f
        if not os.path.exists(os.path.join(root, p)):
            continue
        t = src(p)
        ln = t.count("\n") + 1
        opens = count(t, r"fuiscene\.(open|open_plain|win_open_plain)\b")
        if f not in OWN_WINDOW and opens == 0:
            nowin[f] = ln          # a daemon / helper / backend: no window of its own, left out of the share
            continue
        n += ln
        fu += count(t, r"fuiscene\.")
        wc += count(t, r"wlibc\.(px|rect|rrect|text_at|hline|vline|frame|blit)\w*\(|\bfb\.(fill|pixel|text)\w*\(")
        cls_set.add("OWN" if f in OWN_WINDOW else "SCENE")
    if not n:
        continue
    cls = force or ("SCENE" if cls_set == {"SCENE"} else "OWN")
    if name.startswith("widget demo"):
        cls = "WLIB-WIDGETS"
    rows.append((name, n, cls, fu, wc))
    all_lines += n
    if cls == "SCENE":
        scene_lines += n
tb = src("kernel/user/taskbar.fi")
tb_tree = fn_lines(tb, r"\w*(build|tree|ghost|bar_scene)\w*")
tb_paint = fn_lines(tb, r"\w*paint\w*")
print("%-72s %7s  %-12s %8s %12s" % ("part", "lines", "class", "fuiscene", "direct-paint"))
for r in rows:
    print("%-72s %7d  %-12s %8d %12d" % r)
print("task bar: lines in tree-building functions %d, in paint* functions %d, of %d" % (tb_tree, tb_paint, tb.count("\n") + 1))
fs = src("kernel/user/fuiscene.fi")
print("fuiscene.fi (the host itself) %d lines; own popup/dialog/tooltip painting inside it: %d lines (pop_paint/dlg_paint/tip_paint)" % (fs.count("\n") + 1, fn_lines(fs, r"pop_paint|dlg_paint|tip_paint")))
wm = src("kernel/ui/wm.fi")
print("kernel/ui/wm.fi (window server: frame, title bar, terminal grid) %d lines; not a scene tree" % (wm.count("\n") + 1))
scene_lines += tb_tree   # task bar: only the functions that build its tree (the rest paints by itself)
print("files without a window of their own, left out: " + ", ".join("%s %d" % kv for kv in sorted(nowin.items())))
print("SHARE scene-tree lines %d of %d GUI-program lines = %.1f %%" % (scene_lines, all_lines, 100.0 * scene_lines / all_lines))
