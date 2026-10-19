#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/portio/stamp.py <fifo> -- reads a QEMU trace from a FIFO and prefixes every line with the seconds since the first byte
# (QEMU's -D log has no timestamps; chunks arrive many times per second, so the stamp is good to ~0.1 s). Output on stdout.
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
