#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/themeboot/oldhook.py <new wlibc.fi> <old wlibc.fi> -- put the r1123 test hook (conf_flaky) into the OLD wlibc, so the
# counter-probe tree reads /etc/theme.conf the old way (keys from one read, the copy from a second, good read) and fails the key reads.
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
# NOTE (r1171): the compare-copy read at the end of the old `reload_inner` (`conf_changed`) is deliberately NOT hooked. The old bug
# is "keys from a failing read, compare-copy from a GOOD read": the copy then equals the file, no poll ever sees a change and
# the dark start stays. The counter-probe tree must therefore fail only the KEY reads (flaky=2: the old taskbar/desktop reload
# twice at boot, a single failing key read heals itself with the second reload, measured with debug lines on f2feb2e0).
open(path, "w", encoding="latin1").write(s)
print("old wlibc patched")
