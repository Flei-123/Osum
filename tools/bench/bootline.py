#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/bootline.py <com1.log> [seconds=60] [min_gap_s=0.5] -- boot timeline of a RUNNING qemu: polls the COM1 log file
# every 50 ms, stamps every new line with the seconds since this script started and prints the lines that came after a pause
# >= min_gap_s (= where boot time goes). Start it right after tools/odbc/qemu.sh start.
import os, sys, time

path = sys.argv[1]
span = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
gap = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
t0 = time.time()
seen = 0
last = 0.0
buf = b""
while time.time() - t0 < span:
    try:
        with open(path, "rb") as f:
            f.seek(seen)
            data = f.read()
    except OSError:
        data = b""
    if data:
        seen += len(data)
        now = time.time() - t0
        buf += data
        parts = buf.split(b"\n")
        buf = parts.pop()
        for ln in parts:
            if now - last >= gap:
                print("%7.2f s  (+%5.2f)  %s" % (now, now - last, ln[:100].decode("latin1")))
            last = now
    time.sleep(0.05)
print("end: %d bytes, last line at %.2f s" % (seen, last))
