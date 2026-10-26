#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bench/lib.py -- helpers of the Osum benchmark runner (run.sh / gate.sh / vbox.sh).

  lib.py waitline <file> <regex> <t0_epoch> <timeout_s>   poll a log, print ms since t0 when the regex matches (exit 1 on timeout)
  lib.py procstat <pid> <seconds>                         print "rss_mb=.. cpu_pct=.." (qemu CPU share of one core over the window)
  lib.py info <odbc-info-text>                            parse `odbc info` lines -> JSON (stdin when "-")
  lib.py benchjson                                        stdin -> the BENCHJSON {...} object of a `bench --json` run (or {})
  lib.py portio <analyze.py output>                       stdin -> {"idle.portio_per_s":..,"idle.ide_cmds_per_s":..}
  lib.py merge <out.json> <commit> <arch> <mode> <run1.json> ...   median over runs -> final result file (schema 1)
  lib.py gate <result.json> <budgets.json> [--worsen F]   check budgets; --worsen multiplies every checked number against its
                                                          direction by F (the counter-proof); exit 1 on any violation
"""
import json
import os
import re
import statistics
import sys
import time

UNITS = {
    "host.boot_agent_ms": "ms", "host.boot_loader_ms": "ms", "host.boot_kernel_ms": "ms", "idle.portio_nonserial_per_s": "1/s", "host.boot_login_ms": "ms", "host.login_to_desktop_ms": "ms", "boot.total_ms": "ms",
    "mem.idle_used_mb": "MB", "mem.total_mb": "MB", "host.qemu_rss_mb": "MB",
    "idle.cpu_pct": "%", "idle.host_cpu_pct": "%", "idle.portio_per_s": "1/s", "idle.ide_cmds_per_s": "1/s",
    "idle.wakeups_per_s": "1/s", "size.kernel_kb": "KB", "size.image_mb": "MB", "size.esp_used_kb": "KB",
    "ui.input_to_picture_ms": "ms", "ui.drag_frame_mean_ms": "ms", "ui.drag_frame_max_ms": "ms",
    "ui.menu_frame_max_ms": "ms", "ui.drag_fps": "fps", "procs.count": "count",
    "ref.boot_prompt_ms": "ms", "ref.idle_used_mb": "MB",
}


def waitline(path, rx, t0, timeout):
    r = re.compile(rx.encode("latin1"))
    end = time.time() + timeout
    while time.time() < end:
        try:
            with open(path, "rb") as f:
                if r.search(f.read()):
                    print(int(round((time.time() - t0) * 1000)))
                    return 0
        except OSError:
            pass
        time.sleep(0.05)
    return 1


def _cpu_ticks(pid):
    f = open("/proc/%s/stat" % pid).read().rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])  # utime + stime


def procstat(pid, secs):
    hz = os.sysconf("SC_CLK_TCK")
    a = _cpu_ticks(pid); t = time.time()
    time.sleep(secs)
    b = _cpu_ticks(pid); dt = time.time() - t
    rss = 0
    for ln in open("/proc/%s/status" % pid):
        if ln.startswith("VmRSS:"):
            rss = int(ln.split()[1])
    print("rss_mb=%.1f cpu_pct=%.2f" % (rss / 1024.0, (b - a) / hz / dt * 100.0))


def parse_info(text):
    kv = {}
    for ln in text.splitlines():
        for m in re.finditer(r"([a-z_]+)=(\S+)", ln):
            kv[m.group(1)] = m.group(2)
    out = {}
    if "mem_total_kb" in kv and "mem_free_kb" in kv:
        tot, free = int(kv["mem_total_kb"]), int(kv["mem_free_kb"])
        out["mem.total_mb"] = round(tot / 1024.0, 1)
        out["mem.idle_used_mb"] = round((tot - free) / 1024.0, 1)
    if "idle_pct" in kv:
        out["idle.cpu_pct"] = round(100.0 - float(kv["idle_pct"]), 2)
    if "procs" in kv:
        out["procs.count"] = int(kv["procs"])
    if "uptime_ms" in kv:
        out["_uptime_ms"] = int(kv["uptime_ms"])
    return out


def benchjson(text):
    for ln in text.splitlines():
        i = ln.find("BENCHJSON ")
        if i >= 0:
            try:
                return json.loads(ln[i + 10:])
            except ValueError:
                pass
    return {}


def portio(text):
    out = {}
    m = re.search(r"PORTIO median/s: (\d+)", text)
    if m:
        out["idle.portio_per_s"] = int(m.group(1))
    # the ODB agent polls COM2 (serial) ~800x/s: counted in idle.portio_per_s, but the budget is on everything else
    top = [float(x) for x in re.findall(r"^\s+(?!serial)\S+\s+(?:read|write)\s+0x\w+\s+([\d.]+)/s", text, re.M)]
    if top:
        out["idle.portio_nonserial_per_s"] = int(round(sum(top)))
    m = re.search(r"PORTIO ide_cmds/s: ([\d.]+)", text)
    if m:
        out["idle.ide_cmds_per_s"] = float(m.group(1))
    return out


def merge(outp, commit, arch, mode, files):
    runs = [json.load(open(f)) for f in files]
    keys = sorted({k for r in runs for k in r if not k.startswith("_")})
    res = {}
    spread = {}
    for k in keys:
        vals = [r[k] for r in runs if k in r and isinstance(r[k], (int, float))]
        if vals:
            res[k] = round(statistics.median(vals), 3)
            spread[k] = [min(vals), max(vals)]
    doc = {"schema": 1, "commit": commit, "arch": arch, "results": res,
           "units": {k: UNITS.get(k, "") for k in res},
           "host": {"mode": mode, "runs": len(runs), "spread": spread, "load1": os.getloadavg()[0],
                    "cpus": os.cpu_count(), "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "kvm": os.access("/dev/kvm", os.W_OK)}}
    json.dump(doc, open(outp, "w"), indent=1, sort_keys=True)
    open(outp, "a").write("\n")
    print("wrote %s (%d keys, %d runs)" % (outp, len(res), len(runs)))


def gate(resf, budf, worsen):
    res = json.load(open(resf))["results"]
    bud = json.load(open(budf))
    bad = 0
    for k, b in sorted(bud.items()):
        if k.startswith("_"):
            continue
        if k not in res:
            print("  SKIP  %-26s not measured" % k)
            continue
        v = res[k]
        if "max" in b:
            v2 = v * worsen if worsen else v
            ok = v2 <= b["max"]
            print("  %s  %-26s %s (limit <= %s)%s" % ("OK  " if ok else "FAIL", k, v2, b["max"], "  [worsened x%g]" % worsen if worsen else ""))
        else:
            v2 = v / worsen if worsen else v
            ok = v2 >= b["min"]
            print("  %s  %-26s %s (limit >= %s)%s" % ("OK  " if ok else "FAIL", k, v2, b["min"], "  [worsened x%g]" % worsen if worsen else ""))
        bad += (not ok)
    print("BENCH-GATE: %d violation(s)" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    a = sys.argv[1:]
    c = a[0] if a else ""
    if c == "waitline":
        sys.exit(waitline(a[1], a[2], float(a[3]), float(a[4])))
    elif c == "procstat":
        procstat(a[1], float(a[2]))
    elif c == "info":
        print(json.dumps(parse_info(sys.stdin.read() if a[1] == "-" else a[1])))
    elif c == "benchjson":
        print(json.dumps(benchjson(sys.stdin.read())))
    elif c == "portio":
        print(json.dumps(portio(sys.stdin.read())))
    elif c == "merge":
        merge(a[1], a[2], a[3], a[4], a[5:])
    elif c == "gate":
        w = float(a[a.index("--worsen") + 1]) if "--worsen" in a else 0
        sys.exit(gate(a[1], a[2], w))
    else:
        print(__doc__)
        sys.exit(2)
