#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pakete/bauen.sh -- DIE DREI PAKETE DIESER RUNDE BAUEN.
#
# Die Kette ist dieselbe wie bei tools/module/paket.sh, nur ohne Kern:
#
#   kernel/user/<prog>.fi
#        │  firnc + ld (kernel/user/user.ld, USER_ENTRY=_F0.u_start)
#        ▼
#   pakete/wmplug-*/bau/<prog>.elf          <- Nutzlast, NICHT im Git
#        │  pkg/opk.py bauen  (dasselbe Format, das /bin/opk liest)
#        ▼
#   <ausgabe>/<name>-<fassung>.opk
#
# WARUM DIE REZEPTE IM GIT STEHEN UND DIE .opk NICHT: ein Paket ist ein
# Ergebnis, kein Quelltext. Wer es nachbauen will, ruft dieses Skript;
# wer wissen will, was drin ist, liest das Rezept.
#
# Fehlt `pkg/opk.py` (es liegt in einem anderen Baum), werden die ELFs
# trotzdem gebaut und der Paketschritt ausdruecklich uebersprungen --
# schweigend etwas auslassen waere das, was man spaeter fuer "gebaut"
# haelt.
#
#   bash pakete/bauen.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:-/tmp/wmplug-pakete}
OPK=${OPK:-/root/orientos-install/pkg/opk.py}
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
mkdir -p "$OUT"

CRT=$(mktemp -d)/crt.o
as --64 -o "$CRT" kernel/user/crt.s || exit 1

# ein Ring-3-Programm uebersetzen: quelle, paketverzeichnis, name
elf() {
    local quelle=$1 paket=$2 name=$3
    if [ ! -f "$quelle" ]; then
        echo "   $name: $quelle fehlt (anderes Modul, noch nicht da)"
        return 1
    fi
    mkdir -p "$paket/bau"
    "$FIRNC" "$quelle" -o "$paket/bau/$name.o" || return 1
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$paket/bau/$name.elf" "$CRT" "$paket/bau/$name.o" || return 1
    rm -f "$paket/bau/$name.o"
    echo "   $name.elf $(stat -c%s "$paket/bau/$name.elf") Oktette"
    return 0
}

paket() { # verzeichnis
    local d=$1
    if [ ! -f "$OPK" ]; then
        echo "   $d: opk.py fehlt ($OPK) -- der Paketschritt faellt aus"
        return 0
    fi
    local nm
    nm=$(sed -n 's/^name=//p' "$d/rezept" | head -1)
    local fs
    fs=$(sed -n 's/^fassung=//p' "$d/rezept" | head -1)
    python3 "$OPK" bauen "$d/rezept" -o "$OUT/$nm-$fs.opk" | sed 's/^/   /'
}

echo "== die Programme =="
elf kernel/user/wmplug.fi   pakete/wmplug-werkzeug wmplug
elf kernel/user/pluguhr.fi  pakete/wmplug-uhr      pluguhr
elf kernel/user/plugregel.fi pakete/wmplug-regel   plugregel

echo "== die Pakete =="
for d in pakete/wmplug-werkzeug pakete/wmplug-uhr pakete/wmplug-regel; do
    if [ -d "$d/bau" ]; then
        paket "$d"
    else
        echo "   $d: ohne Nutzlast, uebersprungen"
    fi
done
echo "fertig in $OUT"
