#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/work-patch.py -- $OSUM_WORK einbauen.
#
# GEFUNDEN BEIM MESSEN, und zwar auf die unangenehme Art: zwei Abnahmen
# aus DEMSELBEN Arbeitsbaum gleichzeitig (einmal tcg, einmal kvm)
# schreiben beide nach .test-work/<name>.log. Der zweite Lauf ueberschreibt
# das Protokoll, das der erste gleich noch auswerten will -- und die
# Bilanz zaehlt dann fremde Zahlen.
#
# Seriell oder parallel spielt dabei keine Rolle; es ist die Zahl der
# ABNAHMEN, nicht die der Abschnitte. Der Ausweg ist eine Zeile:
#
#     WORK="${OSUM_WORK:-$ROOT/.test-work}"
#
# Damit laeuft
#     OSUM_WORK=.mess/tcg  OSUM_ACCEL=tcg ./test.sh &
#     OSUM_WORK=.mess/kvm  OSUM_ACCEL=kvm ./test.sh &
# nebeneinander, ohne dass sich die beiden ins Protokoll schreiben.

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
