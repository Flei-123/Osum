#!/usr/bin/env python3
import re
import sys

MARKER = "AUDITSHELL_OK"


def terminal_rows(serial_path):
    text = open(serial_path, "rb").read().decode("latin1")
    return [m.group(1).rstrip() for m in re.finditer(r"wm: (?:tw\d+|termzeile) \d+ \[(.*)\]", text)]


def main():
    rows = terminal_rows(sys.argv[1])
    expect = sys.argv[2]
    ready = any("sh: ready" in r for r in rows)
    bye = any("sh: bye" in r for r in rows)
    answered = any(r.strip() == MARKER for r in rows)
    if not rows:
        print("no terminal rows in the serial log")
        sys.exit(1)
    summary = "rows=%d ready=%d bye=%d answered=%d" % (len(rows), ready, bye, answered)
    alive = ready and answered and not bye
    dead = ready and bye and not answered
    if expect == "alive" and alive:
        print(summary)
        sys.exit(0)
    if expect == "dead" and dead:
        print(summary)
        sys.exit(0)
    print("expected %s: %s" % (expect, summary))
    sys.exit(1)


if __name__ == "__main__":
    main()
