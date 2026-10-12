#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/qa/gates-select.py -- pick the gates for a set of changed files (used by gates.sh).

  gates-select.py --level quick|full|nightly [--explain] [--manifest F] < list-of-changed-paths

Prints one gate name per line (stdout) and notes/warnings (stderr, prefixed '#').
Levels are cumulative: quick = tier quick, full = quick+full, nightly = everything
(nightly ignores the changed paths and selects ALL gates).
Selection: a gate is picked when one of its path globs matches a changed file.
A changed file under kernel/ lib/ vendor/ etc/ assets/ that NO gate claims is
reported, and the fallback gates (kernel, userland) are added so that a typo in
the manifest never means "no gate ran".
"""
import fnmatch, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LEVELS = {"quick": {"quick"}, "full": {"quick", "full"}, "nightly": {"quick", "full", "nightly"}}
FALLBACK = ["kernel", "userland"]
WATCHED = ("kernel/", "lib/", "vendor/", "etc/", "assets/", "tools/build-kernel.sh", "tools/config", "test.sh")
IGNORED = ("docs/", "reports/", "pruef/")


def main():
    a = sys.argv[1:]
    level = a[a.index("--level") + 1] if "--level" in a else "full"
    man = a[a.index("--manifest") + 1] if "--manifest" in a else os.path.join(ROOT, "tools", "qa", "gates.tsv")
    explain = "--explain" in a
    if level not in LEVELS:
        sys.exit("level must be quick|full|nightly")
    rows = [ln.split("\t") for ln in open(man, encoding="utf-8").read().splitlines()[1:] if ln.strip()]
    gates = {r[0]: (r[1], r[3].split(",")) for r in rows}
    changed = [ln.strip() for ln in sys.stdin if ln.strip()]
    picked, why = {}, {}
    if level == "nightly":
        for g in gates:
            picked[g] = True
            why[g] = "nightly = all"
    else:
        want = LEVELS[level]
        unmapped = []
        for f in changed:
            if f.startswith(IGNORED) or f.endswith(".md"):
                continue
            hit = False
            for g, (tier, globs) in gates.items():
                if any(fnmatch.fnmatch(f, p) for p in globs):
                    hit = True
                    if tier in want and g not in picked:
                        picked[g] = True
                        why[g] = f
            if not hit and f.startswith(WATCHED):
                unmapped.append(f)
        # a changed test.sh / gate runner itself selects the self-tests of the QA tooling
        if unmapped:
            print("# unmapped paths (add them to tools/qa/gen-manifest.py AREAS): " + ", ".join(unmapped[:8]) +
                  (" ..." if len(unmapped) > 8 else ""), file=sys.stderr)
            for g in FALLBACK:
                if g in gates and g not in picked:
                    picked[g] = True
                    why[g] = "fallback for unmapped path"
    for g in sorted(picked):
        print(g)
        if explain:
            print(f"# {g}: {gates[g][0]} <- {why[g]}", file=sys.stderr)


if __name__ == "__main__":
    main()
