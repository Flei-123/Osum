#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/kstack/depth.py -- static worst-case kernel stack depth (r837).
#   python3 tools/kstack/depth.py <kernel.elf> [root-symbol ...]
# Sums `sub $N,%rsp` + pushes per function and follows direct calls; the
# result over-approximates (every call of a function counts, recursion is
# cut). Prints the deepest chain below each root (default: the syscall path).
import re, subprocess, sys, collections

sys.setrecursionlimit(20000)
elf = sys.argv[1]
roots = sys.argv[2:] or ["_F0.sys__dispatch", "syscall_entry"]
dump = subprocess.run(["objdump", "-d", "--no-show-raw-insn", elf],
                      capture_output=True, text=True).stdout
size, calls, cur = {}, collections.defaultdict(set), None
for line in dump.split("\n"):
    m = re.match(r"^[0-9a-f]+ <(.*)>:", line)
    if m:
        cur = m.group(1)
        size.setdefault(cur, 8)
        continue
    if cur is None:
        continue
    m = re.search(r"sub\s+\$0x([0-9a-f]+),%rsp", line)
    if m:
        size[cur] += int(m.group(1), 16)
    if re.search(r"\bpush\b", line):
        size[cur] += 8
    m = re.search(r"\bcall\s+[0-9a-f]+ <([^>+]+)>", line)
    if m:
        calls[cur].add(m.group(1))
memo = {}
onstack = set()

def depth(f):
    # memoised longest path; a node met again while it is still open (recursion) counts 0
    if f in memo:
        return memo[f]
    if f in onstack:
        return (0, [])
    onstack.add(f)
    best = (0, [])
    for c in calls.get(f, ()):
        d = depth(c)
        if d[0] > best[0]:
            best = d
    onstack.discard(f)
    r = (size.get(f, 0) + best[0], [f] + best[1])
    memo[f] = r
    return r

for root in roots:
    if root not in size:
        print("root %s: not found" % root)
        continue
    d = depth(root)
    print("root %s: %d octets" % (root, d[0]))
    if "-v" in sys.argv:
        tot = 0
        for f in d[1]:
            tot += size.get(f, 0)
            print("  %6d %5d %s" % (tot, size.get(f, 0), f))
