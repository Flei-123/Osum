#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/taskgrp/drive.py -- taskbar grouping: open two Explorer windows + Settings, read the last taskbar repaint.

    drive.py <qmp-socket> <monitor-socket> <serial.txt> <outdir>

Writes scenes.txt: buttons=<count of `taskbar: btn` lines of the last repaint>, grp_max=<largest `taskbar: grp n=`>,
grp_lines=<number of grp lines in that repaint>.
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "alttab"))
from drive import Qmp, serial_text, wait_for  # noqa: E402


def last_repaint(text):
    idx = [m.start() for m in re.finditer(r"taskbar: btn i=0 ", text)]
    if not idx:
        return ""
    return text[idx[-1]:]


def main():
    qmp_path, mon, ser, out = sys.argv[1:5]
    q = Qmp(qmp_path)
    facts = []
    wait_for(ser, r"eingabe: ber=", 0, 90)
    time.sleep(1.0)
    q.tap("shift")
    time.sleep(1.0)
    for combo, pat in ((("meta_l", "e"), r"taskbar: hk start /apps/explorer\.osp/start"),
                       (("meta_l", "e"), r"taskbar: hk start /apps/explorer\.osp/start"),
                       (("meta_l", "i"), r"taskbar: hk start /apps/settings\.osp/start")):
        before = len(re.findall(r"wm: fokus", serial_text(ser)))
        q.tap(*combo)
        end = time.time() + 40
        while time.time() < end and len(re.findall(r"wm: fokus", serial_text(ser))) <= before:
            time.sleep(0.2)
        time.sleep(2.0)
    time.sleep(3.0)
    rep = last_repaint(serial_text(ser))
    # one repaint = btn lines with rising i; cut at the second `i=0`
    parts = re.split(r"(?=taskbar: btn i=0 )", rep)
    rep = parts[1] if len(parts) > 2 else rep
    btns = re.findall(r"taskbar: btn i=(\d+) ", rep)
    grps = [int(x) for x in re.findall(r"taskbar: grp i=\d+ n=(\d+)", rep)]
    facts.append(f"buttons={len(btns)}")
    facts.append(f"grp_lines={len(grps)}")
    facts.append(f"grp_max={max(grps) if grps else 0}")
    open(out + "/scenes.txt", "w").write("\n".join(facts) + "\n")
    print("\n".join(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
