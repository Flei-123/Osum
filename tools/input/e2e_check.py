#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus_kernel

EVENT = re.compile(r"^touchdemo: ev t=(\d+) slot=(\d+) dev=(\d+) fl=(\d+) x=(\d+) y=(\d+) px=(\d+) py=(\d+) p=(\d+) a=(-?\d+) b=(-?\d+)$")
SUMMARY = re.compile(r"^touchdemo: events=(\d+) dropped=(\d+) gestures=(\d+)$")
T_GESTURE = 4
G_TAP = 1


def main(path):
    runs = [[]]
    sums = []
    with open(path, "rb") as f:
        for raw in f:
            text = raw.decode("latin-1").strip()
            m = EVENT.match(text)
            if m:
                runs[-1].append(tuple(int(v) for v in m.groups()))
                continue
            m = SUMMARY.match(text)
            if m:
                sums.append(tuple(int(v) for v in m.groups()))
                runs.append([])
    ok = 0
    bad = 0

    def check(label, cond):
        nonlocal ok, bad
        if cond:
            ok += 1
            print("OK   " + label)
        else:
            bad += 1
            print("FAIL " + label)

    check("the demo app ran twice and printed two summaries", len(sums) == 2)
    if len(sums) < 2:
        print("e2e check: %d ok, %d fail" % (ok, bad))
        return 1
    first = runs[0]
    raw = [e for e in first if e[0] != T_GESTURE]
    gest = [e for e in first if e[0] == T_GESTURE]
    want = [l for _, l in corpus_kernel.expected_lines(0, "touchscreen-045e-0c32")]
    got = ["touchev: %d slot=%d dev=%d fl=%d x=%d y=%d px=%d py=%d p=%d" % (e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]) for e in raw]
    check("raw events read through the API equal the independent expectation (%d)" % len(want), want == got)
    if want != got:
        for i in range(max(len(want), len(got))):
            print("   want %s" % (want[i] if i < len(want) else "-"))
            print("   got  %s" % (got[i] if i < len(got) else "-"))
    check("summary counts every record", sums[0][0] == len(first))
    check("nothing was dropped", sums[0][1] == 0)
    check("the touch screen tap arrived as a gesture record", any(e[3] == G_TAP for e in gest))
    check("summary counts the gestures", sums[0][2] == len(gest))
    check("a second read finds the ring drained", sums[1][0] == 0 and not runs[1])
    print("e2e check: %d ok, %d fail" % (ok, bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
