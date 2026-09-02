#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/server/build.sh -- DAS SERVERABBILD: ein Kern ohne eine Zeile
# Grafik und eine Platte ohne ein Programm mit Oberflaeche.
#
#   bash tools/server/build.sh [ausgabeverzeichnis] [--gui on]
#
# Was entsteht:
#
#   k.mb       der Kern, gebaut mit `tools/build-kernel.sh --gui off`.
#              `kernel/drivers/gfx/fb.fi`, `wm.fi`, `wig.fi`, `font.fi`, `ttf.fi`,
#              `tile.fi`, `vmode.fi`, `ansi.fi`, `ps2m.fi`, `kgui.fi`
#              und `sysgui.fi` sind dabei NICHT im Uebersetzungsbaum.
#   bin/*      das Userland eines Servers -- Shell, Dateiwerkzeuge,
#              Prozesse, Netz, Pakete. KEIN `schreibtisch`, kein
#              `leiste`, kein `einstellungen`, kein `explorer`, kein
#              `launcher`, kein `widgetdemo`, kein `tiling`, kein
#              `dispctl`: die haengen an `wlib.fi` und damit am
#              Fensterserver, und ohne den gibt es sie nicht.
#   disk.img   ein OFS-Dateisystem mit genau diesen Programmen.
#
# Danach bootet
#
#   qemu-system-x86_64 -accel kvm -kernel k.mb -m 256 -nographic \
#       -append "osum console=ttyS0" -drive file=disk.img,format=raw,if=ide
#
# bis zu einer Shell, in die man tippen kann.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:-/tmp/osum-server}
GUI=off
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gui) GUI=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done

# DIE PROGRAMMLISTE EINES SERVERS. Sie steht hier und nicht in einer
# Datei daneben, weil sie eine Aussage ist: das ist, was ohne Bildschirm
# uebrigbleibt, und wer etwas vermisst, sieht sofort, ob es fehlt oder
# ob es nie hineingehoerte.
PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc \
grep sort uniq cut tr seq tee xargs true false sleep ps kill uname date \
df du find which basename dirname chmod chown id whoami su login passwd \
mount umount sync tar gzip gunzip diff patch sed env top \
netstat ping wget opk power hwid locate edit"}

mkdir -p "$OUT/bin"

bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    echo "== firnc laesst sich nicht bauen"; tail -20 "$OUT/firnc.log"; exit 1; }
CC=${FIRNC:-vendor/firn/bin/firnc}

bash tools/build-kernel.sh "$OUT/k.mb" --gui "$GUI" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -30 "$OUT/k.log"; exit 1; }

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
gebaut=""
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -12 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/bin/$p" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        grep -v 'GNU-stack\|RWX\|deprecated' "$OUT/$p.lderr" | head -5
        rc=1
        continue
    fi
    strip --strip-all "$OUT/bin/$p" 2>/dev/null
    gebaut="$gebaut $p"
done
[ $rc = 0 ] || exit 1

# GEGENPROBE, UND SIE IST DER PUNKT DIESER DATEI: kein Programm auf
# dieser Platte darf den Fensterserver brauchen. Ein `schreibtisch`, der
# sich mit hineinstiehlt, faellt hier auf und nicht erst beim Booten.
verboten=""
for p in schreibtisch leiste einstellungen explorer launcher widgetdemo \
         tiling themetest dispctl icont; do
    [ -f "$OUT/bin/$p" ] && verboten="$verboten $p"
done
if [ -n "$verboten" ]; then
    echo "== auf der Serverplatte liegen Oberflaechenprogramme:$verboten"
    exit 1
fi

printf 'Osum, Serverbau. Kein Bildschirm, eine Leitung.\n' > "$OUT/readme.txt"
SPEC="/bin/"
for p in $gebaut; do SPEC="$SPEC /bin/$p=$OUT/bin/$p"; done
BLOCKS=${BLOCKS:-20480}
python3 tools/osum/mkfs.py build "$OUT/disk.img" "$BLOCKS" $SPEC \
    /readme.txt="$OUT/readme.txt" > "$OUT/mkfs.txt" 2>&1 || {
    echo "== mkfs.py"; cat "$OUT/mkfs.txt"; exit 1; }

echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette (gui=$GUI)"
echo "   userland  $(echo $gebaut | wc -w) Programme, $(du -sb "$OUT/bin" | cut -f1) Oktette"
echo "   platte    $(stat -c%s "$OUT/disk.img") Oktette, $BLOCKS Bloecke"
