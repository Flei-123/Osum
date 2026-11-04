import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from bridge import Bridge
from context import Context
from registry import load_all
from report import Report, fail


def main():
    ap = argparse.ArgumentParser(description="Read-only hardware walk through the paired bridge; works at the login screen.")
    ap.add_argument("--device", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--groups", default="")
    ap.add_argument("--passive", action="store_true")
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    groups = load_all()
    if args.list:
        for g in groups:
            print(g["name"], len(g["commands"]))
        return 0
    bridge = Bridge(args.device)
    try:
        item = bridge.pick_device(args.device)
    except RuntimeError as e:
        print("ABORT: %s -- nothing was sent." % e)
        return 3
    print("device %s" % bridge.device)
    out = args.out or "/root/hwwalk-logs/" + time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(out, exist_ok=True)
    ctx = Context(bridge, active=not args.passive, timeout=args.timeout)
    wanted = set(args.groups.split(",")) if args.groups else None
    selected = [g for g in groups if not wanted or g["name"] in wanted]
    ctx.prefetch([c for g in selected for c in g["commands"]])
    report = Report(bridge.device)
    for g in selected:
        try:
            report.extend(g["fn"](ctx))
        except Exception as e:
            report.extend([fail(g["name"], "check crashed", repr(e)[:120])])
    report.write(out)
    print("hw_walk: %s -> %s" % (report.summary(), out))
    return report.exit_code()


if __name__ == "__main__":
    sys.exit(main())
