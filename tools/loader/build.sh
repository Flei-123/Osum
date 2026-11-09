#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/laden}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT/bin"

GUI=${GUI:-"desktop taskbar launcher settings explorer widgetdemo themetest netmon theme taskmgr rechner trashbin viewer snip lock"}
CLI=${CLI:-"sh ls cat echo edit cp mv rm mkdir rmdir touch head tail wc grep sort sleep ps kill uname date df install opk ota dhcp host reboot find du chmod id whoami top netview locate tar mount umount env which zip wlan"}
APPS=${APPS:-"fetch"}

bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    echo "== firnc cannot be built"; tail -20 "$OUT/firnc.log"; exit 1; }

if [ ! -s "$OUT/k.mb" ] || [ -n "${LADEN_KERN_NEU:-}" ]; then
    bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
        echo "== the kernel cannot be built"; tail -30 "$OUT/k.log"; exit 1; }
fi
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1

eins() { # <name>
    local p=$1
    local q=$p
    [[ $p == rechner ]] && q=calc
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$q.fi" && { UPROF=--profile=app; UCRT=""; }
    "$CC" $UPROF $OPTL -c "kernel/user/$q.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1 || {
        echo "FEHLER-UEBERSETZER $p"; return 1; }
    ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
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
    echo "== these programs cannot be built:"
    grep FEHLER "$OUT/bau.log"
    for p in $(grep FEHLER "$OUT/bau.log" | awk '{print $2}'); do
        echo "--- $p"; head -12 "$OUT/$p.err" "$OUT/$p.lderr" 2>/dev/null
    done
    exit 1
fi
echo "   programme $(wc -l < "$OUT/proglist") Stueck"

for p in $APPS; do
    [ -f "kernel/app/$p.fi" ] || continue
    "$CC" $OPTL -c --profile=app -o "$OUT/app-$p.o" "kernel/app/$p.fi" \
        > "$OUT/app-$p.err" 2>&1 || {
        echo "== $p (app): der Uebersetzer sagt nein"; head -20 "$OUT/app-$p.err"; exit 1; }
    ld $GCS -T kernel/user/user.ld -o "$OUT/bin/$p" "$OUT/app-$p.o" \
        2> "$OUT/app-$p.lderr" || {
        echo "== $p (app): der Binder sagt nein"; head -12 "$OUT/app-$p.lderr"; exit 1; }
    strip --strip-all "$OUT/bin/$p"
    echo "   app       $p ($(stat -c%s "$OUT/bin/$p") Oktette)"
done

if [ -d "${CERTUS_REPO:-/root/certus-ui}/lib/browser" ]; then
    if bash kernel/user/certus/build.sh "$OUT/bin/certus" \
            > "$OUT/certus.log" 2>&1; then
        echo "   browser   certus ($(stat -c%s "$OUT/bin/certus") Oktette)"
    else
        echo "== certus cannot be built:"
        tail -12 "$OUT/certus.log"
    fi
else
    echo "   browser   skipped (no Certus tree in ${CERTUS_REPO:-/root/certus-ui})"
fi
exit 0
