import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from model import parse_file, render, DEFAULT_KEEP
from norm import normalize, text, text_counted
from diffing import first_diff, report


def keep_of(arg):
    return tuple(arg.split(",")) if arg else DEFAULT_KEEP


def load(path, bar, keep):
    return normalize(parse_file(path), bar, keep)


def cmd_parse(a):
    for r in parse_file(a.file):
        print(render(r))
    return 0


def cmd_normalize(a):
    for e in load(a.file, int(a.bar, 16), keep_of(a.keep)):
        print(text_counted(e) if a.counts else text(e))
    return 0


def cmd_diff(a):
    keep = keep_of(a.keep)
    ea = load(a.a, int(a.bar_a, 16), keep)
    eb = load(a.b, int(a.bar_b, 16), keep)
    idx = first_diff(ea, eb)
    print(report(ea, eb, idx, a.context))
    return 0 if idx < 0 else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="regtrace")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("parse")
    p.add_argument("file")
    p.set_defaults(fn=cmd_parse)
    n = sub.add_parser("normalize")
    n.add_argument("file")
    n.add_argument("--bar", default="0")
    n.add_argument("--keep", default="")
    n.add_argument("--counts", action="store_true")
    n.set_defaults(fn=cmd_normalize)
    d = sub.add_parser("diff")
    d.add_argument("a")
    d.add_argument("b")
    d.add_argument("--bar-a", default="0")
    d.add_argument("--bar-b", default="0")
    d.add_argument("--keep", default="")
    d.add_argument("--context", type=int, default=3)
    d.set_defaults(fn=cmd_diff)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
