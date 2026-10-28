#!/usr/bin/env python3
import os
import re
import sys

MIN_SPAN_MS = int(os.environ.get("FX_MIN_SPAN_MS", "30000"))
STAMP = re.compile(rb"^\[\s*(\d+)\.\d+\]")
BAD_MARKERS = (b"MOZ_CRASH", b"Redirecting call to abort", b"Gtk:ERROR", b"Segmentation fault")
MAIN_PROCESS = re.compile(rb"^\s*\d+\s+\S+\s+\d+:\d+\s+/usr/lib/firefox/firefox --no-remote")
COMMIT = re.compile(rb"wl_surface#\d+\.commit\(\)")


def section(lines, start, stop):
    out = []
    active = False
    for line in lines:
        if line.startswith(start):
            active = True
            continue
        if active and stop and line.startswith(stop):
            break
        if active:
            out.append(line)
    return out


def verdict(path):
    lines = open(path, "rb").read().splitlines()
    if not any(b"wayd: window c=" in line for line in lines):
        return "red", "no wayd window"
    if not any(l.startswith(b"FX3 ps:") for l in lines):
        return "red", "guest never reached the liveness check"
    for line in lines:
        for marker in BAD_MARKERS:
            if marker in line:
                return "red", "crash marker: " + marker.decode()
    ps_block = section(lines, b"FX3 ps:", b"FX3 log:")
    if not any(MAIN_PROCESS.match(l) for l in ps_block):
        return "red", "firefox main process gone"
    log_block = section(lines, b"FX3 first:", b"FX-END")
    stamps = [int(m.group(1)) for m in (STAMP.match(l) for l in log_block) if m]
    if len(stamps) < 2:
        return "red", "no timestamped log lines"
    span = max(stamps) - min(stamps)
    if span < MIN_SPAN_MS:
        return "red", "log span %d ms < %d" % (span, MIN_SPAN_MS)
    tail = section(lines, b"FX3 tail:", b"FX-END")
    if not any(COMMIT.search(l) for l in tail):
        return "red", "no surface commit in the last log lines"
    return "green", "window alive, span %d ms" % span


def main():
    state, reason = verdict(sys.argv[1])
    print("%s %s" % (state, reason))
    sys.exit(0 if state == "green" else 1)


if __name__ == "__main__":
    main()
