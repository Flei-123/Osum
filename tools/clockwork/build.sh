#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:?zielverzeichnis fehlt}
mkdir -p "$OUT"

echo "== Kern bauen =="
bash tools/build-kernel.sh "$OUT/kern.mb" --stufe 0 > "$OUT/kern.log" 2>&1 \
    || { echo "NO: the kernel does not build"; tail -20 "$OUT/kern.log"; exit 1; }
echo "  ok  kern.mb ($(stat -c%s "$OUT/kern.mb") Oktette)"

PROGS="desktop taskbar settings launcher explorer widgetdemo locate dhcp sh echo ls cat edit"
as --64 -o "$OUT/crt.o" kernel/user/crt.s 2>/dev/null \
    || { echo "NEIN: crt.s"; exit 1; }
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/e$p" 2>&1 || {
        echo "NEIN: firnc $p.fi"; head -10 "$OUT/e$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2>/dev/null \
        || { echo "NEIN: ld $p"; exit 1; }
    strip --strip-all "$OUT/$p.elf"
done
echo "  ok  $(echo $PROGS | wc -w) Ring-3-Programme"

python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 \
    || { echo "NEIN: tree.py"; exit 1; }

printf '# taskbar.conf\nedge=bottom\nheight=40\nwidth=104\nautohide=0\nontop=1\nalign=left\nlabels=never\nclock_seconds=1\nclock_date=1\nclock_weekday=0\nclock_lines=1\nhide_missing=1\n' \
    > "$OUT/tb.conf"

# RUNDE BAUFEHLER (14.09.2026): 16384 -> 32768 Bloecke (8 -> 16 MiB).











ARGS=(build "$OUT/root.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer" /etc/ "/etc/theme=$OUT/baum/theme"
       "/etc/taskbar.conf=$OUT/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$OUT/mkfs.txt" 2>&1 \
    || { echo "NEIN: mkfs.py"; tail -5 "$OUT/mkfs.txt"; exit 1; }
echo "  ok  root.img ($(stat -c%s "$OUT/root.img") Oktette)"
