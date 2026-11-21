#!/usr/bin/env python3
import argparse
import csv
import datetime
import json
import os
import statistics
import sys

import bench_parse as parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_RAW = "/root/jarvis/data/projects_kb/orientos/reports/w-speed-vs-linux-real-files"
DEFAULT_REPORT = "/root/jarvis/data/projects_kb/orientos/reports/20261121-092506_w-speed-vs-linux-real.md"
DEFAULT_OUT = "/root/projects/osum-site/src/data"
SMP_KEYS = ("smp1", "smp4")
FIREFOX_ENTRIES = [
    ("ff_https_warm_png", "https", "warm", "png"),
    ("ff_https_warm_rc", "https", "warm", "rc"),
    ("ff_data_warm_png", "data", "warm", "png"),
    ("ff_data_warm_rc", "data", "warm", "rc"),
    ("ff_https_cold_png", "https", "cold", "png"),
    ("ff_https_cold_rc", "https", "cold", "rc"),
]
APP_GROUP = "apps"
FIREFOX_GROUP = "firefox"


def side(linux, osum, hung=False):
    ratio = parse.ratio_of(linux, osum)
    if hung:
        status = "hang"
    elif ratio is None:
        status = "unsupported"
    else:
        status = "ahead" if ratio <= 1.0 else "behind"
    return {"linux": linux, "osum": osum, "ratio": None if hung else ratio, "status": status}


def matrix_entries(raw, tests):
    matrices = {smp: parse.read_matrix(os.path.join(raw, "matrix-%s.tsv" % smp)) for smp in SMP_KEYS}
    entries = []
    for test_id, meta in tests.items():
        group = parse.GROUP_OF_TEST_GROUP[meta["group"]]
        entry = {"id": test_id, "group": group, "label": meta["label"], "unit": "us"}
        for smp in SMP_KEYS:
            row = matrices[smp][test_id]
            entry[smp] = side(row["linux"], row["osum"])
        entries.append(entry)
    return entries


def app_entries(raw):
    apps = {smp: parse.read_apps(os.path.join(raw, "apps-%s.txt" % smp)) for smp in SMP_KEYS}
    entries = []
    for name in apps["smp1"]:
        entry = {"id": name, "group": APP_GROUP, "label": name, "unit": "s"}
        for smp in SMP_KEYS:
            row = apps[smp][name]
            entry[smp] = side(row["linux"], row["osum"], row["hung"])
        entries.append(entry)
    return entries


def firefox_entries(raw):
    summary = parse.read_firefox(os.path.join(raw, "firefox-summary.txt"))
    entries = []
    for entry_id, kind, temp, phase in FIREFOX_ENTRIES:
        entry = {"id": entry_id, "group": FIREFOX_GROUP, "label": entry_id, "unit": "s", "kind": kind, "temp": temp, "phase": phase}
        for smp in SMP_KEYS:
            case = "%s%s" % (kind, smp[-1])
            linux = summary.get((case, "linux"))
            osum = summary.get((case, "osum"))
            key = "%s_%s" % (temp, phase)
            entry[smp] = side(linux[key] if linux else None, osum[key] if osum else None)
            if linux:
                entry[smp]["runs"] = linux["n"] if temp == "warm" else 1
        entries.append(entry)
    return entries


def attach_in_work(entries, in_work):
    by_test = {}
    for item in in_work:
        for test_id in item["tests"]:
            by_test[test_id] = item["id"]
    for entry in entries:
        marker = by_test.get(entry["id"])
        if marker and any(entry[smp]["status"] in ("behind", "hang") for smp in SMP_KEYS):
            entry["in_work"] = marker


def matrix_summary(entries):
    result = {}
    for smp in SMP_KEYS:
        measured = [e for e in entries if e["group"] not in (APP_GROUP, FIREFOX_GROUP) and e[smp]["ratio"] is not None]
        ratios = [e[smp]["ratio"] for e in measured]
        raw_ratios = [e[smp]["osum"] / e[smp]["linux"] for e in measured]
        result[smp] = {
            "geomean": parse.geomean(raw_ratios),
            "tests": len(measured),
            "at_or_below_1": sum(1 for r in ratios if r <= 1.0),
            "above_2": sum(1 for r in ratios if r > 2.0),
            "worst": [e["id"] for e in sorted(measured, key=lambda e: -e[smp]["ratio"])[:5]],
        }
    return result


