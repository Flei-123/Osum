#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/module/build.sh -- EIN MODUL BAUEN, aus dem Repo heraus.
#
#   ./tools/modul/build.sh AUSGABE.omod [--stufe 0|1] [--name N] [--abi N]
#                                     [weitere Optionen fuer mkomod.py]
#
# WARUM EIN EIGENES SKRIPT UND NICHT EIN AUFRUF VON firnc: ein Modul wird
# aus einem BAUM uebersetzt, der kleiner ist als der Kernbaum, und das
# ist keine Bequemlichkeit, sondern eine Notwendigkeit.
#
#
# `module/ps2maus.fi` macht `import ps2m`, `kernel/ps2m.fi` macht
# `import serial`, und `kernel/serial.fi` macht `import gfx` -- und
# `gfx.fi` ist die NAHT zur ganzen Oberflaeche (wm, fb, ttf, tile,
# vmode). Uebersetzt man das Modul aus dem vollen Kernbaum, zieht ein
# Mausmodul den Fensterserver mit: gemessen 3 308 584 Oktette
# Objektdatei, .text 1,7 MiB.
#
# Der Ausweg ist der, den `tools/build-kernel.sh` fuer `--gui off`
# nimmt und den es dafuer schon gibt: `kernel/gfx-aus.fi`, dieselben
# 37 Symbole mit leeren Rumpfen. Der Baum unten besteht aus GENAU den
# Dateien, die das Modul wirklich braucht, und `gfx.fi` ist die
# Leerfassung. Ergebnis: 56 776 Oktette, .text 23 KiB.
#
# DAS IST KEINE ABKUERZUNG, SONDERN DIE SACHE SELBST. Ein Treibermodul,
# das den halben Kern mitbringt, waere kein Modul, sondern ein zweiter
# Kern -- und die Symbole, die es dann DOPPELT haette, waeren genau die,
# an denen ein Zustand zweimal gefuehrt wird. Was ein Modul vom Kern
# braucht, geht ueber `extern fn` und `kernel/ksym.fi`, und nur darueber.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

AUS=${1:-}
if [[ -z $AUS ]]; then
    sed -n '2,12p' "$0"
    exit 1
fi
shift

STUFE=0
QUELLE=module/ps2maus.fi
MKARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stufe) STUFE=$2; shift 2 ;;
        --quelle) QUELLE=$2; shift 2 ;;
        *) MKARGS+=("$1"); shift ;;
    esac
done

bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen" >&2; exit 1; }
if [[ $STUFE == 0 ]]; then
    FIRNC="$ROOT/vendor/firn/bin/firnc"
else
    FIRNC="$ROOT/vendor/firn/bin/firnc1"
fi
[[ -x $FIRNC ]] || { echo "Uebersetzer fehlt: $FIRNC" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/k/arch"

# Die Huelle des Moduls. Das ist die einzige Datei, die diese Runde neu
# geschrieben hat -- der Treiber darin ist `kernel/ps2m.fi`, unveraendert.
cp -f "$QUELLE" "$TMP/k/" || exit 1

# Der Abschluss der Importe, Datei fuer Datei, und jede mit ihrem Grund:
#   ps2m.fi     DER TREIBER, unveraendert aus dem Kern
#   kstate.fi   die Versaetze in `kdata` -- ein Modul, das andere naehme,
#               schriebe in fremde Oktette
#   serial.fi   `in8`/`out8` fuer den 8042 und die Meldungen
#   errno.fi    gfx-aus.fi braucht es
#   arch/       `machine.fi` holt `kdata`, `arch.fi` waehlt den Bogen
#   modidx.fi   die Platznummern der Treibertafel
for f in ps2m.fi kstate.fi serial.fi errno.fi modidx.fi; do
    cp -f "kernel/$f" "$TMP/k/$f" || exit 1
done
cp -f kernel/arch/arch.fi kernel/arch/machine.fi "$TMP/k/arch/" || exit 1
# Und die Naht als Leerfassung -- siehe oben.
cp -f kernel/gfx-aus.fi "$TMP/k/gfx.fi" || exit 1

export FIRNLIB="$ROOT/lib"
BASENAME=$(basename "$QUELLE")
"$FIRNC" -o "$TMP/m.o" "$TMP/k/$BASENAME" || exit 1

# Ein Modul darf KEIN undefiniertes Symbol haben, das der Kern nicht
# anbietet. Das prueft der Lader zur Laufzeit (Grund `symbol`), aber es
# beim Bauen zu sehen ist billiger als es in QEMU zu sehen.
UNDEF=$(readelf -sW "$TMP/m.o" | awk '$7=="UND" && $8!="" {print $8}' | sort -u)
echo "undefinierte Symbole: $(echo $UNDEF | tr '\n' ' ')"

python3 tools/module/mkomod.py bauen "$TMP/m.o" "$AUS" "${MKARGS[@]}" || exit 1
