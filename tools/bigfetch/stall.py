#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys
import time


def main(argv):
    path, pid, done_mark = argv[1], int(argv[2]), argv[3].encode()
    last_count = 0
    last_time = None
    max_gap = 0.0
    finished = False
    while True:
        try:
            os.kill(pid, 0)
            alive = True
        except ProcessLookupError:
            alive = False
        try:
            with open(path, "rb") as f:
                data = f.read()
        except FileNotFoundError:
            data = b""
        count = data.count(b"\nPROBE") + (1 if data.startswith(b"PROBE") else 0)
        finished = done_mark in data
        now = time.time()
        if count != last_count:
            if last_time is not None:
                max_gap = max(max_gap, now - last_time)
            last_count = count
            last_time = now
        elif last_time is not None and not finished:
            max_gap = max(max_gap, now - last_time)
        if not alive:
            break
        time.sleep(0.5)
    print("%.1f %d %d" % (max_gap, last_count, 1 if finished else 0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
