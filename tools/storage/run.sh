#!/usr/bin/env bash
#
# Usage:  bash tools/storage/run.sh [output_dir]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
mkdir -p "$TMPD"
SHOTS=${SHOTS:-$ROOT/docs/bilder/speicher}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op want
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
feld() { grep -aoE "(^|[^a-z])$3=[0-9]+" <(grep -aF "$2" "$1" | tail -1) \
         | tail -1 | sed 's/.*=//'; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "STORAGE: skipped, qemu-system-x86_64 is not there"; exit 0
fi
. tools/lib/firnenv.sh

echo "== build"
bash tools/storage/build.sh "$TMPD" || exit 1

# ---- runs
#
run_vm() { # name cmdline [image] [deadline]
    local name=$1 zeile=$2 img=${3:-inhalt.img} frist=${4:-3000}
    cp -f "$TMPD/$img" "$TMPD/live-$name.img"
    timeout "$frist" $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo "RC=$?" > "$TMPD/$name.rc"
}

shot() { # name cmdline [marker]
    local name=$1 zeile=$2 marke=${3:-'^storage: ready'}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/inhalt.img" "$TMPD/live-$name.img"
    timeout 900 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 4000 ]; do
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$sock"
    return 0
}

echo "== 1. time: the index against the complete walk"
echo "   (on gross.img, four thousand files -- this takes minutes)"
run_vm time 'du -m /data' gross.img
IUS=$(feld "$TMPD/time.txt" "du: index [/data]" us10)
WUS=$(feld "$TMPD/time.txt" "du: walk [/data]" us)
NDAT=$(feld "$TMPD/time.txt" "du: walk [/data]" files)
BUS=$(feld "$TMPD/time.txt" "du: build" us)
has "$TMPD/time.txt" "du: compare" "the measurement ran through"
num "files in the walk" "$NDAT" ge 4000
if [ -n "${IUS:-}" ] && [ -n "${WUS:-}" ] && [ "$IUS" -gt 0 ]; then
    FAKTOR=$(( WUS * 10 / IUS ))
    ok "index $((IUS / 10)) us per query, walk $WUS us -- factor $FAKTOR"
    num "the index is at least a thousand times faster" "$FAKTOR" ge 1000
    ok "one-time index build: $BUS us"
    if [ -n "${BUS:-}" ] && [ "$BUS" -gt 0 ]; then
        num "even the BUILD beats the walk" \
            $(( WUS / BUS )) ge 2
    fi
else
    bad "times missing (index '$IUS', walk '$WUS')"
fi

echo "== 2. correctness: the same question on an image WITH content"
run_vm measure 'du -m /data'
MOKT=$(feld "$TMPD/measure.txt" "du: index [/data]" okt)
MWOKT=$(feld "$TMPD/measure.txt" "du: walk [/data]" okt)
SOLL=$(awk '$1=="/data"{print $2}' "$TMPD/baum/soll")
num "the sum is not zero" "${MOKT:-0}" gt 0
if [ "${MOKT:-x}" = "${MWOKT:-y}" ]; then ok "index = walk: $MOKT octets"
else bad "index $MOKT, walk $MWOKT"; fi
if [ "${MOKT:-x}" = "${SOLL:-y}" ]; then ok "and the host computes the same: $SOLL"
else bad "the host says $SOLL, the guest $MOKT"; fi
has "$TMPD/measure.txt" "oktok=1" "the guest's own control check"

echo "== 3. EVERY directory, octet for octet, against three numbers"
run_vm probe 'du -p'
if python3 tools/storage/check.py "$TMPD/baum/soll" "$TMPD/probe.txt" \
        > "$TMPD/check.log" 2>&1; then
    ok "$(tail -1 "$TMPD/check.log")"
else
    bad "the big control check: $(tail -3 "$TMPD/check.log" | tr '\n' ' ')"
fi
sed 's/^/     /' "$TMPD/check.log"

echo "== 4. The journal must pick up GROWTH (not only new names)"
run_vm write 'du -w'
has "$TMPD/write.txt" "du: write" "the write probe ran"
num "no record was lost" "$(feld "$TMPD/write.txt" 'du: write synced' lost)" eq 0
num "the sum was caught up without rebuilding" \
    "$(feld "$TMPD/write.txt" 'du: write rebuilds' rebuilds)" eq 1
