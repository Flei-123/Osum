#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/settingsman/manifest.py -- the second reader of the SETTINGS manifest (docs/SETTINGS-MANIFEST.md).

The first reader is lib/settingsman/manifest.fi (the Settings app). This one is written from the SPEC, not
copied from the Firn code; tools/settingsman/run.sh feeds both the same files and compares the output
(and a golden file per case). Usage: manifest.py < SETTINGS   -> the same text form as dump.fi.
"""
import sys

MAX_ITEMS = 80
MAX_PAGES = 8
POOL_MAX = 3072
TYPES = ["bool", "choice", "text", "secret", "action", "status", "list"]
NAME_CHARS = set(b"abcdefghijklmnopqrstuvwxyz0123456789._-")

E_HEADER, E_APP, E_PAGE, E_DUP_PAGE, E_NO_PAGE, E_ITEM, E_NAME, E_FULL, E_POOL, E_COLUMN, E_DUP_FIELD = range(1, 12)


class Reject(Exception):
    def __init__(self, code, line):
        self.code = code
        self.line = line


def words(raw):
    """Split a line at blanks (space, tab, CR); a word starting with '#' ends the line. Up to 8 words."""
    out = []
    many = False
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c in b" \t\r":
            i += 1
        elif c == 0x23:
            i = n
        else:
            q = i
            while q < n and raw[q] not in b" \t\r":
                q += 1
            if len(out) < 8:
                out.append(raw[i:q])
            else:
                many = True
            i = q
    return out, many


def name_ok(w, maxlen):
    return 0 < len(w) <= maxlen and all(c in NAME_CHARS for c in w)


def parse(data):
    st = 0
    pool = 0
    app = None
    pages = []
    items = []
    warns = 0
    col = 0

    def put(w):
        nonlocal pool
        if pool + len(w) + 1 > POOL_MAX:
            raise Reject(E_POOL, line)
        pool += len(w) + 1
        return w.decode("latin-1")

    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    line = 0
    for raw in lines:
        line += 1
        w, many = words(raw)
        nw = len(w) + (1 if many else 0)
        if not w:
            continue
        if many:
            raise Reject(E_ITEM, line)
        kw = w[0]
        if kw == b"manifest":
            if st != 0 or len(w) != 2 or w[1] != b"1":
                raise Reject(E_HEADER, line)
            st = 1
            continue
        if st == 0:
            raise Reject(E_HEADER, line)
        if kw == b"app":
            if st != 1 or len(w) != 2:
                raise Reject(E_APP, line)
            if not name_ok(w[1], 24):
                raise Reject(E_NAME, line)
            app = put(w[1])
            st = 2
            continue
        if st < 2:
            raise Reject(E_APP, line)
        if kw == b"page":
            if len(w) != 5:
                raise Reject(E_PAGE, line)
            if not all(name_ok(x, 40) for x in w[1:5]):
                raise Reject(E_NAME, line)
            if len(pages) >= MAX_PAGES:
                raise Reject(E_FULL, line)
            vals = [put(x) for x in w[1:5]]
            if any(p["id"] == vals[0] for p in pages):
                raise Reject(E_DUP_PAGE, line)
            pages.append({"id": vals[0], "title": vals[1], "symbol": vals[2], "group": vals[3],
                          "first": len(items), "len": 0})
            col = 0
            continue
        if kw == b"column":
            if not pages:
                raise Reject(E_NO_PAGE, line)
            if len(w) != 2:
                raise Reject(E_COLUMN, line)
            if w[1] == b"left":
                col = 0
            elif w[1] == b"right":
                col = 1
            else:
                raise Reject(E_COLUMN, line)
            continue

        def add(item):
            if len(items) >= MAX_ITEMS:
                raise Reject(E_FULL, line)
            item["col"] = "right" if col else "left"
            items.append(item)
            pages[-1]["len"] += 1

        if kw == b"label":
            if not pages:
                raise Reject(E_NO_PAGE, line)
            if len(w) != 2:
                raise Reject(E_ITEM, line)
            if not name_ok(w[1], 40):
                raise Reject(E_NAME, line)
            add({"kind": "label", "label": put(w[1])})
            continue
        if kw == b"note":
            if not pages:
                raise Reject(E_NO_PAGE, line)
            if not 2 <= len(w) <= 3:
                raise Reject(E_ITEM, line)
            if not name_ok(w[1], 40):
                raise Reject(E_NAME, line)
            lines_n = 1
            if len(w) == 3:
                if len(w[2]) != 1 or not (0x31 <= w[2][0] <= 0x39):
                    raise Reject(E_ITEM, line)
                lines_n = w[2][0] - 0x30
            add({"kind": "note", "label": put(w[1]), "num": lines_n})
            continue
        if kw == b"field":
            if not pages:
                raise Reject(E_NO_PAGE, line)
            if not 3 <= len(w) <= 5:
                raise Reject(E_ITEM, line)
            if not name_ok(w[1], 40):
                raise Reject(E_NAME, line)
            ty = w[2].decode("latin-1")
            if ty not in TYPES:
                warns += 1
                continue
            label = None
            default = None
            if len(w) >= 4:
                if not name_ok(w[3], 40):
                    raise Reject(E_NAME, line)
                label = put(w[3])
            if len(w) == 5:
                default = put(w[4])
            if ty == "action" and label is None:
                raise Reject(E_ITEM, line)
            key = put(w[1])
            first = pages[-1]["first"]
            if any(it["kind"] == "field" and it["key"] == key for it in items[first:]):
                raise Reject(E_DUP_FIELD, line)
            add({"kind": "field", "key": key, "type": ty, "label": label, "def": default})
            continue
        warns += 1
    if st < 2:
        raise Reject(E_HEADER, line)
    return app, pages, items, warns


def dump(data):
    try:
        app, pages, items, warns = parse(data)
    except Reject as r:
        return "error %d line %d\ntables items=0 pages=0\n" % (r.code, r.line)
    out = ["ok app=%s items=%d pages=%d warns=%d" % (app, len(items), len(pages), warns)]
    for p in pages:
        out.append("page %s %s %s %s first=%d len=%d" % (p["id"], p["title"], p["symbol"], p["group"], p["first"], p["len"]))
        for it in items[p["first"]:p["first"] + p["len"]]:
            if it["kind"] == "label":
                out.append("  label %s %s" % (it["col"], it["label"]))
            elif it["kind"] == "note":
                out.append("  note %s %s %d" % (it["col"], it["label"], it["num"]))
            else:
                out.append("  field %s %s %s %s %s" % (it["col"], it["key"], it["type"], it["label"] or "-", it["def"] or "-"))
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    sys.stdout.write(dump(sys.stdin.buffer.read()))
