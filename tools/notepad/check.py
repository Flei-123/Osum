#!/usr/bin/env python3
import re
import sys


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def events(serial):
    return [m.group(1).strip() for m in re.finditer(r"notepad: ([^\r\n]*)", serial)]


def has(evs, prefix, *needles):
    return any(e.startswith(prefix) and all(n in e.split() for n in needles) for e in evs)


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    evs = events(serial)
    readies = [i for i, e in enumerate(evs) if e.startswith("ready")]
    verdict("ready_first", has(evs, "ready", "rows=1"))
    verdict("typed_dirty", has(evs, "state", "len=1", "dirty=1"))
    verdict("shortcut_save", has(evs, "shortcut", "key=19"))
    verdict("shortcut_new", has(evs, "shortcut", "key=305"))
    verdict("shortcut_delete", has(evs, "shortcut", "key=4"))
    verdict("saved_first", has(evs, "saved", "id=1", "status=0", "len=5", "title=alpha"))
    verdict("new_second", has(evs, "new", "id=2", "rows=2"))
    verdict("saved_second", has(evs, "saved", "id=2", "status=0", "len=4", "title=beta"))
    verdict("select_first", has(evs, "select", "row=0", "id=1", "len=5"))
    verdict("autosave", has(evs, "saved", "id=1", "status=0", "len=6", "title=alphax"))
    verdict("select_second", has(evs, "select", "row=1", "id=2", "len=4"))
    verdict("delete_cancel", has(evs, "delete", "status=0", "answer=0", "rows=2"))
    verdict("delete_accept", has(evs, "delete", "status=0", "answer=1", "rows=1"))
    again = evs[readies[1]:] if len(readies) > 1 else []
    verdict("persisted_rows", len(readies) > 1 and "ready rows=1" in again[0])
    verdict("persisted_note", has(again, "select", "row=0", "id=2", "len=4"))
    rows = [dict(f.split("=") for f in e.split()[1:]) for e in evs if e.startswith("list ")]
    scaled = bool(rows) and int(rows[0]["rowh"]) == (28 * int(rows[0]["scale"]) + 500) // 1000
    verdict("list_row_scaled", scaled, rows[0]["rowh"] if rows else "missing")
    verdict("no_surface_absent", "no surface" not in evs)


main()
