# SPDX-License-Identifier: GPL-2.0-only
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import symjoin


def main(argv):
    if len(argv) != 2:
        print("usage: mksymbol.py <bundle-dir> <out>", file=sys.stderr)
        return 2
    bundle, out = argv
    if os.path.isfile(os.path.join(bundle, "symbol.osym")):
        with open(out, "wb") as handle:
            handle.write(symjoin.joined(bundle))
        return 0
    return subprocess.run([sys.executable, os.path.join(HERE, "icon.py"),
                           os.path.join(bundle, "symbol.txt"), out]).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
