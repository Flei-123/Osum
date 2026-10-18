#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/themeboot/oldhook.py <new wlibc.fi> <old wlibc.fi> -- put the r1123 test hook (conf_flaky) into the OLD wlibc, so the
# counter-probe tree reads /etc/theme.conf the old way (keys from one read, the copy from a second read) and fails the same reads.
import sys
new = open(sys.argv[1], encoding="latin1").read()
a = new.index("// TEST HOOK (tools/themeboot)")
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
o2 = "    let fd: u64 = io.open((&p_conf[0 as usize]) as u64, 0)\n    if !ulib.bad(fd) {\n        let r: u64 = io.read(fd, (&buf[0 as usize]) as u64, 511)"
assert s.count(o2) == 1, "conf_changed read anchor"
s = s.replace(o2, o2.replace("if !ulib.bad(fd) {", "if !ulib.bad(fd) && !conf_flaky() {"), 1)
open(path, "w", encoding="latin1").write(s)
print("old wlibc patched")
