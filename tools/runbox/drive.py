#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/runbox/drive.py -- event driven Win+R scenario through QMP (no fixed waits for results).

    drive.py <qmp-socket> <serial.txt> <outdir> [ready-timeout-seconds]

Win+R -> wait `runbox: ready` -> type `echo hi` + Enter -> wait `runbox: exec /bin/echo pid=`
Win+R -> wait the second `runbox: ready` -> type `nope` + Enter -> wait `runbox: fail /bin/nope` -> Esc.
Writes `scenes.txt` (key=value). A step that never happens is recorded as 0 after its timeout (the old tree has no dialog).
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


def type_text(q, text):
    for ch in text:
        q.tap(KEYNAMES.get(ch, ch))
        time.sleep(0.2)


def main():
    qmp_path, ser, out = sys.argv[1:4]
    tmo = float(sys.argv[4]) if len(sys.argv) > 4 else 40.0
    q = ad.Qmp(qmp_path)
    facts = []
    pos, _ = ad.wait_for(ser, r"eingabe: ber=", 0, 90)
    time.sleep(1.0)
    q.tap("shift")
    time.sleep(1.0)

    def count(p):
        return len(re.findall(p, ad.serial_text(ser)))

    q.tap("meta_l", "r")
    end = time.time() + tmo
    while time.time() < end and count(r"runbox: ready") < 1:
        time.sleep(0.2)
    ready1 = count(r"runbox: ready")
    facts.append(f"ready1={ready1}")
    if ready1:
        time.sleep(1.0)
        type_text(q, "echo hi")
        pos = len(ad.serial_text(ser))
        q.tap("ret")
        _, m = ad.wait_for(ser, r"runbox: exec /bin/echo pid=", pos, 25)
        facts.append(f"exec_echo={1 if m else 0}")
        time.sleep(1.0)
        q.tap("meta_l", "r")
        end = time.time() + tmo
        while time.time() < end and count(r"runbox: ready") < 2:
            time.sleep(0.2)
        facts.append(f"ready2={1 if count(r'runbox: ready') >= 2 else 0}")
        time.sleep(1.0)
        type_text(q, "nope")
        pos = len(ad.serial_text(ser))
        q.tap("ret")
        _, m = ad.wait_for(ser, r"runbox: fail /bin/nope", pos, 25)
        facts.append(f"fail_nope={1 if m else 0}")
        time.sleep(1.0)
        q.tap("esc")
        time.sleep(1.5)
        # ---- X1 history: third dialog; Up -> the last started command (the failed `nope` is not in it), Up again -> nothing older,
        # Down -> the draft (empty), Up + Enter -> starts echo again
        q.tap("meta_l", "r")
        end = time.time() + tmo
        while time.time() < end and count(r"runbox: ready") < 3:
            time.sleep(0.2)
        facts.append(f"ready3={1 if count(r'runbox: ready') >= 3 else 0}")
        time.sleep(1.0)
        pos = len(ad.serial_text(ser))
        q.tap("up")
        _, m = ad.wait_for(ser, r"runbox: recall 1 echo hi", pos, 15)
        facts.append(f"recall_up={1 if m else 0}")
        pos = len(ad.serial_text(ser))
        q.tap("up")
        time.sleep(1.5)
        facts.append(f"recall_older={1 if re.search(r'runbox: recall 2', ad.serial_text(ser)) else 0}")
        pos = len(ad.serial_text(ser))
        q.tap("down")
        _, m = ad.wait_for(ser, r"runbox: recall draft", pos, 15)
        facts.append(f"recall_draft={1 if m else 0}")
        time.sleep(0.5)
        q.tap("up")
        time.sleep(1.0)
        pos = len(ad.serial_text(ser))
        q.tap("ret")
        _, m = ad.wait_for(ser, r"runbox: exec /bin/echo pid=", pos, 25)
        facts.append(f"exec_echo_again={1 if m else 0}")
        time.sleep(1.0)
    t = ad.serial_text(ser)
    facts.append(f"exec_nope={1 if 'runbox: exec /bin/nope' in t else 0}")
    open(out + "/scenes.txt", "w").write("\n".join(facts) + "\n")
    print("\n".join(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
