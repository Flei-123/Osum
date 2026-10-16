#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""editwin.py <serial.txt>: judge tools/term/editwin.sh (r543, Editor merge 16.10.2026). Uses the per-window dumps (`wm: termwin`, `wm: tw<slot> <row> [text]`).
Photos 01..05 are the snapshots in order. Exit code 0 = all good."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from multi import snapshots, holders


def has(w, text):
    return any(text in t for t in w["rows"].values())


def main(path):
    sn = snapshots(path)
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    print("%d snapshot(s)" % len(sn))

    def first(pred):
        for x in sn:
            if pred(x):
                return x
        return None
    boot = first(lambda x: holders(x, "boot-a"))
    term = first(lambda x: holders(x, "term-b"))
    check(boot is not None and len(boot) == 1, "boot terminal: one window, it shows boot-a")
    check(term is not None, "the line typed into the new Terminal (`term-b`) stands in some window")
    if not (boot and term):
        return 1
    # the merged Editor (a window program) must not add a terminal window; the Terminal adds exactly one
    check(len(term) == len(boot) + 1,
          "Editor added no terminal window, Terminal added one (%d -> %d)" % (len(boot), len(term)))
    h = holders(term, "term-b")
    check(len(h) == 1 and h[0] not in boot, "the new Terminal window took the typed line: %s" % h)
    txt = open(path, "rb").read().decode("latin1")
    check("launcher: start /apps/editor.osp/start" in txt, "Editor was started from the menu (launcher line on the serial)")
    check("launcher: start /apps/nedit.osp/start" not in txt, "no separate Editor+ entry any more")
    check("launcher: start /apps/terminal.osp/start" in txt, "Terminal was started from the menu (launcher line on the serial)")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
