#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAPS_ALL = 127


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    expected = [x.strip() for x in open(os.path.join(HERE, "expected.txt")) if x.strip()]
    ok_names = [m.group(1).strip() for m in re.finditer(r"svcconf: ok   (.+)", serial)]
    bad_names = [m.group(1).strip() for m in re.finditer(r"svcconf: FAIL (.+)", serial)]
    for name in expected:
        if name in bad_names:
            verdict(slug(name), False, "FAIL line")
        else:
            verdict(slug(name), name in ok_names, "" if name in ok_names else "no ok line")
    summary = re.search(r"svcconf: services orientos caps (\d+): (\d+) checks, (\d+) failures", serial)
    verdict("summary_line", summary is not None)
    if summary:
        verdict("caps_all_bits", int(summary.group(1)) == CAPS_ALL, summary.group(1))
        verdict("check_count", int(summary.group(2)) == len(expected), summary.group(2))
        verdict("zero_failures", int(summary.group(3)) == 0, summary.group(3))
    verdict("conformance_done", "svcconf: done" in serial)


main()
