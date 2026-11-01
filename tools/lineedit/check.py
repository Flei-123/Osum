#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

LONG = "abcdefghij" * 11
COMMANDS = ["echo first", "echo alpha", "echo ZalhaQ", "echo draft", "echo one w3", "echo uu", "echo aex",
            "echo cc yddk", "echo kk", "echo W" + LONG] + ["echo h%02d" % i for i in range(1, 27)]
HIST_MAX = 32
PROMPT = "osum$ "


def snapshots(path):
    snaps = []
    cur = None
    for z in open(path, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: termwin win=(\d+) tty=(\d+) focus=(\d) cols=(\d+) rows=(\d+) x=(\d+) y=(\d+)"
                     r"(?: ccx=(\d+) ccy=(\d+))?", z)
        if m:
            slot = int(m.group(1))
            if cur is None or slot in cur:
                cur = {}
                snaps.append(cur)
            cur[slot] = {"focus": int(m.group(3)), "cols": int(m.group(4)), "rows": {},
                         "cx": int(m.group(8) or -1), "cy": int(m.group(9) or -1)}
            continue
        m = re.match(r"wm: tw(\d+) (\d+) \[(.*)\]\s*$", z)
        if m and cur is not None and int(m.group(1)) in cur:
            cur[int(m.group(1))]["rows"][int(m.group(2))] = m.group(3)
    wins = []
    for sn in snaps:
        for w in sn.values():
            if w["focus"] == 1:
                wins.append(w)
    return wins


def row(w, r):
    return w["rows"].get(r, "").rstrip()


def outputs(path):
    txt = open(path, "rb").read().decode("latin1")
    return [z.rstrip("\r").strip() for z in txt.split("\n")]


def main(path):
    wins = snapshots(path)
    bad = 0

    def check(ok, msg):
        nonlocal bad
        print(("  OK    " if ok else "  FAIL  ") + msg)
        if not ok:
            bad += 1
    print("%d focused terminal snapshot(s)" % len(wins))
    check(len(wins) > 0, "the terminal window cells are dumped on the serial line")
    check(any(w["cx"] >= 0 for w in wins), "the dump carries the cursor cell (ccx/ccy)")

    def state(name, line, col, above=None, below_empty=False, top=False):
        hit = None
        for w in wins:
            cy = w["cy"]
            if row(w, cy) != line or w["cx"] != col:
                continue
            if above is not None and row(w, cy - 1) != above:
                continue
            if below_empty and row(w, cy + 1) != "":
                continue
            if top and cy != 0:
                continue
            hit = w
        check(hit is not None, "%s: cursor row shows %r, cursor at column %d" % (name, line, col))
        return hit

    state("Up recalls the previous command VISIBLY", PROMPT + "echo alpha", 16, above="alpha")
    state("Left x3 + insert in the middle", PROMPT + "echo alXpha", 14)
    state("Delete under the cursor + Backspace before it", PROMPT + "echo alha", 13)
    state("Home, Right x5, insert, End", PROMPT + "echo Zalha", 16)
    state("Up while typing a draft shows the history entry", PROMPT + "echo ZalhaQ", 17, above="ZalhaQ")
    state("Down past the newest entry restores the draft", PROMPT + "echo draft", 16, above="ZalhaQ")

    full = PROMPT + "echo W" + LONG
    cols = max([w["cols"] for w in wins] or [0])
    if cols and len(full) > cols:
        hit = None
        for w in wins:
            cy = w["cy"]
            got = "".join(w["rows"].get(cy + k, "").ljust(cols) for k in range(len(full) // cols + 1)).rstrip()
            if got == full and w["cx"] == 12:
                hit = w
        check(hit is not None, "insert at the start of a line wrapped at the right edge (%d cols): rows redrawn, cursor kept" % cols)
    else:
        check(False, "wrap case not reached: line %d cells, window %d cols" % (len(full), cols))
    state("long wrapped line -> shorter entry: the second row is erased", PROMPT + "echo kk", 13, below_empty=True)
    oldest = COMMANDS[len(COMMANDS) - HIST_MAX]
    state("Up x40 with %d entries stops at the oldest kept (%d)" % (len(COMMANDS), HIST_MAX), PROMPT + oldest, 6 + len(oldest))
    state("Ctrl+L clears the screen and redraws the line at the top", PROMPT + "echo ll", 13, top=True)

    out = outputs(path)
    cells = [row(w, r) for w in wins for r in w["rows"]]
    for c in COMMANDS[:9] + ["echo h01", "echo h26", "echo ll"]:
        want = c[5:]
        check(want in out or want in cells, "`%s` ran and printed %r" % (c, want))
    reruns = sum(1 for z in out if z == oldest[5:])
    check(reruns >= 2 or sum(1 for z in cells if z == oldest[5:]) >= 2,
          "Enter on the recalled oldest entry runs it again (%r printed %d times on serial)" % (oldest[5:], reruns))
    wrapped_out = any(("W" + LONG) == z for z in out) or any(
        "".join(w["rows"].get(r, "").ljust(cols) for r in range(i, i + 3)).rstrip().startswith("W" + LONG)
        for w in wins for i in w["rows"] if w["rows"][i].startswith("Wabc"))
    check(wrapped_out, "the edited long line ran with the inserted W")
    check(not any("cannot run" in z for z in out), "no `sh: cannot run`")
    check(not any("\x1b" in z for z in cells), "no ESC byte stands in any cell")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
