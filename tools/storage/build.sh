#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
CC=$FIRNC
OUT=${1:-/tmp/speicher}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
BUDGET=${BUDGET:-420000}
mkdir -p "$OUT"

PROGS="storage du sh echo ls cat locate"
binname() { if [[ $1 == storage ]]; then echo speicher; else echo "$1"; fi; }

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== the kernel cannot be built"; tail -30 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -30 "$OUT/$p.err"
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

# --------------------------------------------------------- gross.img (Zeit)
python3 tools/k15/bigfs.py "$OUT/gross" 4000 > "$OUT/gross.log" 2>&1 || exit 1
ARGS=(build "$OUT/gross.img" 4096 /bin/)
for p in $PROGS; do
    [[ $p == storage ]] && continue
    ARGS+=("/bin/$(binname $p)=$OUT/$p.elf")
done
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/gross/angaben"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$OUT/mkfs-gross.log" 2>&1 || {
    echo "== mkfs.py (gross) fehlgeschlagen"; tail -5 "$OUT/mkfs-gross.log"
    exit 1; }
echo "   gross.img $(stat -c%s "$OUT/gross.img") Oktette  ($(tail -1 "$OUT/gross.log"))"

python3 tools/storage/tree.py "$OUT/baum" 4000 "$BUDGET" \
    > "$OUT/baum.log" 2>&1 || { cat "$OUT/baum.log"; exit 1; }
cp -f tools/k15/theme "$OUT/baum/theme" 2>/dev/null || \
    python3 - "$OUT/baum/theme" <<'EOF'
import sys
open(sys.argv[1], "wb").write(open(
    "tools/k15/tree.py").read().split('THEME = b"""')[1]
    .split('"""')[0].encode())
EOF
INHALT_BLOCKS=${INHALT_BLOCKS:-16384}
ARGS=(build "$OUT/inhalt.img" "$INHALT_BLOCKS" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf"
      "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$(binname $p)=$OUT/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/baum/angaben"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$OUT/mkfs-inhalt.log" 2>&1 || {
    echo "== mkfs.py (inhalt) fehlgeschlagen"; tail -5 "$OUT/mkfs-inhalt.log"
    echo "   -> BUDGET kleiner setzen (jetzt $BUDGET)"; exit 1; }
echo "   inhalt.img $(stat -c%s "$OUT/inhalt.img") Oktette  ($(tail -1 "$OUT/baum.log"))"
echo "   inhalt.img: $(bash tools/mkfsfi/mkfs.sh list "$OUT/inhalt.img" | wc -l) Namen"
exit 0
