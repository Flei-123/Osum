#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def events(path):
    serial = open(path, "rb").read().decode("latin-1")
    clips = [(int(m.group(1)), int(m.group(2)), int(m.group(3))) for m in re.finditer(r"explorer: clip n=(\d+) schnitt=(\d+) rc=(\d+)", serial)]
    pastes = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"explorer: paste n=(\d+) rc=(\d+)", serial)]
    return clips, pastes


def main():
    clips, pastes = events(sys.argv[1])
    note = str((clips, pastes))
    verdict("cut_flag", len(clips) >= 1 and clips[0] == (1, 1, 0), note)
    verdict("cut_paste_consumes", len(pastes) >= 1 and pastes[0] == (0, 0), note)
    verdict("cut_clears_clipboard", len(pastes) >= 2 and pastes[1] == (0, 0), note)
    verdict("copy_stages", len(clips) >= 2 and clips[1] == (1, 0, 0), note)
    verdict("paste_from_service", len(pastes) >= 3 and pastes[2] == (1, 0), note)
    verdict("copy_stays_on_clipboard", len(pastes) >= 4 and pastes[3] == (1, 0), note)


main()
