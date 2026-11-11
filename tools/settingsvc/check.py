#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

PAGE_THEMES = "7"


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def lines(serial):
    return [m.group(1).strip() for m in re.finditer(r"settings: ([^\r\n]*)", serial)]


def index_of(evs, prefix, start=0, *needles):
    for i in range(start, len(evs)):
        if evs[i].startswith(prefix) and all(n in evs[i] for n in needles):
            return i
    return -1


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    evs = lines(serial)
    readies = [i for i, e in enumerate(evs) if e.startswith("ready")]
    saved = index_of(evs, "page saved", 0, "page=" + PAGE_THEMES, "status=0")
    cancel = index_of(evs, "confirm uninstall", 0, "status=0", "answer=0", "go=0")
    accept = index_of(evs, "confirm uninstall", max(cancel, 0), "status=0", "answer=1", "go=1")
    restored = index_of(evs, "page restored", 0, "page=" + PAGE_THEMES)
    verdict("ready_twice", len(readies) >= 2, str(len(readies)))
    verdict("fresh_start_no_restore", restored < 0 or saved < 0 or restored > saved)
    verdict("page_saved", saved >= 0, str([e for e in evs if e.startswith("page saved")][:3]))
    verdict("confirm_cancel", cancel >= 0, str([e for e in evs if e.startswith("confirm uninstall")][:3]))
    verdict("confirm_accept", accept >= 0)
    between = [e for e in evs[max(cancel, 0):max(accept, 0)] if e.startswith("apps uninstall ")]
    verdict("cancel_keeps_app", cancel >= 0 and accept > cancel and not between)
    after = [e for e in evs[max(accept, 0):] if e.startswith("apps uninstall ")]
    verdict("accept_uninstalls", accept >= 0 and len(after) > 0, str(after[:2]))
    verdict("page_restored", restored >= 0 and saved >= 0 and restored > saved)
    nav = index_of(evs, "nav route=", max(restored, 0), "page=" + PAGE_THEMES)
    verdict("reopened_on_page", restored >= 0 and nav > restored)
    verdict("no_surface_absent", "no surface" not in evs)


main()
