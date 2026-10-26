# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import corpus_checks
import hidcaps
import refparser
import reportfile
import selftest

CORPUS = os.path.join(HERE, "corpus", "holo-laptop-3")


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def load_corpus(directory):
    devices = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".caps"):
            continue
        base = os.path.join(directory, name[:-5])
        caps = hidcaps.load(os.path.join(directory, name))
        desc = bytes.fromhex(read(base + ".desc.hex").strip())
        devices.append((caps, desc, read(base + ".desc.meta")))
    return devices


def run_checks(directory):
    results = []
    refs = {}
    for caps, desc, meta in load_corpus(directory):
        results.append(corpus_checks.check_device(caps, desc, meta))
        head, fields = refparser.parse(desc)
        refs[caps.name] = refparser.expand(fields)
    lines = reportfile.parse_file(read(os.path.join(directory, "reports.txt")))
    results.append(corpus_checks.check_reports(lines, refs))
    return results


def print_items(items):
    ok = fail = 0
    for good, label, detail in items:
        if good:
            ok += 1
            print("OK   " + label)
        else:
            fail += 1
            print("FAIL %s%s" % (label, ": " + detail if detail else ""))
    return ok, fail


def main(argv):
    directory = CORPUS
    if "--selftest" in argv:
        return selftest.run(directory)
    ok = fail = 0
    for result in run_checks(directory):
        o, f = print_items(result.items)
        ok += o
        fail += f
    print("corpus: %d ok, %d fail" % (ok, fail))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
