#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import subprocess
import sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
new = subprocess.run(["bash", os.path.join(root, "tools/structure/srcview.sh"), os.path.abspath(sys.argv[1])], capture_output=True, check=True).stdout.decode("latin1")
a = new.index("static mut flaky_left")
b = new.index("fn conf_read_into")
hook = new[a:b]
path = sys.argv[2]
s = open(path, encoding="latin1").read()
anchor = "fn conf_changed() -> bool {"
assert s.count(anchor) == 1, "conf_changed anchor"
s = s.replace(anchor, hook + anchor, 1)
o1 = "        nc = kv_read((&p_conf[0 as usize]) as u64, 1)\n"
assert s.count(o1) == 1, "reload anchor"
s = s.replace(o1, "        if conf_flaky() {\n            nc = 0\n        } else {\n            nc = kv_read((&p_conf[0 as usize]) as u64, 1)\n        }\n", 1)
open(path, "w", encoding="latin1").write(s)
print("old wlibc patched")
