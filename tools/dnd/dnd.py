#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/dnd/dnd.py -- judge the serial line of tools/dnd/run.sh (W-DND: drag hover-raise, Esc cancel, path drop on terminal).

Witnesses in order: wm: dndcancel (Esc phase) -> taskbar: dndraise id=N rc= (taskbar phase) -> wm: dndraise id=N (hover raise)
-> wm: dndterm tty=T (drop on the terminal). The no-payload drag before the Esc phase must produce NOTHING."""
import re
import sys

W = re.compile(r"(wm: dndraise id=\d+|wm: dndcancel|wm: dndterm tty=\d+|wm: dndsrc id=\d+|taskbar: dndraise id=\d+)")


def main(path):
    txt = open(path, "rb").read().decode("latin1")
    ev = []
    for z in txt.split("\n"):
        for m in W.finditer(z):
            ev.append(m.group(1))
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1

    print("        witnesses: %s" % ev)
    kinds = [e.split(" id=")[0].split(" tty=")[0] for e in ev]
    check(kinds[:1] == ["wm: dndcancel"], "first witness is the Esc cancel (no-payload drag and the Esc drag raised/dropped nothing)")
    check(kinds.count("wm: dndcancel") == 1, "exactly one dndcancel")
    check(kinds.count("taskbar: dndraise") == 1, "taskbar hover-raise fired once")
    check(kinds.count("wm: dndraise") == 1, "window hover-raise fired once")
    check(kinds.count("wm: dndterm") == 1, "path dropped on the terminal once")
    order = [k for k in kinds if k != "wm: dndsrc"]
    check(kinds[-2:] == ["wm: dndsrc", "wm: dndterm"], "the drag source is told about the release outside its window (drag chip goes away)")
    want = ["wm: dndcancel", "taskbar: dndraise", "wm: dndraise", "wm: dndterm"]
    check(order == want, "order is cancel -> taskbar raise -> wm raise -> terminal drop")
    print("DND: %s" % ("FAIL %d" % bad if bad else "OK"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
