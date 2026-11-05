import os
import re
import sys

SKIP_DIRS = {"pidkill", "__pycache__", ".git"}
PATTERNS = [
    re.compile(r"\b(?:p" + "kill|kill" + r"all)\b"),
    re.compile(r"kill\b.*\$\(\s*pgrep\s+-[a-zA-Z]*f"),
    re.compile(r"\$\(\s*pgrep\s+-[a-zA-Z]*f\b.*\bkill\b"),
    re.compile(r"\bpgrep\s+-[a-zA-Z]*f\b.*\|\s*xargs\s+kill"),
]


def scan(root):
    hits = []
    base = os.path.join(root, "tools")
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    lines = handle.read().splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            for number, line in enumerate(lines, 1):
                if any(p.search(line) for p in PATTERNS):
                    hits.append("%s:%d: %s" % (os.path.relpath(path, root), number, line.strip()))
    return hits


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    hits = scan(root)
    for hit in hits:
        print(hit)
    print("%d name-based kills" % len(hits))
    return 1 if hits else 0


sys.exit(main())
