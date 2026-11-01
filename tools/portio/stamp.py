#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, sys, time
fd = os.open(sys.argv[1], os.O_RDONLY)
t0 = None
buf = b""
out = sys.stdout.buffer
while True:
    chunk = os.read(fd, 1 << 16)
    if not chunk:
        break
    now = time.monotonic()
    if t0 is None:
        t0 = now
    buf += chunk
    cut = buf.rfind(b"\n")
    if cut < 0:
        continue
    stamp = ("%.2f " % (now - t0)).encode()
    for ln in buf[:cut].split(b"\n"):
        out.write(stamp + ln + b"\n")
    buf = buf[cut + 1:]
out.flush()
