import os
import re
import sys

GUI_IMPORT = re.compile(
    rb"^import +(wlibc|wlib|fuiscene|fuib|fuiapp|fui\.[a-z]+|softui|wmplug|wmd)\b", re.M
)
FORBIDDEN = re.compile(rb"(?<![\w.])ulib\.(say|sayn|sayu|nl|say_line)\(")
USES_LINEOUT = re.compile(rb"(?<![\w.])lineout\.add_(text|num|unum)\(")
ENDS_LINE = re.compile(rb"(?<![\w.])lineout\.(end_line|flush)\(|\\n")
SKIP = {"kernel/user/lineout.fi"}


def targets(root):
    found = []
    user = os.path.join(root, "kernel/user")
    for name in sorted(os.listdir(user)):
        if not name.endswith(".fi"):
            continue
        rel = "kernel/user/" + name
        with open(os.path.join(root, rel), "rb") as fh:
            data = fh.read()
        if GUI_IMPORT.search(data):
            found.append(rel)
    extra = os.path.join(root, "tools/lineout/extra.txt")
    if os.path.exists(extra):
        with open(extra) as fh:
            for line in fh:
                line = line.strip()
                if line and line not in found:
                    found.append(line)
    return [t for t in found if t not in SKIP]


def lint(root):
    bad = []
    for rel in targets(root):
        with open(os.path.join(root, rel), "rb") as fh:
            lines = fh.read().split(b"\n")
        uses = False
        ends = False
        for number, line in enumerate(lines, 1):
            if FORBIDDEN.search(line):
                bad.append("%s:%d: piecewise serial write: %s" % (rel, number, line.strip().decode("latin-1")))
            if USES_LINEOUT.search(line):
                uses = True
            if ENDS_LINE.search(line):
                ends = True
        if uses and not ends:
            bad.append("%s: lineout pieces without end_line/flush" % rel)
    return bad


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    bad = lint(root)
    for entry in bad:
        print("FAIL", entry)
    print("lineout-lint: %d programs checked, %d violations" % (len(targets(root)), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
