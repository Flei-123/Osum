#!/usr/bin/env python3
"""tools/tresor/orphans.py -- the PRODUCER side of the orphan interface.

Round TRESOR, addendum of 27.08.2026. See docs/ORPHANS.md for the
contract; this is a working implementation of it, and it exists for two
reasons:

  1. `/bin/backup` needs the list to be produced by SOMETHING before the
     measurement in `tools/tresor/run.sh` can mean anything. A test that
     hand-writes the list would only prove that `backup` can read a file
     somebody typed.
  2. Round PLAN2 is adding the same answer to `opk` itself, as a
     subcommand. Until that lands, this file IS the reference: it uses
     `opk.py`'s own classes -- `Wurzel`, `Plan`, `quelle_lesen`, `kurz` --
     so it cannot drift from how the package manager actually thinks. When
     `opk orphans` exists, this becomes the cross-check rather than the
     source, and the assertion in run.sh should compare the two.

WHAT THE QUESTION IS, precisely:

    Which store entries would a rebuild on a NEW machine be unable to
    fetch, given this PLAN and these sources?

Not "which packages did I build myself" -- that is a guess about history.
The honest question is about REACHABILITY NOW, and it is answered by
comparing the hashes the plan names against the hashes the registered
sources actually offer. A package built here and later published becomes
reachable and drops off the list by itself; a package from a source that
has since dropped it becomes orphaned and appears, which is exactly right
and is the case a "did I build it?" flag would miss.

USAGE

    python3 tools/tresor/orphans.py --root TREE [--source DIR ...] [-o FILE]

Writes one store entry name per line, sorted, to stdout or to FILE. A
human-readable account of the same thing goes to stderr, where it cannot
contaminate the machine-readable list.
"""

import argparse
import os
import sys


def load_opk(path):
    """Import the real `opk.py` so this cannot drift from the package manager."""
    d = os.path.dirname(os.path.abspath(path))
    if d not in sys.path:
        sys.path.insert(0, d)
    import opk  # noqa: E402
    return opk


def deliverable_hashes(opk, sources, arch):
    """Every FULL hash the given sources could hand back.

    A source that cannot be read is not silently treated as empty -- that
    would turn a typo in a path into "everything is orphaned", which
    inflates the backup instead of failing.
    """
    out = set()
    for d in sources:
        if not os.path.isfile(os.path.join(d, "INDEX")):
            raise SystemExit("orphans: %s has no INDEX -- not a source" % d)
        idx, _signed = opk.quelle_lesen(d, arch=arch)
        for _name, eintrag in idx.items():
            out.add(eintrag[1])
    return out


def orphans_of(opk, root, sources):
    w = opk.Wurzel(root)
    n = w.aktuell()
    if n is None:
        raise SystemExit("orphans: %s has no generation -- nothing installed" % root)
    plan = w.plan_full(n)
    needed = plan.hashes()
    have = deliverable_hashes(opk, sources, plan.arch)
    names = plan.names_by_hash()
    missing = sorted(h for h in needed if h not in have)
    # The DIRECTORY NAME is what `backup` is handed, because the path is
    # what it needs; the shortening rule stays here, on the side that owns
    # it (opk.KURZ).
    return [(opk.kurz(h), h, names.get(h, "?")) for h in missing], len(needed)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_opk = os.path.join(here, "..", "..", "..", "orientos", "pkg", "opk.py")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", required=True, help="an OrientOS tree")
    ap.add_argument("--source", action="append", default=[],
                    help="a source directory; may be given more than once")
    ap.add_argument("--opk", default=os.path.normpath(default_opk),
                    help="path to opk.py")
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args()

    if not os.path.isfile(args.opk):
        raise SystemExit("orphans: no opk.py at %s" % args.opk)
    opk = load_opk(args.opk)

    rows, total = orphans_of(opk, args.root, args.source)
    text = "".join("%s\n" % r[0] for r in rows)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)

    sys.stderr.write("%d package(s) in the plan, %d source(s), %d ORPHANED\n"
                     % (total, len(args.source), len(rows)))
    for short, full, name in rows:
        sys.stderr.write("   %s  %s...  %s\n" % (short, full[:16], name))
    if not rows:
        sys.stderr.write("   every package can be fetched again; the backup "
                         "carries no programs at all\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
