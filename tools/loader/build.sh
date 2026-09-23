#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/loader/build.sh -- RUNDE LADEN: Kern und Programme uebersetzen.
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
#   bash tools/loader/build.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/laden}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT/bin"

# DIE PROGRAMME. Die erste Gruppe ist die Oberflaeche (alles, was
# `import wlib` hat), die zweite das Werkzeug darunter -- darunter
# `opk` und `ota`, ohne die diese Runde nichts zu messen haette.
# RUNDE CERTUS-AUF-OSUM: `taskmgr` gehoert dazu. assets/apps enthaelt
# taskmgr.osp, und dessen `start` ist ein zweiter Name auf /bin/taskmgr
# -- fehlt die Datei, lehnt tools/osum/mkfs.py das ganze Abbild ab
# ("mkfs: '/bin/taskmgr' gibt es nicht"). Gemessen beim ersten Bau
# dieser Runde; es hat nichts mit dem Browser zu tun und wird hier
# trotzdem behoben, weil es JEDEN Bau dieses Skripts betrifft.
GUI=${GUI:-"desktop taskbar launcher settings explorer widgetdemo themetest netmon theme taskmgr rechner papierkorb viewer snip lock"}
CLI=${CLI:-"sh ls cat echo edit cp mv rm mkdir rmdir touch head tail wc grep sort sleep ps kill uname date df install opk ota dhcp host reboot find du chmod id whoami top netview locate tar mount umount env which zip wlan"}
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
    # Seit ENGLISCH ETAPPE 9 heisst die QUELLE von /bin/rechner calc.fi;
    # Paket und Laden kennen das Programm weiter als `rechner`.
    local q=$p
    [[ $p == rechner ]] && q=calc
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$q.fi" && { UPROF=--profile=app; UCRT=""; }
    "$CC" $UPROF -c "kernel/user/$q.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1 || {
        echo "FEHLER-UEBERSETZER $p"; return 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
       -o "$OUT/bin/$p" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr" || {
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

# ============================================ RUNDE CERTUS-AUF-OSUM
#
# Der Browser ist die dritte Bauart in diesem Skript, und er ist die
# einzige, deren QUELLTEXT NICHT IN DIESEM BAUM LIEGT: Certus gehoert
# zum Firn-Projekt ($CERTUS_REPO, Zweig `osum`), ist rund 105.000
# Zeilen gross und wird mit SEINEM eigenen Uebersetzer gebaut -- nicht
# mit dem festgenagelten aus vendor/firn, dem er voraus ist. Wie das
# geht und warum, steht in kernel/user/certus/build.sh.
#
# Fehlt der Baum, faellt hier nichts aus: das Abbild hat dann kein
# /bin/certus, und tools/loader/pakete.sh laesst das Paket weg. Ein
# Bauskript, das ohne fremdes Repo gar nicht mehr durchlaeuft, waere
# der schlechtere Tausch.
if [ -d "${CERTUS_REPO:-/root/certus-sammeln}/lib/browser" ]; then
    if bash kernel/user/certus/build.sh "$OUT/bin/certus" \
            > "$OUT/certus.log" 2>&1; then
        echo "   browser   certus ($(stat -c%s "$OUT/bin/certus") Oktette)"
    else
        echo "== certus laesst sich nicht bauen:"
        tail -12 "$OUT/certus.log"
    fi
else
    echo "   browser   uebersprungen (kein Certus-Baum in ${CERTUS_REPO:-/root/certus-sammeln})"
fi
exit 0
