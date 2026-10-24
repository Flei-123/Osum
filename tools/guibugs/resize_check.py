#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

serial = open(sys.argv[1], "rb").read().decode("latin1")
steps = int(sys.argv[3])
passed = 0
failed = 0


def check(cond, text):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + text)
    else:
        failed += 1
        print("  FAIL  " + text)


faults = re.findall(r"^(?:user fault:.*|panic:.*|.*KERNEL PANIC.*)$", serial, re.M)
check(not faults, "no user fault or panic during %d resizes%s" % (steps, "" if not faults else ": " + faults[0][:120]))
lists = serial.split("wm: fenliste")
check(len(lists) - 1 >= steps, "window list printed after every resize (%d of %d)" % (len(lists) - 1, steps))
last = lists[-1] if lists else ""
alive = re.search(r"wm: fen i=\d+ id=19 ", last) is not None
check(alive, "settings window still listed after the last resize")
sizes = set(re.findall(r"wm: fen i=\d+ id=19 x=-?\d+ y=-?\d+ w=(\d+) h=(\d+)", serial))
check(len(sizes) >= max(3, steps // 2), "the window really took %d different sizes" % len(sizes))
print("RESIZE: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
