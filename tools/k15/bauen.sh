#!/usr/bin/env bash
# tools/k15/bauen.sh -- Kernel, Programme und ein Plattenabbild dieser
# Runde, zum Iterieren waehrend der Arbeit. Die Abnahme baut in
# tools/k15/run.sh alles noch einmal aus BEIDEN Uebersetzern.
#
#   bash tools/k15/bauen.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/k15}
mkdir -p "$OUT"

PROGS="wigdemo explorer starter suchen sh echo ls cat edit"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
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
python3 tools/k15/baum.py "$OUT/baum" || exit 1
ARGS=(build "$OUT/disk.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
# Der ZWEITE NAME: ein Verzeichniseintrag mehr auf dieselbe Inode.
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
# DIE BUENDEL: /apps/<name>.prog/{INFO,start,symbol,daten/}
while read -r zeile; do ARGS+=("$zeile"); done < <(python3 tools/k15/buendel.py assets/apps "$OUT/buendel")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
