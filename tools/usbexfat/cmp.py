#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import re
import sys


def read_base(path):
    want = {}
    for line in open(path):
        sha, size, name = line.rstrip("\n").split(" ", 2)
        if not name.endswith("/"):
            want[name] = sha
    return want


def read_sums(path, prefix):
    got = {}
    for line in open(path, errors="replace"):
        m = re.match(r"^([0-9a-f]{64})  (.*)$", line.rstrip("\r\n"))
        if m and m.group(2).startswith(prefix):
            got[m.group(2)[len(prefix):]] = m.group(1)
    return got


def cmd_sums(base_path, out_path, prefix):
    want = read_base(base_path)
    got = read_sums(out_path, prefix)
    bad = [k for k in want if k in got and got[k] != want[k]]
    missing = [k for k in want if k not in got]
    for k in bad[:4]:
        print("MISMATCH", k)
    print("FILES %d SEEN %d BAD %d" % (len(want), len(got), len(bad)))
    return 1 if bad or not got else 0


def cmd_tree(dump_path, *expect):
    rows = {}
    for line in open(dump_path):
        sha, size, name = line.rstrip("\n").split(" ", 2)
        rows[name] = sha
    fails = 0
    for item in expect:
        name, _, want = item.partition("=")
        if want == "absent":
            ok = name not in rows
        else:
            ok = rows.get(name) == want
        print("%s %s" % ("OK" if ok else "FAIL", name))
        fails += 0 if ok else 1
    return 1 if fails else 0


def cmd_sha(path):
    print(hashlib.sha256(open(path, "rb").read()).hexdigest())
    return 0


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "sums":
        sys.exit(cmd_sums(*sys.argv[2:5]))
    if c == "tree":
        sys.exit(cmd_tree(*sys.argv[2:]))
    if c == "sha":
        sys.exit(cmd_sha(sys.argv[2]))
    sys.exit("usage: cmp.py sums|tree|sha ...")
