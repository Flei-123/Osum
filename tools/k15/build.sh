#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/k15/build.sh -- Kernel, Programme und ein Plattenabbild dieser
# Runde, zum Iterieren waehrend der Arbeit. Die Abnahme baut in
# tools/k15/run.sh alles noch einmal aus BEIDEN Uebersetzern.
#
#   bash tools/k15/build.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/k15}
mkdir -p "$OUT"

PROGS="widgetdemo explorer launcher locate sh echo ls cat edit"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        head -12 "$OUT/$p.lderr"
        rc=1
        continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-10s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

# Das Abbild: die beiden Schriften (der Fensterserver liest sie von der
# Platte), die Programme, ein Farbschema und ein Verzeichnisbaum, an dem
# der Dateimanager etwas zu zeigen hat.
python3 tools/k15/tree.py "$OUT/baum" || exit 1
# RUNDE MODERN: 16384 BLOECKE STATT 4096, UND EINE MEHRBLOCKIGE KARTE.
#
# GEMESSEN, NICHT GERATEN: die Nutzlast dieses Abbilds sind 4 752 920
# Oktette (neun Programme, drei Schriften, Buendel, Sprachdateien).
# Ein Block ist hier 512 Oktette -- 4096 Bloecke sind also 2 MiB,
# und die Nutzlast ist 4,5 MiB. Das Abbild war schon VOR dieser
# Runde zu klein: ein sauberer Stand ohne jede Aenderung endet
# ebenso mit "mkfs: the disk is full". Der fette Schnitt (45 012
# Oktette) hat das nicht verursacht, er kam nur dazu.
#
# WARUM AUCH --karten: eine Blockkarte deckt BS*8 = 4096 Bloecke.
# Ohne Vorrat an Kartenbloecken ist bei 4096 Schluss, egal welche
# Zahl hier steht. 16384 Bloecke brauchen vier Karten; 32 sind
# Vorrat nach oben, wie in tools/install/build.sh.
ARGS=(build "$OUT/disk.img" 16384 "--karten=32" "--inodes=512" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" "/lib/bold.ttf=assets/osum-sans-bold.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
# Der ZWEITE NAME: ein Verzeichniseintrag mehr auf dieselbe Inode.
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
# RUNDE I18N: die Sprachdateien. Ohne sie zeigt jedes Bedienelement
# seinen Schluessel -- der Rueckfall, und nicht das, was gemessen wird.
ARGS+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/
       "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/
       "/usr/share/locale/de/messages=locale/de/messages")
# DIE BUENDEL: /apps/<name>.osp/{INFO,start,symbol,daten/}
while read -r zeile; do ARGS+=("$zeile"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel" nur="$PROGS")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
