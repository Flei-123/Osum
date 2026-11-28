#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
LIMIT_NAMES = ("MAX_TASKS", "MAX_CPUS")
LITERAL_CPU_CONST = re.compile(r"^const ([A-Z_]*(?:CPUS|NCPU)): u64 = (8)\s*$", re.M)
ZERO_ARRAY = re.compile(r"^static mut (\w+): \[u64; (\d+)\] = \[0 as u64; (\d+)\]", re.M)


def kernel_limits():
    text = (ROOT / "kernel/lib/kstate.fi").read_text()
    values = {}
    for name in LIMIT_NAMES:
        match = re.search(r"^const %s: u64 = (\d+)" % name, text, re.M)
        if not match:
            sys.exit("missing %s in kstate" % name)
        values[name] = int(match.group(1))
    return values


def read_rows():
    rows = []
    for line in (ROOT / "tools/limits/tables.tsv").read_text().splitlines()[1:]:
        if line.strip():
            rows.append(line.split("\t"))
    return rows


def evaluate(expr, limits):
    return eval(expr, {"__builtins__": {}}, dict(limits))


def check_const(text, name, expr):
    return re.search(r"^const %s: u64 = kstate\.%s\s*$" % (name, expr), text, re.M) is not None


def check_array(text, name, expected):
    match = re.search(r"^static mut %s: \[u64; (\d+)\] = \[0 as u64; (\d+)\]" % name, text, re.M)
    if not match:
        return "array %s not found" % name
    if int(match.group(1)) != expected or int(match.group(2)) != expected:
        return "array %s has %s/%s entries, expected %d" % (name, match.group(1), match.group(2), expected)
    return None


def check_file(path, rows, limits, problems):
    text = (ROOT / path).read_text()
    covered = set()
    for _, kind, name, expr in rows:
        covered.add(name)
        if kind == "const" and not check_const(text, name, expr):
            problems.append("%s: const %s must be 'kstate.%s'" % (path, name, expr))
        if kind == "array":
            error = check_array(text, name, evaluate(expr, limits))
            if error:
                problems.append("%s: %s" % (path, error))
        if kind == "fixed" and expr.isdigit():
            error = check_array(text, name, int(expr))
            if error:
                problems.append("%s: %s" % (path, error))
    for name, size, _ in ZERO_ARRAY.findall(text):
        if name not in covered and int(size) > 1:
            problems.append("%s: array %s[%s] is not in tables.tsv" % (path, name, size))


def check_literal_cpus(problems):
    baseline = set((ROOT / "tools/limits/cpu_baseline.txt").read_text().split())
    for path in sorted((ROOT / "kernel").rglob("*.fi")):
        rel = str(path.relative_to(ROOT))
        if rel.startswith("kernel/user/") or rel == "kernel/lib/kstate.fi":
            continue
        for name, _ in LITERAL_CPU_CONST.findall(path.read_text(errors="ignore")):
            if name == "MAX_CPUS" or rel + ":" + name not in baseline:
                problems.append("%s: independent literal %s" % (rel, name))


def main():
    limits = kernel_limits()
    rows = read_rows()
    problems = []
    for path in sorted({row[0] for row in rows}):
        check_file(path, [row for row in rows if row[0] == path], limits, problems)
    check_literal_cpus(problems)
    checked = len(rows)
    for line in problems:
        print("FAIL", line)
    print("limits: MAX_TASKS=%d MAX_CPUS=%d rows=%d problems=%d" % (limits["MAX_TASKS"], limits["MAX_CPUS"], checked, len(problems)))
    return 1 if problems else 0


sys.exit(main())
