import csv
import glob
import math
import os
import statistics

NS_PER_US = 1000.0
REGISTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests.tsv")
BUDGETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "budgets.tsv")
TARGET = 1.0
UNSUPPORTED = "-"
HEADER = ["test", "linux", "osum", "ratio", "budget", "status"]
RAW_HEADER = ["test", "osum_runs", "linux_runs", "osum_min", "osum_max", "linux_min", "linux_max", "osum_fail", "linux_fail"]


def read_tsv(path):
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def write_tsv(path, header, rows):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def registry():
    return [(r["test"], r["group"], r["label"]) for r in read_tsv(REGISTRY)]


def load_budgets(path=BUDGETS):
    if not os.path.exists(path):
        return {}
    return {r["test"]: r["budget"] for r in read_tsv(path)}


def load_runs(directory, prefix):
    runs = []
    for path in sorted(glob.glob(os.path.join(directory, prefix + "-[0-9]*.txt"))):
        values, failed = {}, set()
        for line in open(path, errors="replace"):
            parts = line.split()
            if len(parts) != 4 or parts[0] != "S":
                continue
            if parts[2] == "FAIL":
                failed.add(parts[1])
                continue
            try:
                values[parts[1]] = float(parts[2])
            except ValueError:
                continue
        if "END" in values:
            runs.append((values, failed))
    return runs


def series(runs, key):
    return [values[key] for values, _ in runs if key in values]


def fail_count(runs, key):
    return sum(1 for _, failed in runs if key in failed)


def fmt_us(value):
    if value is None:
        return ""
    us = value / NS_PER_US
    return "%.4g" % us


def round_up_budget(value):
    if value <= TARGET:
        return TARGET
    digits = 2 - int(math.floor(math.log10(value))) - 1
    scale = 10 ** digits
    return math.ceil(value * scale) / scale


def classify(ratio, budget, osum_fail):
    if budget == UNSUPPORTED:
        return "unsupported"
    if ratio is None:
        return "fail" if osum_fail else "nodata"
    if budget == "":
        return "nobudget"
    if ratio > float(budget):
        return "red"
    return "pass" if ratio <= TARGET else "ratchet"


def build_one(directory, budgets):
    osum, linux = load_runs(directory, "osum"), load_runs(directory, "linux")
    cells = {}
    for test, _, _ in registry():
        o, l = series(osum, test), series(linux, test)
        om = statistics.median(o) if o else None
        lm = statistics.median(l) if l else None
        ratio = om / lm if om is not None and lm else None
        budget = budgets.get(test, "")
        status = classify(ratio, budget, fail_count(osum, test) > 0)
        row = [test, fmt_us(lm), fmt_us(om), "%.2f" % ratio if ratio is not None else "", budget, status]
        raw = [test, len(o), len(l), fmt_us(min(o)) if o else "", fmt_us(max(o)) if o else "",
               fmt_us(min(l)) if l else "", fmt_us(max(l)) if l else "", fail_count(osum, test), fail_count(linux, test)]
        cells[test] = (ratio, row, raw)
    return cells, len(osum), len(linux)


def build_rows(directories, budgets):
    rows, raw = [], []
    runs = (0, 0)
    for directory in directories:
        cells, o_runs, l_runs = build_one(directory, budgets)
        runs = (max(runs[0], o_runs), max(runs[1], l_runs))
        if not rows:
            rows = {t: c[1] for t, c in cells.items()}
            raw = {t: c[2] for t, c in cells.items()}
            best = {t: c[0] for t, c in cells.items()}
            continue
        for test, (ratio, row, raw_row) in cells.items():
            if ratio is not None and (best[test] is None or ratio < best[test]):
                best[test], rows[test], raw[test] = ratio, row, raw_row
    order = [t for t, _, _ in registry()]
    return [rows[t] for t in order], [raw[t] for t in order], runs[0], runs[1]
