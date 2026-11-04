import re
import subprocess
import sys

BINARIES = ["libxul.so", "firefox-esr", "libmozsandbox.so", "libnspr4.so", "libnss3.so", "libmozgtk.so"]
PREFIXES = ("pthread_", "sem_", "sched_", "__pthread")
ALIASES = {"pthread_once": "once_call", "sched_yield": "yield_now"}


def imported(root):
    names = set()
    for name in BINARIES:
        out = subprocess.run(["nm", "-D", "--undefined-only", root + "/" + name], capture_output=True, text=True).stdout
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1].split("@")[0].startswith(PREFIXES):
                names.add(parts[1].split("@")[0])
    return names


def exported(source):
    text = open(source).read()
    body = re.search(r"export \{(.*?)\}", text, re.S).group(1)
    return {item.strip() for item in body.replace("\n", " ").split(",") if item.strip()}


def local_name(symbol):
    if symbol in ALIASES:
        return ALIASES[symbol]
    if symbol.startswith("pthread_"):
        return symbol[len("pthread_"):]
    return symbol


def main():
    root, source, gap_file = sys.argv[1:4]
    have = exported(source)
    missing = sorted(s for s in imported(root) if local_name(s) not in have)
    expected = sorted(l.strip() for l in open(gap_file) if l.strip())
    print("imported pthread surface missing: %d (gap file: %d)" % (len(missing), len(expected)))
    if missing != expected:
        print("new:", sorted(set(missing) - set(expected)))
        print("fixed:", sorted(set(expected) - set(missing)))
        return 1
    return 0


sys.exit(main())
