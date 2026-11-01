#!/usr/bin/env python3

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "test.sh"

ALT = 'WORK="$ROOT/.test-work"\nmkdir -p "$WORK"\n'
NEW = ('# Where the logs of each section go. Overridable so two\n'
       '# acceptance runs (e.g. tcg and kvm) do not overwrite each\n'
       '# other logs.\n'
       'WORK="${OSUM_WORK:-$ROOT/.test-work}"\n'
       'mkdir -p "$WORK"\n')


def main():
    t = TEST.read_text()
    if "OSUM_WORK" in t:
        print("test.sh already knows OSUM_WORK")
        return 0
    if ALT not in t:
        print("ERROR: I do not see the WORK line", file=sys.stderr)
        return 1
    TEST.write_text(t.replace(ALT, NEW, 1))
    print("test.sh: WORK can now be redirected with $OSUM_WORK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
