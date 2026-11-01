#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

LINE = re.compile(r"wlib: text win=(\d+) kind=(\d+) x=(-?\d+) base=(-?\d+) fg=\d+ bg=\d+ tw=(\d+) ax=(-?\d+) ay=(-?\d+)"
                  r"(?: ow=(\d+) bw=(\d+))? t=(.*)")
PASS = FAIL = 0


def check(c, m):
    global PASS, FAIL
    if c:
        PASS += 1
    else:
        FAIL += 1
    print(("  OK    " if c else "  FAIL  ") + m)


def is_data(t):
    return bool(re.search(r"[/\\]|\.[A-Za-z0-9]{1,4}$|\d{3,}", t))


WORK = re.compile(r"wm: work x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)")


def scan(text):
    seen = 0
    cut = {}
    for m in LINE.finditer(text):
        seen += 1
        if m.group(8) is None:
            continue
        win, kind, ow, bw, t = int(m.group(1)), int(m.group(2)), int(m.group(8)), int(m.group(9)), m.group(10).strip()
        cut[(win, kind, t)] = (ow, bw)
    return seen, cut


def run_dir(out, tag):
    p = os.path.join(out, "serial.txt")
    if not os.path.exists(p):
        check(False, "%s: no serial.txt in %s" % (tag, out))
        return
    t = open(p, "rb").read().decode("utf-8", "replace")
    seen, cut = scan(t)
    check(seen >= 40, "%s: %d text lines reported (>= 40: the trace is on)" % (tag, seen))
    works = WORK.findall(t)
    sw = int(works[-1][2]) if works else 0
    off = {}
    for m in LINE.finditer(t):
        sx = int(m.group(3)) + int(m.group(6))
        if sw and sx + int(m.group(5)) > sw + 1 and sx < sw:
            off[m.group(10).strip()] = (sx + int(m.group(5)), sw)
    for tx, (right, w) in sorted(off.items()):
        check(False, "%s: text runs past the screen edge (right end %d > screen %d): '%s'" % (tag, right, w, tx))
    check(not off, "%s: no text runs past the screen edge" % tag)
    chrome = {k: v for k, v in cut.items() if not is_data(k[2])}
    data = {k: v for k, v in cut.items() if is_data(k[2])}
    for (win, kind, tx), (ow, bw) in sorted(data.items()):
        print("  note  %s: data text shortened (allowed) win=%d kind=%d ow=%d bw=%d '%s'" % (tag, win, kind, ow, bw, tx))
    for (win, kind, tx), (ow, bw) in sorted(chrome.items()):
        check(False, "%s: chrome text shortened win=%d kind=%d ow=%d > room %d: '%s'" % (tag, win, kind, ow, bw, tx))
    check(not chrome, "%s: no fixed text is shortened (%d data texts may be)" % (tag, len(data)))


def selftest():
    good = "wlib: text win=3 kind=2 x=10 base=20 fg=1 bg=2 tw=50 ax=0 ay=0 t=Apply\n" * 50
    bad = good + "wlib: text win=3 kind=2 x=10 base=20 fg=1 bg=2 tw=50 ax=0 ay=0 ow=90 bw=50 t=Uebernehmen\n"
    data = good + "wlib: text win=3 kind=1 x=10 base=20 fg=1 bg=2 tw=50 ax=0 ay=0 ow=300 bw=50 t=/home/user/a/very/long/path.txt\n"
    s, c = scan(good)
    check(s == 50 and not c, "selftest: a clean log has no shortened text")
    s, c = scan(bad)
    check(len({k for k in c if not is_data(k[2])}) == 1, "selftest: a shortened button word is found (the gate would FAIL)")
    s, c = scan(data)
    check(len(c) == 1 and all(is_data(k[2]) for k in c), "selftest: a shortened path is a data text (allowed)")


def main(argv):
    if argv and argv[0] == "--selftest":
        selftest()
    else:
        for a in argv:
            run_dir(a, os.path.basename(a.rstrip("/")))
    print("%d OK / %d FAIL" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
