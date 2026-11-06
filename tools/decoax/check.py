#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

serial = open(sys.argv[1], "rb").read().decode("latin1")
passed = 0
failed = 0

WIN = re.compile(r"decodemo: win x=(\d+) y=(\d+) inx=(\d+) iny=(\d+)")
TEXT = re.compile(r"wlib: text win=\d+ kind=\d+ x=\d+ base=\d+ fg=\d+ bg=\d+ tw=\d+ ax=(\d+) ay=(\d+) t=Frame check")


def check(cond, text):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + text)
    else:
        failed += 1
        print("  FAIL  " + text)


def segment(start, end):
    a = serial.find("\n" + start + "\n")
    if a < 0:
        return ""
    b = serial.find("\n" + end + "\n", a + 1)
    return serial[a:b if b >= 0 else len(serial)]


def verify(name, body, want_frame):
    win = WIN.findall(body)
    texts = TEXT.findall(body)
    check(bool(win), name + ": window geometry reported")
    check(bool(texts), name + ": text trace with ax/ay present")
    if not win or not texts:
        return
    x, y, inx, iny = (int(v) for v in win[-1])
    ax, ay = (int(v) for v in texts[-1])
    check((inx > 0 and iny > 0) == want_frame, name + ": frame inset %d/%d as expected" % (inx, iny))
    if want_frame:
        check((ax, ay) == (x + inx, y + iny), name + ": text ax/ay %d/%d == window %d/%d + inset %d/%d" % (ax, ay, x, y, inx, iny))
    else:
        check((ax, ay) == (x, y), name + ": text ax/ay %d/%d == window %d/%d" % (ax, ay, x, y))


verify("framed", segment("decodemo: ready", "decodemo: bare"), True)
verify("frameless", segment("decodemo: bare", "decodemo: done"), False)
print("\nDECOAX: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
