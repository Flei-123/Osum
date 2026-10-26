#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/startmenu/instcheck.py <stick-out> <disk-out> -- X5: "Install OrientOS" is offered on the stick and hidden
# on a disk that carries /etc/installed (appdir `hideif=`). The stick run is the counter-proof.
import re
import sys
import os

fails = 0


def serial(d):
    p = os.path.join(d, "serial.txt")
    return open(p, "rb").read().decode("latin1") if os.path.exists(p) else ""


def check(cond, msg):
    global fails
    print(("  OK    " if cond else "  FAIL  ") + msg)
    if not cond:
        fails += 1


stick = serial(sys.argv[1])
disk = serial(sys.argv[2])
check("launcher: " in stick and "launcher: " in disk, "both machines booted the start menu")
pat = r"launcher: treffer i=\d+ name=\[Install OrientOS\] exec="
check(re.search(pat, stick) is not None, "stick: the search 'install' finds Install OrientOS (counter-proof)")
check(re.search(pat, disk) is None, "installed disk (/etc/installed): the search finds no Install OrientOS")
pat_n = r"launcher: suche \[install\] treffer=\d+ apps=(\d+)"
m = re.findall(pat_n, stick)
check(bool(m) and int(m[-1]) >= 1, "stick: the search reports apps>=1 (%s)" % (m[-1] if m else "no report"))
m = re.findall(pat_n, disk)
# file hits (/bin/installer, /apps/installer.osp) stay: only the APP list must be empty
check(bool(m) and m[-1] == "0", "installed disk: the search reports apps=0 (%s)" % (m[-1] if m else "no report"))
src = open("kernel/user/instaccount.fi", encoding="latin1").read()
check('"/etc/installed' in src, "instaccount writes /etc/installed into the new system")
print("INSTCHECK: %d failed" % fails)
sys.exit(1 if fails else 0)
