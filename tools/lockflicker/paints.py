#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/paints.py <run dir> <max_pictures_after_click|-1> <max_median_ms|-1>

Counts the pictures fUi painted AFTER the step `click` (drive.py `schritt click` writes the serial byte offset to schritte.tsv).
Needs /etc/paintlog in the guest: one serial line `fui: paint n=<count> ms=<time of the picture> chg=<words that differ from the shown buffer>` per picture, `fui: down n=<count>` per button press.
Prints `PAINTS after_click=K median_ms=M max_ms=X total=T` and exits 1 when the SHOWN pictures (chg > 0) or the median is above its limit (-1 = no limit), 2 = no data.
"""
import os, re, statistics, sys

def main():
    run, kmax, msmax = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    off = None
    try:
        for l in open(os.path.join(run, "schritte.tsv"), encoding="utf-8"):
            f = l.rstrip("\n").split("\t")
            if len(f) >= 3 and f[2] == "click":
                off = int(f[0])
    except OSError:
        pass
    data = open(os.path.join(run, "serial.txt"), "rb").read()
    if off is None:
        print("PAINTS no step 'click'")
        return 2
    pat = re.compile(rb"fui: paint n=(\d+) ms=(\d+) chg=(\d+)")
    allp = pat.findall(data)
    after = pat.findall(data[off:])
    if not allp:
        print("PAINTS no paint lines (/etc/paintlog missing?)")
        return 2
    shown = [c for _, _, c in after if int(c) > 0]   # pictures that really changed what the window server shows
    allms = [int(m) for _, m, _ in allp]
    med = int(statistics.median(allms[2:] or allms))
    print("PAINTS after_click=%d shown=%d median_ms=%d max_ms=%d total=%d" % (len(after), len(shown), med, max(allms), len(allp)))
    bad = (kmax >= 0 and len(shown) > kmax) or (msmax >= 0 and med > msmax)
    return 1 if bad else 0

sys.exit(main())
