#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""report.py <old-results> <new-results> -- one markdown table: every check, its verdict on the kernel of main (before this round)
and on this tree, and the detail of the new run when it is not a PASS.

  python3 tools/unterbau/report.py /tmp/ub-main-results.txt /tmp/ub-new-results.txt > table.md
A results file holds lines `<test>.<check> PASS|FAIL|GAP <detail>` (what run.sh writes with UB_RESULT=...)."""
import sys, collections

def load(p):
    d = collections.OrderedDict()
    for l in open(p, errors="replace"):
        parts = l.rstrip("\n").split(" ", 2)
        if len(parts) >= 2 and "." in parts[0] and parts[1] in ("PASS", "FAIL", "GAP"):
            d.setdefault(parts[0], (parts[1], parts[2] if len(parts) > 2 else ""))
    return d

old, new = load(sys.argv[1]), load(sys.argv[2])
names = list(new.keys()) + [k for k in old if k not in new]
tests = collections.OrderedDict()
for n in names:
    tests.setdefault(n.split(".")[0], []).append(n)
sym = {"PASS": "ok", "FAIL": "FAIL", "GAP": "GAP", None: "-"}
tot = collections.Counter()
for t, ns in tests.items():
    c_old = collections.Counter(old.get(n, (None,))[0] for n in ns)
    c_new = collections.Counter(new.get(n, (None,))[0] for n in ns)
    tot.update(v for v in (new.get(n, (None,))[0] for n in ns) if v)
    print("\n### `t_%s` -- main: %d ok / %d FAIL / %d GAP, now: %d ok / %d FAIL / %d GAP\n" % (t, c_old["PASS"], c_old["FAIL"], c_old["GAP"], c_new["PASS"], c_new["FAIL"], c_new["GAP"]))
    print("| check | main | now | what the run said |")
    print("|---|---|---|---|")
    for n in ns:
        o = old.get(n, (None, ""))[0]; v, det = new.get(n, (None, ""))
        # only rows that are interesting: changed, or not ok now
        if o == "PASS" and v == "PASS":
            continue
        print("| %s | %s | %s | %s |" % (n.split(".", 1)[1], sym[o], sym[v], det.replace("|", "/")[:150]))
print("\nTotal now: %d ok, %d FAIL, %d GAP (checks that pass on both kernels are not listed)" % (tot["PASS"], tot["FAIL"], tot["GAP"]))
