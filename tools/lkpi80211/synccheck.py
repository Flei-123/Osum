import re
import sys

header = open(sys.argv[1]).read()
firn = open(sys.argv[2]).read()

prefixes = {"MACPLAN_OP_": "OP_", "MACPLAN_KEY_": "KEY_", "MACPLAN_BSS_": "BSS_", "MACPLAN_CFG_": "CFG_"}
checked = 0
bad = 0
for name, value in re.findall(r"#define (MACPLAN_[A-Z_0-9]+) (\S+)", header):
    for prefix, firn_prefix in prefixes.items():
        if not name.startswith(prefix):
            continue
        if name in ("MACPLAN_OP_MASK",):
            continue
        firn_name = firn_prefix + name[len(prefix):]
        match = re.search(r"^const %s: u64 = (\S+)$" % firn_name, firn, re.M)
        if not match or int(match.group(1), 0) != int(value, 0):
            print("mismatch", name, value, match and match.group(1))
            bad += 1
        checked += 1
print("checked", checked)
sys.exit(1 if bad or checked < 25 else 0)
