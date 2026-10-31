#!/usr/bin/env bash
#
# ==================================================================
# SO WIRD GEMESSEN
# ==================================================================
#
#   2. Kernelzeile:
#
#        acpiev evdump evself
#
#        acpiev: ready=1 why=0 sci=9 gpearm=N meth=M lid=L batt=B ...
#
#        acpiev: gpe b=0x1B art=0 on=1
#
#   5. NOW OPERATE THE HARDWARE, and after every step look at the
#      report line (with `evdump` it comes by itself every 200 passes):
#
#      a) CLOSE THE LID.      Expected: a line
#                             `acpiev: ev gpe b=0x..`, then
#                             `acpiev: lid closed -- locked`, and the
#                             lock screen on the display.
#                             `lid=` must jump from 1 to 0.
#      b) OPEN THE LID.       `lid=` back to 1. NOT unlocked --
#                             that is intended.
#      c) UNPLUG THE ADAPTER. `ac=` from 1 to 0, and `ev=` rises.
#      d) PLUG THE ADAPTER IN. `ac=` back to 1.
#      e) PRESS THE POWER BUTTON SHORTLY (do not hold!).
#                             `acpiev: ev taste`, `irqs=` rises,
#                             `sts=` has bit 8 (0x0100).
#                             The energy menu must open.
#      f) LET IT RUN FOR A QUARTER OF AN HOUR, do nothing.
#                             `irqs=` must NOT rise without bound.
#                             THIS IS THE STORM PROBE: if it rises by
#                             thousands per second, a status bit is
#                             not being cleared, and `kernel/hw.fi`
#                             has warned of exactly that since round
#                             BLECHVIER.
#                             Then: put `noacpiev` on the kernel line
#                             and send the `gpe b=` lines of the run
#                             here.
#
#     python3 tools/aml/disasm.py ns   TABELLE.bin
#     python3 tools/aml/pflichtenheft.py TABELLE.bin
#
set -uo pipefail
cd "$(dirname "$0")/../.."

echo "Diese Datei ist eine ANLEITUNG und kein Testlauf."
echo "Sie beschreibt, was auf echter Hardware nachzumessen ist."
echo
echo "Kernelzeile:   acpiev evdump evself"
echo "Bei Verdacht:  acpiev amldump   (Tabellen auf die Leitung)"
echo
echo "Die Schritte stehen im Kopf dieser Datei:"
sed -n '/^# *5\. JETZT DIE HARDWARE/,/^# *6\./p' "$0" | sed 's/^# \{0,1\}//'
