#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

PAD = 16
ROW_H = 48
ROW_GAP = 4
HEAD_H = 32
PANEL_W = 368
CHEV_MIN = 16


def snapshots(lines):
    snaps = []
    for l in lines:
        m = re.match(r"qsnet: page h=(\d+)", l)
        if m:
            snaps.append({"h": int(m.group(1)), "box": {}})
            continue
        m = re.match(r"qsnet: box k=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", l)
        if m and snaps:
            k, x, y, w, h = (int(v) for v in m.groups())
            snaps[-1]["box"][k] = (x, y, w, h)
    return snaps


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin1")
    sc = int(sys.argv[2])
    out = []

    def ok(c, msg):
        out.append(("OK    " if c else "FAIL  ") + msg)

    snaps = [s for s in snapshots(serial.splitlines()) if 50 in s["box"] and 41 not in s["box"]]
    if not snaps:
        ok(False, "no network page snapshot with Wi-Fi rows")
        print("\n".join(out))
        return 1
    s = snaps[0]
    b = s["box"]
    ph = s["h"]
    ok(40 in b, "header: the back button is on the page")
    if 40 in b:
        x, y, w, h = b[40]
        ok(x == PAD * sc and y == PAD * sc, "header: back button at the padding corner (%d,%d)" % (x, y))
        ok(h == HEAD_H * sc, "header: back button is %d px high (%d points)" % (h, HEAD_H))
    ok(55 in b, "header: the Wi-Fi switch is on the page")
    if 55 in b:
        x, y, w, h = b[55]
        ok(x + w == (PANEL_W - PAD) * sc, "header: the Wi-Fi switch ends at the right padding edge (%d)" % (x + w))
        ok(y == PAD * sc, "header: the switch shares the header row (y %d)" % y)
    rows = sorted((k for k in b if 50 <= k < 54))
    ok(len(rows) >= 1, "%d network rows listed" % len(rows))
    for k in rows:
        x, y, w, h = b[k]
        ok(h == ROW_H * sc, "row %d: %d px high (%d points)" % (k, h, ROW_H))
        ok(w == (PANEL_W - 2 * PAD) * sc, "row %d: full inner width %d px" % (k, w))
    for a, c in zip(rows, rows[1:]):
        gap = b[c][1] - (b[a][1] + b[a][3])
        ok(gap == ROW_GAP * sc, "rows %d/%d: gap %d px (%d points)" % (a, c, gap, ROW_GAP))
    ok(49 in b and 43 in b, "footer: refresh button and more-settings link are on the page")
    if 49 in b:
        x, y, w, h = b[49]
        ok(x + w == (PANEL_W - PAD) * sc, "footer: refresh ends at the right padding edge (%d)" % (x + w))
        ok(abs(y + h + PAD * sc - ph) <= 2 * sc,
           "page height %d equals footer bottom %d plus padding (no empty space below the list)" % (ph, y + h))
        last = max((b[k][1] + b[k][3] for k in rows), default=0)
        ok(y > last, "footer starts below the last row (%d > %d)" % (y, last))
    if 43 in b:
        ok(b[43][0] >= PAD * sc, "footer: the link starts inside the padding (x %d)" % b[43][0])
    print("\n".join(out))
    return 0 if all(o.startswith("OK") for o in out) else 1


sys.exit(main())
