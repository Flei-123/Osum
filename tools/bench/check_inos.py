#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check one BENCHJSON payload (schema 1) printed by `bench --json` inside Osum.

usage: check_inos.py <file-with-json> [--show] [--allow-unknown-commit] [--require-cores]
(--allow-unknown-commit: the fast gate image has no build stamp, /proc/version carries no hash)
exit 0 = all required keys present, numeric and plausible; 1 = problems (listed on stdout).
"""
import json, re, sys

# key -> (min, max) inclusive. Ranges only catch a broken measurement, not a slow one.
RANGES = {
    "boot.init_ms": (1, 600000),
    "boot.total_ms": (1, 600000),
    "mem.total_kib": (100000, 1 << 26),
    "mem.free_kib": (1000, 1 << 26),
    "mem.used_kib": (100, 1 << 26),
    "mem.kheap_kib": (1, 1 << 26),
    "idle.window_ms": (1000, 60000),
    "idle.cpu_busy_permille": (0, 1000),   # optional: needs per-core counters (CS_COUNT > 0)
    "idle.traps_per_s": (0, 1e7),
    "idle.ctxsw_per_s": (0, 1e7),          # optional, same reason
    "idle.syscalls_per_s": (0, 1e7),
    "size.kernel_end_kib": (100, 1 << 20),
    "size.bin_total_b": (1000, 1 << 32),
    "size.fs_total_kib": (100, 1 << 30),
    "size.fs_used_kib": (1, 1 << 30),
    "syscall.getpid_ns": (1, 100000),
    "syscall.yield_ns": (1, 1e7),
    "syscall.pipe_rtt_poll_ns": (1, 1e8),
    "syscall.pipe_rtt_block_ns": (1, 1e8),
    "syscall.fork_exit_wait_us": (1, 1e7),
    "syscall.exec_exit_wait_us": (1, 4000),  # r1222: 10-13 ms while every exec wrote ~270 UART octets; ~1.4 ms now
    "syscall.exec_call_us": (1, 4000),
    "syscall.exec_wait_us": (1, 4000),
    "fs.tmp_write_kib_s": (1, 1e8),
    "fs.tmp_read_kib_s": (1, 1e8),
    "fs.disk_write_kib_s": (1, 1e8),
    "fs.disk_read_kib_s": (1, 1e8),
    "fs.meta_ops_s": (1, 1e8),
    "memcpy.copy_mib_s": (1, 1e6),
    "memcpy.fill_mib_s": (1, 1e6),
    "memcpy.bytecopy_mib_s": (1, 1e6),
    "alloc.brk_touch_mib_s": (1, 1e6),
    "alloc.page_ns": (1, 1e8),
    "cpu.int_mops": (1, 1e6),
    "cpu.float_mflops": (1, 1e6),
    "cpu.sort16k_ms": (0.001, 600000),
    "cpu.hash_mib_s": (1, 1e6),
    "tsc.khz": (100000, 20000000),
}


# keys that only exist with per-core counters (full image / firmware tables); the fast QEMU -kernel gate image has none
OPTIONAL = {"idle.cpu_busy_permille", "idle.ctxsw_per_s"}


def check(d, allow_unknown=False, require_cores=False):
    errs = []
    if not isinstance(d, dict):
        return ["payload is not an object"]
    if d.get("schema") != 1:
        errs.append("schema is %r, expected 1" % (d.get("schema"),))
    if not re.fullmatch(r"[0-9a-f]{8}", str(d.get("commit", ""))) and not (
            allow_unknown and d.get("commit") == "unknown"):
        errs.append("commit %r is not 8 hex" % (d.get("commit"),))
    if d.get("arch") != "x86_64":
        errs.append("arch %r" % (d.get("arch"),))
    res = d.get("results")
    if not isinstance(res, dict):
        return errs + ["results missing"]
    for k, (lo, hi) in RANGES.items():
        if k not in res:
            if k not in OPTIONAL or require_cores:
                errs.append("missing key %s" % k)
            continue
        v = res[k]
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            errs.append("%s is not a number: %r" % (k, v))
        elif not (lo <= v <= hi):
            errs.append("%s = %s outside [%s, %s]" % (k, v, lo, hi))
    for k, v in res.items():
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            errs.append("%s is not a number: %r" % (k, v))
    units = d.get("units")
    if not isinstance(units, dict):
        errs.append("units missing")
    else:
        for k in RANGES:
            if k in res and k not in units:
                errs.append("no unit for %s" % k)
    if res.get("mem.free_kib", 0) > res.get("mem.total_kib", 1 << 62):
        errs.append("mem.free_kib > mem.total_kib")
    return errs


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    try:
        d = json.load(open([a for a in sys.argv[1:] if not a.startswith("--")][0]))
    except Exception as e:  # noqa: BLE001
        print("unreadable JSON: %s" % e)
        return 1
    errs = check(d, "--allow-unknown-commit" in sys.argv, "--require-cores" in sys.argv)
    if "--show" in sys.argv or not errs:
        for k in sorted(d.get("results", {})):
            print("%-28s %s %s" % (k, d["results"][k], d.get("units", {}).get(k, "")))
    for e in errs:
        print("PROBLEM " + e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
