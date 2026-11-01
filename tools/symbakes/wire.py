#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

root = sys.argv[1]


def rd(path):
    t = open(os.path.join(root, path), "rb").read().decode("latin1")
    d = os.path.join(root, path[:-3])
    if os.path.isdir(d):
        t += "".join(open(os.path.join(d, f), "rb").read().decode("latin1") for f in sorted(os.listdir(d)) if f.endswith(".fi"))
    return t


checks = [
    ("taskmgr: slot holds the 72/44/64 pictures", "const ICO_BYTES: u64 = 44900" in rd("kernel/user/taskmgr.fi")),
    ("taskmgr: row icon slot registered with symvar", "symvar.register(out, got)" in rd("kernel/user/taskmgr.fi")),
    ("taskbar: slot holds the 72/44/64 pictures", "const SYM_BYTES: u64 = 44900" in rd("kernel/user/taskbar.fi")),
    ("taskbar: symbol slot registered with symvar", "symvar.register(target, got)" in rd("kernel/user/taskbar/tblayout.fi")),
    ("taskbar: button symbol drawn from symvar.pick", "icon_draw_fit(symvar.pick(sym, symw)" in rd("kernel/user/taskbar.fi")),
    ("fuiscene: icon_at (start menu tiles) picks the bake", "symvar.pick(word, size)" in rd("kernel/user/fuiscene/fsdraw.fi")),
    ("jarvismini: image carries the joined symbol", "$OUT/jarvismini.symbol@0644" in rd("tools/usbimg/build.sh")),
]
bad = 0
for text, ok in checks:
    print(("  OK    " if ok else "  FAIL  ") + text)
    bad += 0 if ok else 1
print("WIRE: %d red" % bad)
sys.exit(1 if bad else 0)
