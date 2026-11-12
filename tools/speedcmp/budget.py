#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import csv
import sys

DEFAULT_MAX_FACTOR = 1.0


def load_budget(path):
    budget = {}
    with open(path, newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if row and not row[0].startswith("#") and row[0] != "metric":
                budget[row[0]] = (float(row[1]), row[2] if len(row) > 2 else "")
    return budget


def load_table(path):
    with open(path, newline="") as handle:
        return {row["metric"]: float(row["factor"]) for row in csv.DictReader(handle, delimiter="\t")}


def main():
    table_path = sys.argv[1] if len(sys.argv) > 1 else "docs/speed-osum-vs-linux.tsv"
    budget_path = sys.argv[2] if len(sys.argv) > 2 else "tools/speedcmp/budget.tsv"
    budget = load_budget(budget_path)
    table = load_table(table_path)
    red = 0
    for metric, factor in table.items():
        limit, note = budget.get(metric, (DEFAULT_MAX_FACTOR, ""))
        ok = factor <= limit
        red += 0 if ok else 1
        print("%s %-28s factor %8.2f limit %8.2f %s" % ("OK  " if ok else "RED ", metric, factor, limit, note))
    print("SPEEDBUDGET: %d red of %d" % (red, len(table)))
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
