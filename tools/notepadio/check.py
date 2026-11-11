#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def events(serial):
    return [m.group(1).strip() for m in re.finditer(r"(?m)^notepad: ([^\r\n]*)", serial)]


def has(evs, prefix, *needles):
    return any(e.startswith(prefix) and all(n in e.split() for n in needles) for e in evs)


def index(evs, prefix, *needles):
    for i, e in enumerate(evs):
        if e.startswith(prefix) and all(n in e.split() for n in needles):
            return i
    return -1


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    evs = events(serial)
    verdict("ready_line", has(evs, "ready", "rows=1"))
    verdict("typed_dirty", has(evs, "state", "len=5", "dirty=1"))
    verdict("shortcut_export", has(evs, "shortcut", "key=5"))
    verdict("shortcut_import", has(evs, "shortcut", "key=15"))
    verdict("exported_ok", has(evs, "exported", "name=note.txt", "status=0", "len=5"), str([e for e in evs if e.startswith("exported")][:2]))
    saved_first = index(evs, "saved", "id=1", "status=0", "len=5")
    imported = index(evs, "imported", "name=note.txt", "status=0", "len=5")
    verdict("autosave_before_import", 0 <= saved_first < imported, str([e for e in evs if e.startswith("saved")][:3]))
    verdict("imported_ok", imported >= 0, str([e for e in evs if e.startswith("imported")][:3]))
    verdict("imported_saved", has(evs, "saved", "id=2", "status=0", "len=5", "title=alpha"))
    verdict("imported_state", has(evs, "state", "row=1", "id=2", "len=5", "dirty=0"))
    cancelled = [e for e in evs if e.startswith("imported name=-")]
    verdict("import_cancel", bool(cancelled) and "status=0" not in cancelled[-1].split(), str(cancelled[-1:]))
    picks = re.findall(r"(?m)^explorer: pick answer=(\d+) name=(\S*) len=(\d+)", serial)
    verdict("picker_exported", any(a == "1" and n == "note.txt" and l == "0" for a, n, l in picks), str(picks))
    verdict("picker_imported", any(a == "1" and n == "note.txt" and l == "5" for a, n, l in picks), str(picks))
    verdict("picker_cancelled", any(a == "0" for a, n, l in picks), str(picks))
    verdict("no_surface_absent", "no surface" not in evs)


main()
