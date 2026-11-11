#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def events(serial):
    return [m.group(1).strip() for m in re.finditer(r"svcedit: ([^\r\n]*)", serial)]


def after(evs, prefix, nxt):
    for i, e in enumerate(evs):
        if e.startswith(prefix):
            for f in evs[i + 1:]:
                if f.startswith("state "):
                    return nxt in f
    return False


def find(evs, prefix, *needles):
    return any(e.startswith(prefix) and all(n in e for n in needles) for e in evs)


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    evs = events(serial)
    verdict("ready_line", "ready" in evs)
    verdict("typed_dirty", find(evs, "state ", "len=5", "dirty=1"))
    verdict("shortcut_save", "shortcut key=19" in evs)
    verdict("shortcut_new", "shortcut key=305" in evs)
    verdict("saved_ok", find(evs, "saved name=", "status=0", "len=5"), str([e for e in evs if e.startswith("saved")][:2]))
    verdict("saved_clean", after(evs, "saved name=", "dirty=0"))
    verdict("confirm_cancel", find(evs, "confirm status=", "status=0", "answer=0"))
    verdict("confirm_accept", find(evs, "confirm status=", "status=0", "answer=1"))
    verdict("cancel_keeps_text", find(evs, "state ", "len=6", "dirty=1"))
    verdict("new_cleared", after(evs, "new", "len=0"))
    verdict("open_ok", find(evs, "open name=", "status=0", "len=5"), str([e for e in evs if e.startswith("open")][:2]))
    verdict("recent_set", any(e.startswith("recent=") for e in evs))
    picks = re.findall(r"(?m)^explorer: pick answer=(\d+) name=(\S*) len=(\d+)", serial)
    verdict("picker_saved", any(a == "1" and n == "untitled.txt" and l == "0" for a, n, l in picks), str(picks))
    verdict("picker_opened", any(a == "1" and n == "untitled.txt" and l == "5" for a, n, l in picks), str(picks))
    verdict("no_surface_absent", "no surface" not in evs)


main()
