#!/usr/bin/env python3

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "test.sh"

ALT = 'WORK="$ROOT/.test-work"\nmkdir -p "$WORK"\n'
NEU = ('# Wohin die Protokolle je Abschnitt gehen. Ueberschreibbar, damit\n'
       '# ZWEI Abnahmen (z. B. eine unter tcg und eine unter kvm) sich\n'
       '# nebeneinander nicht die Protokolle ueberschreiben -- gefunden\n'
       '# beim Messen dieser Runde, siehe tools/lib/work-patch.py.\n'
       'WORK="${OSUM_WORK:-$ROOT/.test-work}"\n'
       'mkdir -p "$WORK"\n')


def main():
    t = TEST.read_text()
    if "OSUM_WORK" in t:
        print("test.sh kennt OSUM_WORK schon")
        return 0
    if ALT not in t:
        print("FEHLER: die WORK-Zeile sehe ich nicht", file=sys.stderr)
        return 1
    TEST.write_text(t.replace(ALT, NEU, 1))
    print("test.sh: WORK laesst sich jetzt mit $OSUM_WORK umlenken")
    return 0


if __name__ == "__main__":
    sys.exit(main())