def boot_summary(raw, sources):
    values, runs = parse.read_bench_gate(os.path.join(raw, "benchfull.log"))
    if not runs or "mem.idle_used_mb" not in values:
        sys.exit("benchfull.log: boot or idle RAM values missing")
    login_ms = [r[0] for r in runs]
    desktop_ms = [r[1] for r in runs]
    return {
        "runs": len(runs),
        "login_s": round(statistics.median(login_ms) / 1000, 2),
        "login_s_range": [round(min(login_ms) / 1000, 2), round(max(login_ms) / 1000, 2)],
        "login_to_desktop_s": round(statistics.median(desktop_ms) / 1000, 1),
        "idle_ram_mb": values["mem.idle_used_mb"][0],
        "image_mb": values["size.image_mb"][0],
        "kernel_kb": values["size.kernel_kb"][0],
        "idle_cpu_pct": values["idle.cpu_pct"][0],
        "linux_login_s": sources["references"]["debian13"]["boot_to_login_s"],
        "linux_idle_ram_mb": sources["references"]["debian13"]["idle_ram_mb"],
        "linux_image_mb": sources["references"]["debian13"]["image_mb"],
        "paired": False,
        "vm": "QEMU KVM, 2 vCPU, 1536 MB, AHCI, -kernel direct",
    }


def firefox_summary(entries):
    wanted = {"https_png": "ff_https_warm_png", "https_rc": "ff_https_warm_rc"}
    by_id = {e["id"]: e for e in entries}
    return {name: {smp: by_id[eid][smp] for smp in SMP_KEYS} for name, eid in wanted.items()}


def git_head(path):
    import subprocess
    out = subprocess.run(["git", "-C", path, "rev-parse", "--short=9", "HEAD"], capture_output=True, text=True)
    return out.stdout.strip() or None


def write_csv(path, entries, measurement):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["measured", "osum_commit", "group", "test", "label", "unit", "smp", "linux", "osum", "ratio_osum_over_linux", "status"])
        for entry in entries:
            for smp in SMP_KEYS:
                cell = entry[smp]
                writer.writerow([measurement["date"], measurement["osum_commit"], entry["group"], entry["id"], entry["label"], entry["unit"],
                                 smp.upper(), cell["linux"], cell["osum"], cell["ratio"], cell["status"]])


def build(args):
    sources = json.load(open(args.sources))
    tests = parse.read_tests(os.path.join(REPO, "tools", "speedcmp", "tests.tsv"))
    meta = parse.read_report_meta(args.report)
    entries = matrix_entries(args.raw, tests) + app_entries(args.raw) + firefox_entries(args.raw)
    attach_in_work(entries, sources["in_work"])
    commit = args.commit or meta["commit"]
    date = args.date or os.path.basename(args.report)[:8]
    date = "%s-%s-%s" % (date[:4], date[4:6], date[6:8]) if "-" not in date else date
    measurement = {
        "id": "%s-%s" % (date, commit),
        "date": date,
        "osum_commit": commit,
        "osum_commit_note": "origin/main, kernel stage 0",
        "server_load": {"min": meta["load_min"], "max": meta["load_max"], "cores": meta["server_cores"]},
    }
    return {
        "schema_version": sources["schema_version"],
        "measurement": measurement,
        "exported": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
        "exporter_commit": git_head(REPO),
        "linux": sources["linux"],
        "setup": sources["setup"],
        "summary": {
            "matrix": matrix_summary(entries),
            "boot": boot_summary(args.raw, sources),
            "firefox": firefox_summary(entries),
            "syscalls": sources["syscalls"],
            "references": sources["references"],
        },
        "entries": entries,
        "in_work": sources["in_work"],
        "not_measured": sources["not_measured"],
        "uncertainty": sources["uncertainty"],
        "host": sources["host"],
    }


def main():
    parser = argparse.ArgumentParser(description="Export Osum vs Linux benchmark data for osum.fleitec.com")
    parser.add_argument("--raw", default=DEFAULT_RAW)
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--sources", default=os.path.join(HERE, "bench_sources.json"))
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--commit")
    parser.add_argument("--date")
    args = parser.parse_args()
    data = build(args)
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "bench.json"), "w") as handle:
        json.dump(data, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    write_csv(os.path.join(args.out, "bench.csv"), data["entries"], data["measurement"])
    summary = data["summary"]["matrix"]
    print("exported %s smp1=%s smp4=%s entries=%d" % (data["measurement"]["id"], summary["smp1"]["geomean"], summary["smp4"]["geomean"], len(data["entries"])))


if __name__ == "__main__":
    main()
