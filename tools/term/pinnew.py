#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""pinnew.py <serial.txt>: judge tools/term/pinnew.sh (r529 pin opens more terminals, r530 error window).

Checks: the pin starts the terminal once on the first left click, a second left click only switches (no new start), the middle
click starts one more, the context menu "New window" starts another; every start gives a real window with its own tty;
/bin/termfull shows its window. Exit code 0 = all good."""
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from multi import snapshots, holders   # noqa: E402


def main(path):
    txt = open(path, "rb").read().decode("latin1")
    sn = snapshots(path)
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    starts = re.findall(r"taskbar: pin starte (/apps/terminal\.osp/start) pid=(\d+)", txt)
    check(len(starts) == 3,
          "pin starts: first click, middle click, menu item = 3 starts (saw %d)" % len(starts))
    sw = re.findall(r"taskbar: pin schalte terminal", txt)
    check(len(sw) >= 1, "the second left click only switched the window (%d switch line(s))" % len(sw))
    check(len(sw) >= 1 and len(starts) == 3, "the switch did not start another terminal (3 starts in all)")
    check("taskbar: pin neu starte" in txt, "the context menu item 'New window' was taken")
    last = sn[-1] if sn else {}
    peak = max((len(x) for x in sn), default=0)
    check(peak >= 4, "console + three pin windows at once: saw %d" % peak)
    if sn:
        top = [x for x in sn if len(x) == peak][-1]
        ttys = [w["tty"] for w in top.values()]
        check(len(set(ttys)) == len(ttys), "every window has its own tty: %s" % sorted(ttys))
        for mk in ("pin-one", "pin-two", "pin-three"):
            h = holders(top, mk)
            check(len(h) == 1, "marker %s stands in exactly one window: %s" % (mk, h))
    check("termfull: window shown" in txt, "/bin/termfull opened its window")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
