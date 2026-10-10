#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/term/esc.py -- judge the serial line of tools/term/esc.sh (r537: ESC in front of a command)."""
import re
import sys


def main(path):
    txt = open(path, "rb").read().decode("latin1")
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    lines = [re.sub(r"^osum\$ ", "", z.rstrip("\r")) for z in txt.split("\n")]
    for mk in ("esc-a", "esc-b", "esc-c"):
        n = sum(1 for z in lines if z.strip() == mk)
        check(n == 1, "`echo %s` after the key ran and printed its argument once: %d" % (mk, n))
    cr = [z for z in lines if "cannot run" in z]
    check(not cr, "no `sh: cannot run`: %s" % (cr[:3] or "none"))
    check(any("passwd" in z.split() for z in lines), "`ls /etc` ran (lists passwd)")
    esc_in_name = [z for z in lines if "/bin/\x1b" in z]
    check(not esc_in_name, "no command name carries an ESC byte")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
