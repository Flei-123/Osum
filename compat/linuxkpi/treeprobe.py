#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

MISSING = re.compile(r"fatal error: ([^:]+): No such file or directory")
ERROR = re.compile(r": error: ")
MAX_ROUNDS = 40


def compile_unit(cc, flags, tree, unit, extra, out=None):
    src = os.path.join(tree, unit)
    cmd = [cc] + flags + ["-I" + os.path.dirname(src), "-I" + tree] + extra
    cmd += ["-c", src, "-o", out] if out else ["-fsyntax-only", src]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode, res.stderr


def classify(rc, err):
    if rc == 0:
        return "ok", None, 0
    miss = MISSING.search(err)
    if miss:
        return "header", miss.group(1), 0
    return "errors", None, len(ERROR.findall(err))


def discover_headers(cc, flags, tree, units, jobs):
    stub = tempfile.mkdtemp(prefix="lkpi-stub-")
    found = set()
    for _ in range(MAX_ROUNDS):
        extra = ["-idirafter", stub]
        with ThreadPoolExecutor(jobs) as pool:
            results = list(pool.map(lambda u: compile_unit(cc, flags, tree, u, extra), units))
        new = {m for _, err in results for m in MISSING.findall(err)} - found
        if not new:
            break
        for name in new:
            path = os.path.join(stub, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        found |= new
    subprocess.run(["rm", "-rf", stub])
    return sorted(found)


def nm_names(path, undefined):
    flag = ["-u"] if undefined else ["--defined-only"]
    res = subprocess.run(["nm", "-P"] + flag + [path], capture_output=True, text=True)
    names = set()
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and (undefined or parts[1] in "TDBRWVtdbr"):
            if undefined or parts[1].isupper():
                names.add(parts[0])
    return names


def closure(cc, flags, tree, ok_units, shim_objs):
    work = tempfile.mkdtemp(prefix="lkpi-obj-")
    undef, defined = set(), set()
    for unit in ok_units:
        obj = os.path.join(work, unit.replace("/", "_") + ".o")
        rc, _ = compile_unit(cc, flags, tree, unit, [], obj)
        if rc == 0:
            undef |= nm_names(obj, True)
            defined |= nm_names(obj, False)
    provided = set()
    for obj in shim_objs:
        provided |= nm_names(obj, False)
    subprocess.run(["rm", "-rf", work])
    return sorted(undef - defined - provided)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", required=True)
    ap.add_argument("--units", required=True)
    ap.add_argument("--cc", default="gcc")
    ap.add_argument("--flag", action="append", default=[])
    ap.add_argument("--shim-obj", action="append", default=[])
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--json", required=True)
    args = ap.parse_args()
    units = [u.strip() for u in open(args.units) if u.strip()]
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda u: compile_unit(args.cc, args.flag, args.tree, u, []), units))
    per_unit = {}
    for unit, (rc, err) in zip(units, results):
        state, header, errors = classify(rc, err)
        per_unit[unit] = {"state": state, "header": header, "errors": errors}
    ok_units = [u for u in units if per_unit[u]["state"] == "ok"]
    headers = discover_headers(args.cc, args.flag, args.tree, units, args.jobs)
    undefined = closure(args.cc, args.flag, args.tree, ok_units, args.shim_obj)
    report = {"units": len(units), "units_ok": len(ok_units), "headers_missing": headers,
              "undefined": undefined, "complete": len(ok_units) == len(units), "per_unit": per_unit}
    json.dump(report, open(args.json, "w"), indent=1, sort_keys=True)
    print("units_ok=%d/%d headers_missing=%d undefined=%d complete=%s" % (
        len(ok_units), len(units), len(headers), len(undefined), report["complete"]))


if __name__ == "__main__":
    sys.exit(main())
