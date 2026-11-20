#!/usr/bin/env python3
import re
import sys
from collections import Counter

TCP_STATE_NAMES = {
    "01": "ESTAB", "02": "SYN_SENT", "03": "SYN_RECV", "04": "FIN_WAIT1",
    "05": "FIN_WAIT2", "06": "TIME_WAIT", "07": "CLOSE", "08": "CLOSE_WAIT",
    "09": "LAST_ACK", "0A": "LISTEN", "0B": "CLOSING",
}
TCP_TABLE_SLOTS = 8
EVENT_MARKERS = ("WORKER-", " net ", "supervisor", "TLS handshake failed", "cannot resolve")
EVENT_LIMIT = 40


def parse_blocks(text):
    blocks = []
    current = None
    for line in text.splitlines():
        match = re.search(r"WATCH up_ms=(\d+) tasks=(\d+)", line)
        if match:
            current = {"up": int(match.group(1)), "tasks": int(match.group(2)),
                       "states": Counter(), "file_nr": ""}
            continue
        if current is None:
            continue
        if line.startswith("WATCHEND"):
            blocks.append(current)
            current = None
            continue
        fields = line.split()
        if len(fields) >= 4 and re.fullmatch(r"\d+:?", fields[0]):
            current["states"][TCP_STATE_NAMES.get(fields[3].upper(), fields[3])] += 1
        elif len(fields) == 3 and all(f.isdigit() for f in fields):
            current["file_nr"] = fields[0]
    return blocks


def print_table(blocks):
    print("   t(s)  tasks  file-nr  tcp rows  states")
    for b in blocks:
        rows = sum(b["states"].values())
        states = " ".join("%s=%d" % kv for kv in sorted(b["states"].items()))
        print("  %5d  %5d  %7s  %8d  %s" % (b["up"] // 1000, b["tasks"], b["file_nr"] or "-", rows, states))


def print_events(text):
    shown = 0
    for line in text.splitlines():
        if any(m in line for m in EVENT_MARKERS) and shown < EVENT_LIMIT:
            print("  " + line.strip()[:200])
            shown += 1


def print_peer(path, soak_s):
    reqs = 0
    stalled = 0
    with open(path, errors="replace") as f:
        for line in f:
            if " REQ-STALLED " in line:
                stalled += 1
            elif " REQ " in line:
                reqs += 1
    print("  relay saw %d requests (%d stalled) in %d s" % (reqs, stalled, soak_s))


def main():
    serial = open(sys.argv[1], errors="replace").read()
    blocks = parse_blocks(serial)
    print("-- table fill per sample --")
    print_table(blocks)
    if len(blocks) >= 2:
        first, last = blocks[0], blocks[-1]
        rows_first = sum(first["states"].values())
        rows_last = sum(last["states"].values())
        print("-- growth first -> last: tasks %d -> %d, tcp rows %d -> %d (table holds %d)"
              % (first["tasks"], last["tasks"], rows_first, rows_last, TCP_TABLE_SLOTS))
    print("-- jarvisd events --")
    print_events(serial)
    print("-- relay --")
    print_peer(sys.argv[2], int(sys.argv[3]))


main()
