#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/cliphist/drive.py -- event driven Win+V scenario through QMP (D-015).

    drive.py <qmp-socket> <serial.txt> <outdir> [timeout-seconds]

Win+R `cliphist put alpha beta gamma` (three bus entries, gamma newest)
Win+V -> rows gamma beta alpha; Tab + Enter -> pick row 1 (beta), the bus head is beta
Win+V -> beta gamma alpha (the second beta is shown once, ring n=4); key 3 -> pick row 2 (alpha)
Win+V -> Down + Enter -> pick row 1; Win+V -> Esc -> closed, nothing picked.
Writes `scenes.txt` (key=value). A step that never happens is recorded as 0 after its timeout (the old tree has no popup).
"""
import importlib.util
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("alttab_drive", os.path.join(HERE, "..", "alttab", "drive.py"))
ad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ad)

KEYNAMES = {" ": "spc"}
ROWS1 = r"cliphist: row 0 gamma\s+cliphist: row 1 beta\s+cliphist: row 2 alpha"
ROWS2 = r"cliphist: row 0 beta\s+cliphist: row 1 gamma\s+cliphist: row 2 alpha"


def type_text(q, text):
    for ch in text:
        q.tap(KEYNAMES.get(ch, ch))
        time.sleep(0.2)


def main():
    qmp_path, ser, out = sys.argv[1:4]
    tmo = float(sys.argv[4]) if len(sys.argv) > 4 else 40.0
    q = ad.Qmp(qmp_path)
    facts = []
    ad.wait_for(ser, r"eingabe: ber=", 0, 90)
    time.sleep(1.0)
    q.tap("shift")
    time.sleep(1.0)

    def text():
        return ad.serial_text(ser)

    def count(p):
        return len(re.findall(p, text()))

    def wait_count(p, n, t):
        end = time.time() + t
        while time.time() < end and count(p) < n:
            time.sleep(0.2)
        return count(p) >= n

    # seed three entries through the Run dialog (the hook of the program itself)
    q.tap("meta_l", "r")
    got = wait_count(r"runbox: ready", 1, tmo)
    facts.append(f"run_ready={1 if got else 0}")
    if got:
        time.sleep(1.0)
        type_text(q, "cliphist put alpha beta gamma")
        q.tap("ret")
        facts.append(f"seed={1 if wait_count(r'cliphist: put n=3', 1, 25) else 0}")
    else:
        facts.append("seed=0")
    time.sleep(1.0)

    def popup(n):
        q.tap("meta_l", "v")
        return wait_count(r"cliphist: ready", n, tmo)

    # 1. open: three rows, newest first
    r1 = popup(1)
    facts.append(f"open1={1 if r1 else 0}")
    time.sleep(1.5)
    t = text()
    facts.append(f"ring3={1 if 'cliphist: ready n=3 shown=3' in t else 0}")
    facts.append("rows1=%d" % (1 if re.search(ROWS1, t) else 0))
    if r1:
        # Tab moves to row 1, Enter picks it
        q.tap("tab")
        time.sleep(0.6)
        q.tap("ret")
        facts.append(f"pick_beta={1 if wait_count(r'cliphist: pick 1 beta', 1, 20) else 0}")
        facts.append(f"head_beta={1 if wait_count(r'cliphist: head beta', 1, 10) else 0}")
        facts.append(f"closed1={1 if wait_count(r'cliphist: closed', 1, 10) else 0}")
    time.sleep(1.0)
    # 2. the picked entry is on top again; the older beta is not shown twice
    r2 = popup(2)
    facts.append(f"open2={1 if r2 else 0}")
    time.sleep(1.5)
    t = text()
    facts.append(f"ring4={1 if 'cliphist: ready n=4 shown=3' in t else 0}")
    facts.append("rows2=%d" % (1 if re.search(ROWS2, t) else 0))
    if r2:
        q.tap("3")
        facts.append(f"pick_digit={1 if wait_count(r'cliphist: pick 2 alpha', 1, 20) else 0}")
        facts.append(f"head_alpha={1 if wait_count(r'cliphist: head alpha', 1, 10) else 0}")
        wait_count(r"cliphist: closed", 2, 10)
    time.sleep(1.0)
    # 3. arrow keys
    r3 = popup(3)
    facts.append(f"open3={1 if r3 else 0}")
    time.sleep(1.5)
    if r3:
        pos = len(text())
        q.tap("down")
        time.sleep(0.6)
        q.tap("ret")
        _, m = ad.wait_for(ser, r"cliphist: pick 1 ", pos, 20)
        facts.append(f"pick_down={1 if m else 0}")
        wait_count(r"cliphist: closed", 3, 10)
    time.sleep(1.0)
    # 4. Esc closes without a pick
    picks = count(r"cliphist: pick ")
    r4 = popup(4)
    facts.append(f"open4={1 if r4 else 0}")
    time.sleep(1.5)
    if r4:
        q.tap("esc")
        wait_count(r"cliphist: closed", 4, 10)
    facts.append(f"esc_nopick={1 if count(r'cliphist: pick ') == picks else 0}")
    open(out + "/scenes.txt", "w").write("\n".join(facts) + "\n")
    print("\n".join(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
