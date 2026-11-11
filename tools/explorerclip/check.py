#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def events(path):
    serial = open(path, "rb").read().decode("latin-1")
    found = []
    for m in re.finditer(r"explorer: (clip|paste) n=(\d+)([^\r\n]*)", serial):
        found.append((m.group(1), int(m.group(2)), m.group(3)))
    return found


def field(rest, name):
    m = re.search(name + r"=(\d+)", rest)
    return int(m.group(1)) if m else -1


def main():
    evs = events(sys.argv[1])
    clips = [e for e in evs if e[0] == "clip"]
    pastes = [e for e in evs if e[0] == "paste"]
    note = str(evs)
    verdict("copy_stages", len(clips) >= 1 and clips[0][1] == 1 and field(clips[0][2], "schnitt") == 0 and field(clips[0][2], "rc") == 0, note)
    verdict("paste_from_service", len(pastes) >= 1 and pastes[0][1] == 1 and field(pastes[0][2], "rc") == 0, note)
    verdict("copy_stays_on_clipboard", len(pastes) >= 2 and pastes[1][1] == 1, note)
    verdict("cut_flag", len(clips) >= 2 and clips[1][1] == 1 and field(clips[1][2], "schnitt") == 1, note)
    verdict("cut_paste", len(pastes) >= 3 and pastes[2][1] == 1, note)
    verdict("cut_clears_clipboard", len(pastes) >= 4 and pastes[3][1] == 0, note)


main()