num "the caught-up sum is correct" \
    "$(feld "$TMPD/write.txt" 'du: write synced' ok)" eq 1
num "and after the delete the old state is back" \
    "$(feld "$TMPD/write.txt" 'du: write gone' ok)" eq 1

echo "== 5. control run: without catching up the number MUST become wrong"
run_vm writeW 'du -W'
WOK=$(feld "$TMPD/writeW.txt" 'du: write synced' ok)
WNACH=$(feld "$TMPD/writeW.txt" 'du: write synced' after)
WERW=$(feld "$TMPD/writeW.txt" 'du: write synced' expected)
if [ "${WOK:-1}" = "0" ] && [ "${WNACH:-0}" != "${WERW:-0}" ]; then
    ok "without journal the sum is off ($WNACH instead of $WERW) -- so the journal really caught up before"
else
    bad "without journal everything was still right (ok=$WOK, $WNACH against $WERW): then the probe measures nothing"
fi

echo "== 6. The surface"
mkdir -p "$SHOTS"
GRUND="nokbd nosched noproc nofs"
shot idle "gfx wm wig wigspeicher wmhold wiglong wighalt=240 $GRUND" '^storage: ready'
has "$TMPD/idle.txt" "k15: start /bin/speicher" "/bin/speicher comes FROM THE DISK"
has "$TMPD/idle.txt" "storage: tile" "it computed its tiles"
SOKT=$(feld "$TMPD/idle.txt" "storage: cd /data" okt)
if [ "${SOKT:-x}" = "${SOLL:-y}" ]; then
    ok "the surface shows the same number as you and as the host: $SOKT"
else
    bad "the surface says '$SOKT', du and the host say '$SOLL'"
fi
ZSUM=$(grep -aoE '^storage: row i=[0-9]+ okt=[0-9]+' "$TMPD/idle.txt" \
       | grep -oE 'okt=[0-9]+' | sed 's/okt=//' \
       | awk '{s+=$1} END{print s+0}')
if [ "${ZSUM:-0}" = "${SOKT:-x}" ]; then
    ok "the rows add up to the total: $ZSUM"
else
    bad "the rows give $ZSUM, the top says $SOKT"
fi
has "$TMPD/idle.txt" "storage: probe" "the surface checks itself"
num "and correctly" "$(feld "$TMPD/idle.txt" 'storage: probe' ok)" eq 1

if [ -s "$TMPD/idle.ppm" ]; then
    python3 tools/gfx/ppm2png.py "$TMPD/idle.ppm" "$SHOTS/speicher.png" \
        > "$TMPD/png.log" 2>&1 || cp -f "$TMPD/idle.ppm" "$SHOTS/speicher.ppm"
    ok "screenshot: $SHOTS/speicher.png"
    if python3 tools/storage/tileprobe.py "$TMPD/idle.ppm" \
            "$TMPD/idle.txt" > "$TMPD/tile.log" 2>&1; then
        ok "$(tail -1 "$TMPD/tile.log")"
    else
        bad "the treemap in the image: $(tail -2 "$TMPD/tile.log" | tr '\n' ' ')"
    fi
    sed 's/^/     /' "$TMPD/tile.log"
else
    bad "no screenshot was produced"
fi

echo "== 7. control run: the same surface without index"
shot without "gfx wm wig wigspeicher wignoidx wmhold wiglong $GRUND" \
    '^storage: (ready|cd)'
OOKT=$(feld "$TMPD/without.txt" "storage: cd" okt)
if [ "${OOKT:-0}" = "0" ]; then
    ok "without index the surface shows zero -- it invents nothing"
else
    bad "without index it says '$OOKT': from where?"
fi
if grep -qa "storage: tile" "$TMPD/without.txt"; then
    bad "without index tiles are painted anyway -- from which shares?"
else
    ok "without index the tiles disappear"
fi
[ -s "$TMPD/without.ppm" ] && { python3 tools/gfx/ppm2png.py "$TMPD/without.ppm" \
    "$SHOTS/speicher-ohne-index.png" >/dev/null 2>&1 || \
    cp -f "$TMPD/without.ppm" "$SHOTS/speicher-ohne-index.ppm"; }

echo
echo "STORAGE: $pass passed, $fail failed   (work dir: $TMPD)"
[ "$fail" -eq 0 ] || exit 1
exit 0
