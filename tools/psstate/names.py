import re
import sys

sched = open(sys.argv[1], encoding="latin-1").read()
names_src = open(sys.argv[2], encoding="latin-1").read()
consts = {m.group(1): int(m.group(2)) for m in re.finditer(r"^const (S_[A-Z]+): u64 = (\d+)", sched, re.M)}
literal = re.search(r'static mut NAMES: \[u8; (\d+)\] = "([^"]*)"', names_src)
if not literal:
    sys.exit("NAMES literal not found")
names = [n.strip() for n in literal.group(2).split("\\0") if n != ""]
if int(literal.group(1)) != len(names) * 8:
    sys.exit("table size does not match entry count")
count = re.search(r"const COUNT: u64 = (\d+)", names_src)
if not count or int(count.group(1)) != len(names):
    sys.exit("COUNT does not match the table")
if max(consts.values()) + 1 != len(names):
    sys.exit("table has %d entries, scheduler has %d states" % (len(names), max(consts.values()) + 1))
if len(set(names)) != len(names):
    sys.exit("duplicate state name")
for const, value in consts.items():
    expected = const[2:].lower()
    if expected == "reaping":
        expected = "reap"
    if names[value] != expected:
        sys.exit("state %d (%s) is named %s" % (value, const, names[value]))
print("ok", len(names))
