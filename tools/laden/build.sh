#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/laden/build.sh -- RUNDE LADEN: Kern und Programme uebersetzen.
#
# Baut alles, was die Abnahme dieser Runde braucht, in EIN
# Arbeitsverzeichnis:
#
#   k.mb      der Kern
#   bin/*     die Programme (Ring 3, `profile kernel`)
#   bin/fetch das Programm der zweiten Bauart (`kernel/app/`, mit Halde)
#
# Es wird PARALLEL uebersetzt; der Uebersetzer ist ein eigener Prozess
# je Datei, und die Ausgaben landen in getrennten Dateien.
#
#   bash tools/laden/build.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/laden}
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT/bin"

# DIE PROGRAMME. Die erste Gruppe ist die Oberflaeche (alles, was
# `import wlib` hat), die zweite das Werkzeug darunter -- darunter
# `opk` und `ota`, ohne die diese Runde nichts zu messen haette.
GUI=${GUI:-"desktop taskbar launcher settings explorer widgetdemo themetest netmon theme"}
CLI=${CLI:-"sh ls cat echo edit cp mv rm mkdir rmdir touch head tail wc grep sort sleep ps kill uname date df install opk ota dhcp host reboot find du chmod id whoami top netview locate tar mount umount env which"}
APPS=${APPS:-"fetch"}

bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    echo "== firnc laesst sich nicht bauen"; tail -20 "$OUT/firnc.log"; exit 1; }

if [ ! -s "$OUT/k.mb" ] || [ -n "${LADEN_KERN_NEU:-}" ]; then
    bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
        echo "== der Kern laesst sich nicht bauen"; tail -30 "$OUT/k.log"; exit 1; }
fi
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1

eins() { # <name>
    local p=$1
    "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1 || {
        echo "FEHLER-UEBERSETZER $p"; return 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
       -o "$OUT/bin/$p" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr" || {
        echo "FEHLER-BINDER $p"; return 1; }
    strip --strip-all "$OUT/bin/$p"
    return 0
}
export -f eins
export OUT CC FIRNLIB

printf '%s\n' $GUI $CLI | sort -u > "$OUT/proglist"
: > "$OUT/bau.log"
xargs -a "$OUT/proglist" -P "$JOBS" -I{} bash -c 'eins {}' \
    >> "$OUT/bau.log" 2>&1
if grep -q FEHLER "$OUT/bau.log"; then
    echo "== diese Programme lassen sich nicht bauen:"
    grep FEHLER "$OUT/bau.log"
    for p in $(grep FEHLER "$OUT/bau.log" | awk '{print $2}'); do
        echo "--- $p"; head -12 "$OUT/$p.err" "$OUT/$p.lderr" 2>/dev/null
    done
    exit 1
fi
echo "   programme $(wc -l < "$OUT/proglist") Stueck"

for p in $APPS; do
    [ -f "kernel/app/$p.fi" ] || continue
    "$CC" -c --profile=app -o "$OUT/app-$p.o" "kernel/app/$p.fi" \
        > "$OUT/app-$p.err" 2>&1 || {
        echo "== $p (app): der Uebersetzer sagt nein"; head -20 "$OUT/app-$p.err"; exit 1; }
    ld -T kernel/user/user.ld -o "$OUT/bin/$p" "$OUT/app-$p.o" \
        2> "$OUT/app-$p.lderr" || {
        echo "== $p (app): der Binder sagt nein"; head -12 "$OUT/app-$p.lderr"; exit 1; }
    strip --strip-all "$OUT/bin/$p"
    echo "   app       $p ($(stat -c%s "$OUT/bin/$p") Oktette)"
done
exit 0
