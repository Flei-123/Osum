#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/verschiebe.sh -- EINE Datei in eine Schicht umziehen.
#
#   bash tools/struktur/verschiebe.sh <modul> <unterordner>
#   z. B.  bash tools/struktur/verschiebe.sh serial arch
#
# Was es tut, und warum es so wenig ist:
#
#   1. `git mv kernel/<modul>.fi kernel/<ordner>/<modul>.fi`
#   2. in JEDER .fi-Datei unter kernel/ die Zeile `import <modul>`
#      durch `import <ordner>.<modul>` ersetzen.
#
# MEHR IST NICHT NOETIG -- und das ist der ganze Grund, aus dem diese
# Runde moeglich war. Firn spricht ein Modul unter dem LETZTEN Teil des
# Pfades an (`/root/firn/compiler/src/modules.rs`, `imp.path.last()`):
# nach `import arch.serial` heisst das Modul weiterhin `serial`, und
# jede der 3000 Aufrufstellen `serial.putc(...)` bleibt Zeichen fuer
# Zeichen stehen.
#
# GEMESSEN, nicht geglaubt: derselbe Kern, einmal flach und einmal mit
# `serial.fi` unter `core/`, ergibt DIESELBEN 6858 Symbole (siehe
# docs/STRUKTUR.md, Abschnitt "Der Beweis").
#
# Die Datei wird ABSICHTLICH nicht selbst gebaut oder getestet -- das
# tut der Aufrufer, nach jedem Schritt einzeln.
set -uo pipefail
cd "$(dirname "$0")/../.."

MODUL=${1:-}
ORDNER=${2:-}
if [[ -z $MODUL || -z $ORDNER ]]; then
    sed -n '3,8p' "$0"
    exit 1
fi

QUELLE="kernel/$MODUL.fi"
ZIEL="kernel/$ORDNER/$MODUL.fi"

[[ -f $QUELLE ]] || { echo "es gibt kein $QUELLE" >&2; exit 1; }
[[ -e $ZIEL ]] && { echo "$ZIEL steht schon da" >&2; exit 1; }

mkdir -p "kernel/$ORDNER"
git mv "$QUELLE" "$ZIEL" || exit 1

# Nur die EIGENE import-Zeile, am Zeilenanfang, nichts sonst. Ein
# `import netmonitor` darf von `import netmon` nicht getroffen werden --
# deshalb das Zeilenende im Muster.
N=0
while IFS= read -r f; do
    sed -i -E "s|^([ \t]*)import[ \t]+$MODUL[ \t]*\$|\1import $ORDNER.$MODUL|" "$f"
    N=$((N + 1))
done < <(grep -rlE "^[ \t]*import[ \t]+$MODUL[ \t]*\$" --include='*.fi' kernel/ 2>/dev/null)

echo "$MODUL -> $ORDNER/  ($N import-Zeilen angepasst)"
