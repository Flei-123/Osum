#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""odbc bench: latency + throughput numbers over any transport.
  python3 bench.py --port unix:/tmp/odb.sock --token-file tok [--mib 1] [--path /tmp/odb-bench.bin]
Prints one 'BENCH key=value' line per metric (grep-able) and a final OK/FAIL line."""
import argparse
import hashlib
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from odb.client import Session, read_token_file  # noqa: E402
from odb import proto  # noqa: E402


def med(xs):
    return statistics.median(xs) if xs else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=os.environ.get("ODB_PORT"))
    ap.add_argument("--token")
    ap.add_argument("--token-file")
    ap.add_argument("--mib", type=float, default=1.0)
    ap.add_argument("--path", default="/tmp/odb-bench.bin")
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--timeout", type=float, default=60.0)
    ns = ap.parse_args()
    tok = ns.token or (read_token_file(ns.token_file) if ns.token_file else os.environ.get("ODB_TOKEN"))
    s = Session.open(ns.port, token=tok, wait=10)
    ok = True
    t0 = time.time()
    h = s.login(timeout=5)
    print("BENCH hello_ms=%.1f" % ((time.time() - t0) * 1000))
    print("BENCH agent=%s kernel=%s features=%s window=%d maxchunk=%d" % (
        h.get("agent"), h.get("kernel"), h.get("features"), s.window, s.maxchunk))
    pings = [s.ping() * 1000 for _ in range(ns.n)]
    print("BENCH ping_ms_min=%.2f ping_ms_med=%.2f ping_ms_max=%.2f n=%d" % (min(pings), med(pings), max(pings), len(pings)))
    inf = []
    for _ in range(max(5, ns.n // 4)):
        t = time.time()
        s.request("info", timeout=ns.timeout)
        inf.append((time.time() - t) * 1000)
    print("BENCH info_ms_med=%.2f info_ms_max=%.2f" % (med(inf), max(inf)))
    ex = []
    for _ in range(max(5, ns.n // 4)):
        t = time.time()
        r, out, err = s.exec(cmd="echo odb-bench", timeout=ns.timeout)
        ex.append((time.time() - t) * 1000)
        if out != b"odb-bench\n" or r.geti("exit") != 0:
            ok = False
            print("FAIL: exec echo returned %r exit=%s" % (out, r.get("exit")))
    print("BENCH exec_echo_ms_med=%.2f exec_echo_ms_max=%.2f" % (med(ex), max(ex)))
    size = int(ns.mib * 1024 * 1024)
    blob = os.urandom(size)
    sha = hashlib.sha256(blob).hexdigest()
    rw0 = s.stats["rewinds"]
    t = time.time()
    s.push(blob, ns.path, timeout=ns.timeout)
    dt = time.time() - t
    print("BENCH push_bytes=%d push_s=%.2f push_kib_s=%.1f" % (size, dt, size / 1024 / dt))
    t = time.time()
    r, back = s.pull(ns.path, timeout=ns.timeout)
    dt = time.time() - t
    print("BENCH pull_bytes=%d pull_s=%.2f pull_kib_s=%.1f" % (len(back), dt, len(back) / 1024 / dt))
    print("BENCH rewinds=%d retries=%d bad_crc=%d garbage_bytes=%d" % (
        s.stats["rewinds"] - rw0, s.stats["retries"], s.dec.bad_crc, s.dec.garbage))
    if hashlib.sha256(back).hexdigest() != sha:
        ok = False
        print("FAIL: pushed and pulled bytes differ")
    try:
        t = time.time()
        r, img = s.collect_stream("shot", {"format": "png"}, proto.SHOT, timeout=ns.timeout)
        print("BENCH shot_s=%.2f shot_bytes=%d size=%sx%s" % (time.time() - t, len(img), r.get("w"), r.get("h")))
        if not img.startswith(b"\x89PNG"):
            ok = False
            print("FAIL: shot is not a PNG")
    except proto.AgentError as e:
        print("BENCH shot_error=%s" % e.code)
    try:
        s.exec(cmd="rm " + ns.path, timeout=ns.timeout)
    except Exception:
        pass
    print("OK: bench" if ok else "FAIL: bench")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
