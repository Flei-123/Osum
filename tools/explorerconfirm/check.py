#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

WAIT_TRASH = "wait=3"


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def lines(path):
    serial = open(path, "rb").read().decode("latin-1")
    return [m.group(1).strip() for m in re.finditer(r"explorer: ([^\r\n]*)", serial)]


def index_of(evs, prefix, start=0, *needles):
    for i in range(start, len(evs)):
        if evs[i].startswith(prefix) and all(n in evs[i] for n in needles):
            return i
    return -1


def trashed(evs, start):
    return index_of(evs, "tat 3 n=1 rc=0", max(start, 0)) >= 0


def check_service(evs):
    cancel = index_of(evs, "confirm delete", 0, "status=0", WAIT_TRASH, "answer=0", "go=0")
    accept = index_of(evs, "confirm delete", max(cancel, 0), "status=0", WAIT_TRASH, "answer=1", "go=1")
    verdict("confirm_cancel", cancel >= 0, str([e for e in evs if e.startswith("confirm delete")][:3]))
    verdict("confirm_accept", accept >= 0)
    between = [e for e in evs[max(cancel, 0):max(accept, 0)] if e.startswith("tat ")]
    verdict("cancel_keeps_file", cancel >= 0 and accept > cancel and not between)
    verdict("accept_trashes", accept >= 0 and trashed(evs, accept), str([e for e in evs[max(accept, 0):] if e.startswith("tat ")][:2]))
    verdict("no_scene_dialog_with_service", cancel >= 0 and index_of(evs, "dlgrect") < 0)


def check_fallback(evs):
    ask = index_of(evs, "confirm delete", 0, "go=2")
    scene = index_of(evs, "dlgrect", max(ask, 0))
    verdict("fallback_verdict", ask >= 0, str([e for e in evs if e.startswith("confirm delete")][:3]))
    verdict("fallback_scene_dialog", ask >= 0 and scene > ask)
    verdict("fallback_trashes", ask >= 0 and trashed(evs, ask), str([e for e in evs[max(ask, 0):] if e.startswith("tat ")][:2]))


def main():
    mode = sys.argv[1]
    evs = lines(sys.argv[2])
    verdict("explorer_ready", index_of(evs, "ready") >= 0)
    verdict("no_surface_absent", "no surface" not in evs)
    if mode == "service":
        check_service(evs)
    else:
        check_fallback(evs)


main()
