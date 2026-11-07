#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import statistics
import sys

out = sys.argv[1]
counter = len(sys.argv) > 2 and sys.argv[2] == "stall"
EXPECTED_CLICKS = 4
MAX_LATENCY_MS = 800
ok = fail = 0


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


log = open(os.path.join(out, "fahren.log"), "rb").read().decode("latin1")
latencies = [(m.group(1), int(m.group(2))) for m in re.finditer(r"klickmess (\w+) -> (\d+) ms", log)]
missing = len(re.findall(r"klickmess .* -> (?:NOT THERE|NO RECT)", log))
values = [v for _, v in latencies]
worst = max(values, default=-1)
detail = ", ".join("%s %d" % (n, v) for n, v in latencies)
if counter:
    say(len(values) == EXPECTED_CLICKS, "COUNTER-PROOF (-w 2000): all %d clicks still landed" % EXPECTED_CLICKS)
    say(worst > MAX_LATENCY_MS, "COUNTER-PROOF: a loop blocked for 2 s per round breaks the %d ms bound (worst %d ms; %s)" % (MAX_LATENCY_MS, worst, detail))
else:
    say(len(values) == EXPECTED_CLICKS and missing == 0, "all %d clicks while playing landed (pause, resume, +1 s, slider)" % EXPECTED_CLICKS)
    say(values and worst <= MAX_LATENCY_MS, "click to effect while playing: worst %d ms, median %d ms (limit %d; %s)" % (worst, statistics.median(values) if values else -1, MAX_LATENCY_MS, detail))
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
