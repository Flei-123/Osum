#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    check.py <soll-file> <serielle-output> [...weitere Ausgaben]
"""

import re
import sys

PROBE = re.compile(
    r"du: probe path=(\S+)\s+idx=(\d+)\s+walk=(\d+)\s+idxkb=(\d+)\s+"
    r"walkkb=(\d+)\s+ok=(\d+)")
DONE = re.compile(r"du: probe done checked=(\d+)\s+wrong=(\d+)")
MEASURE = re.compile(r"du: (index|walk) \[(\S+)\] okt=(\d+) kb=(\d+)")


def soll_read(path_2):
    aus = {}
    with open(path_2) as f:
        for line in f:
            t = line.split()
            if len(t) >= 3:
                aus[t[0]] = (int(t[1]), int(t[2]))
    return aus


def text(path_2):
    with open(path_2, "rb") as f:
        return f.read().decode("latin-1")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    soll = soll_read(argv[1])
    roh = "\n".join(text(p) for p in argv[2:])

    geprueft = 0
    wrong = 0
    without_soll = 0
    dritt = 0
    rows = []

    for m in PROBE.finditer(roh):
        path_2, idx, run_2, ikb, lkb, ok = m.group(1), int(m.group(2)), \
            int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6))
        geprueft += 1
        gut = idx == run_2 and ikb == lkb and ok == 1
        s = soll.get(path_2)
        anmerkung = ""
        if path_2 == "/":
            anmerkung = "(root: index against walk only, see header)"
            without_soll += 1
        elif s is None:
            anmerkung = "(no expected value)"
            without_soll += 1
        else:
            dritt += 1
            if idx != s[0] or ikb != s[1]:
                gut = False
                anmerkung = "HOST SAYS okt=%d kb=%d" % s
        if not gut:
            wrong += 1
        rows.append("  %-24s idx=%-8d walk=%-8d kb=%-6d %s %s"
                      % (path_2, idx, run_2, ikb, "OK " if gut else "WRONG",
                         anmerkung))

    print("check: %d directories from the guest, of which %d also against the "
          "arithmetic of the host" % (geprueft, dritt))
    for z in rows:
        print(z)

    for m in DONE.finditer(roh):
        g, f = int(m.group(1)), int(m.group(2))
        print("check: the guest says checked=%d wrong=%d" % (g, f))
        if f != 0:
            wrong += f
        if g != geprueft:
            print("check: NOTE -- the guest counts %d probes, here "
                  "arrive: %d" % (g, geprueft))
            wrong += 1

    if geprueft == 0:
        print("check: NOT A SINGLE PROBE in the output -- the run is "
              "did not get through")
        return 1
    if dritt == 0:
        print("check: no probe against the host -- the expected values fit "
              "to no path")
        return 1
    if wrong:
        print("check: %d WRONG" % wrong)
        return 1
    print("check: all %d directories identical octet for octet "
          "(index = walk = host)" % geprueft)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
