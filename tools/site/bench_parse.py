import csv
import math
import re

GROUP_OF_TEST_GROUP = {
    "syscall": "syscalls",
    "time": "syscalls",
    "read": "fs_read",
    "write": "fs_write",
    "meta": "fs_meta",
    "mm": "memory",
    "proc": "process",
    "ipc": "ipc",
    "net": "net",
}

FIREFOX_CASES = [
    ("https1", "https", "smp1", "warm"),
    ("https4", "https", "smp4", "warm"),
    ("data1", "data", "smp1", "warm"),
    ("data4", "data", "smp4", "warm"),
]

FIREFOX_LINE = re.compile(
    r"^(?P<case>\w+) (?P<os>linux|osum) warm n=(?P<n>\d+) png_med=(?P<png>[\d.]+) wall_med=(?P<wall>[\d.]+)"
    r" \| cold png=(?P<cpng>[\d.]+) wall=(?P<cwall>[\d.]+)"
)

GATE_LINE = re.compile(r"^\s+(?:OK|FAIL)\s+(?P<key>[\w.]+)\s+(?P<value>[\d.]+) \(limit")
HOST_LINE = re.compile(r"^\s+(?P<key>host\.[\w]+|idle\.[\w]+|mem\.[\w]+|size\.[\w]+)\s+(?P<value>[\d.]+) (?P<unit>\S+)$")


def ratio_of(linux, osum):
    if linux is None or osum is None or linux <= 0:
        return None
    return round(osum / linux, 2)


def geomean(ratios):
    values = [r for r in ratios if r is not None and r > 0]
    if not values:
        return None
    return round(math.exp(sum(math.log(v) for v in values) / len(values)), 2)


def read_tests(path):
    with open(path, newline="") as handle:
        return {row["test"]: row for row in csv.DictReader(handle, delimiter="\t")}


def read_matrix(path):
    result = {}
    with open(path, newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            linux = float(row["linux"]) if row["linux"] else None
            osum = float(row["osum"]) if row["osum"] else None
            result[row["test"]] = {"linux": linux, "osum": osum, "status": row["status"]}
    return result


def read_apps(path):
    result = {}
    with open(path) as handle:
        next(handle)
        for line in handle:
            parts = line.split()
            if len(parts) < 5:
                continue
            name, linux, osum, _ratio, codes = parts[:5]
            hung = "124" in codes.split(",")
            result[name] = {"linux": float(linux), "osum": float(osum), "hung": hung}
    return result


def read_firefox(path):
    result = {}
    with open(path) as handle:
        for line in handle:
            match = FIREFOX_LINE.match(line.strip())
            if not match:
                continue
            key = (match["case"], match["os"])
            result[key] = {
                "n": int(match["n"]),
                "warm_png": float(match["png"]),
                "warm_rc": float(match["wall"]),
                "cold_png": float(match["cpng"]),
                "cold_rc": float(match["cwall"]),
            }
    return result


def read_bench_gate(path):
    values = {}
    runs = []
    with open(path) as handle:
        for line in handle:
            host = HOST_LINE.match(line.rstrip("\n"))
            if host:
                values[host["key"]] = (float(host["value"]), host["unit"])
            run = re.search(r"run \d+: login screen (\d+) ms, login->desktop (\d+) ms", line)
            if run:
                runs.append((int(run[1]), int(run[2])))
    return values, runs


def read_report_meta(path):
    text = open(path).read()
    commit = re.search(r"Gemessen auf origin/main (\w+)", text)
    load = re.search(r"Serverlast (\d+)-(\d+) \((\d+) Kerne\)", text)
    stamp = re.search(r"Datum (\d{4}-\d{2}-\d{2})", text)
    return {
        "date": stamp[1] if stamp else None,
        "commit": commit[1] if commit else None,
        "load_min": int(load[1]) if load else None,
        "load_max": int(load[2]) if load else None,
        "server_cores": int(load[3]) if load else None,
    }
