import sys

sys.path.insert(0, "tools/kdatalayout")
import check

MUTANTS = [
    ("pmon tables packed for 256 tasks", "kernel/pwr/pmon.fi",
     "const BUCKETS: u64 = TASKS + kstate.MAX_TASKS * TBYTES", "const BUCKETS: u64 = 0x6200"),
    ("netmon tables packed for 256 tasks", "kernel/net/netmon.fi",
     "const SOCKS: u64 = TASKS + kstate.MAX_TASKS * TBYTES", "const SOCKS: u64 = 0x6080"),
]


def main(root):
    missed = 0
    for name, path, old, new in MUTANTS:
        with open(f"{root}/{path}") as handle:
            text = handle.read()
        if old not in text:
            print(f"  FAIL  mutant source line gone: {name}")
            missed += 1
            continue
        _, issues = check.check(root, {path: text.replace(old, new)})
        if issues:
            print(f"  OK    counter-proof detected: {name}")
        else:
            print(f"  FAIL  counter-proof missed: {name}")
            missed += 1
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
