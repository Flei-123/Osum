#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("disdiff", os.path.join(HERE, "disdiff.py"))
DISDIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DISDIFF)

MAX_FORWARDER_INSNS = 24
CALL = re.compile(r"^(call|jmp)\s")
TARGET = re.compile(r"<([^>+]+)(\+N)?>")


def short(name):
    return re.sub(r"^_F0\.", "", name).split("__")[-1]


def is_forwarder(name, body):
    calls = [line for line in body if CALL.match(line)]
    return len(body) <= MAX_FORWARDER_INSNS and len(calls) == 1 and calls[0].endswith("<" + name + ">")


def load(path):
    groups = defaultdict(list)
    for full, body in DISDIFF.load(path, lambda n: n).items():
        name = short(full)
        flat = tuple(TARGET.sub(lambda m: "<" + short(m.group(1)) + (m.group(2) or "") + ">", ln) for ln in body)
        if not is_forwarder(name, flat):
            groups[name].append(flat)
    return groups


def main():
    before, after = load(sys.argv[1]), load(sys.argv[2])
    only_before, only_after, changed = [], [], []
    for name in sorted(set(before) | set(after)):
        cb, ca = Counter(before.get(name, [])), Counter(after.get(name, []))
        if cb == ca:
            continue
        if not ca:
            only_before.append(name)
        elif not cb:
            only_after.append(name)
        else:
            changed.append(name)
    print("names before=%d after=%d only_before=%d only_after=%d body_diff=%d"
          % (len(before), len(after), len(only_before), len(only_after), len(changed)))
    for tag, items in (("ONLY_BEFORE", only_before), ("ONLY_AFTER", only_after), ("DIFF", changed)):
        for name in items:
            print(tag, name)
    sys.exit(1 if only_before or only_after or changed else 0)


if __name__ == "__main__":
    main()
