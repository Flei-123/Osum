#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import re
import sys

from PIL import Image

PAGE = 35
ROUTE = "settings://privacy/remote-desktop"
ROUTES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kernel", "user", "settings.d", "settings.routes")
CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
RECT = re.compile(r"^settings: rect name=xrsw x=(\d+) y=(\d+) w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", re.M)
REMOTE = re.compile(r"^settings: remote page enabled=(\w+) service=(\S*) id=(\S*) peer=(\S*)$", re.M)
NAV = re.compile(r"^settings: nav route=" + re.escape(ROUTE) + r" page=(\d+)", re.M)
MIN_COLORS = 4
MIN_DIFF_PIXELS = 40


def declared_controls():
    text = open(ROUTES_FILE, encoding="utf-8").read()
    block = text.split("route " + ROUTE + " ", 1)[1].split("\nroute ", 1)[0]
    return int(re.search(r"^controls (\d+)$", block, re.M).group(1))


def shot(run_dir, name):
    found = sorted(glob.glob(os.path.join(run_dir, "*" + name + "*.png")))
    return Image.open(found[0]).convert("RGB") if found else None


def colors_in(img, box):
    return len(set(img.crop(box).getdata()))


def diff_pixels(a, b):
    if a is None or b is None or a.size != b.size:
        return 0
    return sum(1 for p, q in zip(a.getdata(), b.getdata()) if p != q)


def judge(serial_text, before, after, declared):
    res = []

    def ok(cond, msg):
        res.append((bool(cond), msg))

    nav = NAV.search(serial_text)
    ok(nav and int(nav.group(1)) == PAGE, "route %s opens page %d" % (ROUTE, PAGE))
    ctl = [int(m.group(2)) for m in CTL.finditer(serial_text) if int(m.group(1)) == PAGE]
    ok(ctl, "page %d reports its controls" % PAGE)
    ok(ctl and max(ctl) == declared, "controls %s equal the route table (%d)" % (ctl, declared))
    rect = RECT.search(serial_text)
    ok(rect, "rect xrsw reported")
    ok(REMOTE.search(serial_text), "page state line reported")
    ok(not re.search(r"CRASH|EXCEPTION", serial_text), "no crash lines")
    ok(before is not None, "screenshot 01-remote exists")
    ok(after is not None, "screenshot 02-remote-clicked exists")
    if rect and before is not None:
        ax, ay, w, h = (int(rect.group(i)) for i in (5, 6, 3, 4))
        box = (ax, ay, min(ax + w, before.size[0]), min(ay + h, before.size[1]))
        ok(w > 0 and h > 0 and box[2] > box[0] and box[3] > box[1], "switch rect inside the picture (%s)" % (box,))
        ok(colors_in(before, box) >= MIN_COLORS, "switch rect has drawn pixels (%d colors)" % colors_in(before, box))
    ok(diff_pixels(before, after) >= MIN_DIFF_PIXELS, "clicking the switch changes the picture (%d pixels)" % diff_pixels(before, after))
    return res


def doctored_cases(serial_text, before):
    blank = Image.new("RGB", before.size, (0, 0, 0)) if before is not None else None
    return {
        "no rect line": re.sub(r"settings: rect name=xrsw ", "settings: rect name=zzzz ", serial_text),
        "wrong controls": CTL.sub(lambda m: "settings: controls page=%s n=99" % m.group(1), serial_text),
        "no state line": "\n".join(l for l in serial_text.splitlines() if not l.startswith("settings: remote page")),
        "wrong page": NAV.sub("settings: nav route=" + ROUTE + " page=1", serial_text),
        "crash line": serial_text + "\nCRASH\n",
    }, blank


def main():
    serial_path, run_dir = sys.argv[1], sys.argv[2]
    serial_text = open(serial_path, "rb").read().decode("latin1")
    before = shot(run_dir, "01-remote")
    after = shot(run_dir, "02-remote-clicked")
    declared = declared_controls()
    res = judge(serial_text, before, after, declared)
    for good, msg in res:
        print("  %s  %s" % ("OK  " if good else "FAIL", msg))
    bad = sum(1 for good, _ in res if not good)
    passed = len(res) - bad
    cases, blank = doctored_cases(serial_text, before)
    for name, doctored in cases.items():
        if all(good for good, _ in judge(doctored, before, after, declared)):
            print("  FAIL  counter-proof not red: %s" % name)
            bad += 1
        else:
            print("  OK    counter-proof red: %s" % name)
            passed += 1
    if blank is not None:
        if all(good for good, _ in judge(serial_text, blank, blank, declared)):
            print("  FAIL  counter-proof not red: blank picture")
            bad += 1
        else:
            print("  OK    counter-proof red: blank picture")
            passed += 1
    print("SETTINGSREMOTE: %d passed, %d failed" % (passed, bad))
    sys.exit(1 if bad else 0)


main()
