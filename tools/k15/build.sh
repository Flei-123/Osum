#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
CC=$FIRNC
OUT=${1:-/tmp/k15}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"

PROGS="widgetdemo explorer launcher locate sh echo ls cat edit"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== the kernel cannot be built"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF $OPTL -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
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

python3 tools/k15/tree.py "$OUT/baum" || exit 1
ARGS=(build "$OUT/disk.img" 16384 --v3 "--karten=32" "--inodes=512" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" "/lib/bold.ttf=assets/osum-sans-bold.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
ARGS+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/
       "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/
       "/usr/share/locale/de/messages=locale/de/messages")
while read -r zeile; do ARGS+=("$zeile"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel" nur="$PROGS")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
