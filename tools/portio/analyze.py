#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/portio/analyze.py <trace.log> [idle_from_s; negative = last N s of the trace] -- port/MMIO access statistics of a QEMU memory_region_ops trace.
# Prints: accesses per second (median over the idle window), the top regions/addresses, the ATA command mix.
import re, sys, collections, statistics

path = sys.argv[1]
idle_from = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
rx = re.compile(r"(\d+(?:\.\d+)?) memory_region_ops_(read|write) .*?addr 0x([0-9a-fA-F]+) value 0x([0-9a-fA-F]+) size (\d+) name '([^']*)'")
rows = []
with open(path, errors="replace") as f:
    for line in f:
        m = rx.search(line)
        if m:
            rows.append((float(m.group(1)), m.group(2), int(m.group(3), 16), int(m.group(4), 16), int(m.group(5)), m.group(6)))
if not rows:
    print("PORTIO: no parsable trace lines"); sys.exit(1)
t0 = rows[0][0]
tend = rows[-1][0]
if idle_from < 0:  # negative: the window is the last |idle_from| s minus the final 5 s (idle.txt waits 80 s after "launcher: ready")
    win = [r for r in rows if tend + idle_from <= r[0] <= tend - 5]
else:
    win = [r for r in rows if r[0] - t0 >= idle_from]
if not win:
    print("PORTIO: idle window empty"); sys.exit(1)
span = win[-1][0] - win[0][0]
per = collections.Counter(int(r[0] - t0) for r in win)
secs = sorted(per)
vals = [per[s] for s in secs[1:-1]] or [per[s] for s in secs]
print("window %.0f s (from +%.0f s), total accesses %d" % (span, idle_from, len(win)))
print("PORTIO median/s: %d  mean/s: %.0f" % (statistics.median(vals), sum(vals) / len(vals)))
by = collections.Counter((r[5], r[1], r[2]) for r in win)
print("top (region, rw, addr): count/s")
for (n, rw, a), c in by.most_common(14):
    print("  %-14s %-5s 0x%-4x %7.1f/s" % (n, rw, a, c / max(span, 1)))
ide = [r for r in win if r[5] == "ide"]
cmds = collections.Counter(r[3] for r in ide if r[1] == "write" and r[2] == 0x1f7)
if cmds:
    names = {0x20: "READ", 0x24: "READ_EXT", 0x30: "WRITE", 0xC5: "WRITE_MULTI", 0xC4: "READ_MULTI", 0xC8: "READ_DMA", 0xCA: "WRITE_DMA", 0xE7: "FLUSH", 0xEA: "FLUSH_EXT", 0xEC: "IDENTIFY", 0xC6: "SET_MULTI"}
    print("ATA commands/s:")
    for v, c in cmds.most_common():
        print("  0x%02x %-12s %6.2f/s" % (v, names.get(v, "?"), c / max(span, 1)))
    print("PORTIO ide_cmds/s: %.1f  ide_write_cmds/s: %.1f" % (
        sum(cmds.values()) / max(span, 1),
        sum(c for v, c in cmds.items() if v in (0x30, 0xC5, 0xCA, 0x34, 0x35)) / max(span, 1)))
