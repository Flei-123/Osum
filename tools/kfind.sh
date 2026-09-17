#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kfind.sh -- WO LIEGT EIN KERNMODUL?
#
# Bis zur Runde O-STRUKTUR lagen alle Kerndateien flach in `kernel/`,
# und jeder Testlaeufer durfte `kernel/kstate.fi` buchstabieren. Seit
# die Dateien in Schichtverzeichnissen liegen (`kernel/lib/kstate.fi`,
# `kernel/gfx/fb.fi`, ...) stimmt dieser Pfad nicht mehr.
#
# Statt in ueber hundert Laeufern je einen Pfad zu aendern -- und beim
# naechsten Umzug wieder --, fragt man hier:
#
#     KSTATE=$(bash tools/kfind.sh kstate)
#     grep -aE '^const MAX_CPUS' "$KSTATE"
#
# oder, weil das kuerzer ist, ueber die Hilfsfunktion in
# `tools/kpfad.sh`:
#
#     . tools/kpfad.sh
#     grep -aE '^const MAX_CPUS' "$(kfi kstate)"
#
# REGELN:
#   * Gesucht wird NUR unter `kernel/`, und NUR nach `<name>.fi`.
#   * Gefunden werden muss GENAU EINE Datei. Zwei Treffer sind ein
#     Fehler und keine Auswahl -- in Firn waeren zwei Module gleichen
#     Namens ohnehin eine Namenskollision (`modules.rs`).
#   * `kernel/user/` und `kernel/app/` sind EIGENE Programme mit
#     eigenen Wurzeln; sie werden ausgelassen, sonst faende `netmon`
#     zwei Dateien (Kern und Anwendung tragen denselben Namen).
#   * Kein Treffer -> Code 1 und eine Meldung auf stderr. Ein Laeufer,
#     der einen Pfad braucht, soll LAUT scheitern und nicht mit einer
#     leeren Zeichenkette weiterrechnen.
set -uo pipefail

NAME=${1:-}
if [[ -z $NAME ]]; then
    echo "Aufruf: tools/kfind.sh <modulname ohne .fi>" >&2
    exit 1
fi

# Vom Ort dieses Skripts aus, damit der Aufrufer in jedem
# Arbeitsverzeichnis stehen darf.
WURZEL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

mapfile -t TREFFER < <(find "$WURZEL/kernel" \
    -path "$WURZEL/kernel/user" -prune -o \
    -path "$WURZEL/kernel/app" -prune -o \
    -name "$NAME.fi" -type f -print 2>/dev/null | sort)

case ${#TREFFER[@]} in
    1) echo "${TREFFER[0]}" ;;
    0) echo "kfind: '$NAME.fi' liegt nirgends unter kernel/" >&2; exit 1 ;;
    *) { echo "kfind: '$NAME.fi' liegt MEHRFACH unter kernel/:"
         printf '  %s\n' "${TREFFER[@]}"
         echo "  Zwei Module gleichen Namens sind in Firn eine Kollision."
       } >&2; exit 1 ;;
esac
