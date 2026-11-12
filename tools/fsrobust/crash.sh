#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."

ABBILD=$1
ARB=$2
NR=$3
EXTRA=${4:-}

K=${FSR_KERNEL:-/tmp/fsr-k.mb}
MINMS=${FSR_MINMS:-120}
SPANMS=${FSR_SPANMS:-2600}
WRITER=${FSR_WRITER:-fsrw endlos}
MARKER=${FSR_MARKER:-fsrw: los}

if [ "${FSR_DRIVE:-ide}" = ahci ]; then
    DRIVE_ARGS=(-device ich9-ahci,id=ahci0 -drive "file=$ARB/live-$NR.img,format=raw,if=none,id=hd0,cache=directsync" -device ide-hd,drive=hd0,bus=ahci0.0)
    FSCK_STEP=""
else
    DRIVE_ARGS=(-drive "file=$ARB/live-$NR.img,format=raw,if=ide,index=0,cache=directsync")
    FSCK_STEP=";fsck /dev/hda"
fi

LIVE="$ARB/live-$NR.img"
S1="$ARB/w-$NR.txt"
S2="$ARB/v-$NR.txt"
rm -f "$LIVE" "$S1" "$S2"
cp --sparse=always "$ABBILD" "$LIVE"

qemu-system-x86_64 -accel tcg -kernel "$K" -m 512 \
    -append "osum vfs nokbd $EXTRA script=$WRITER" \
    -serial "file:$S1" -display none -no-reboot \
    "${DRIVE_ARGS[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!

LOS=0
for _ in $(seq 1 1200); do
    if [ -f "$S1" ] && tr -d '\000' < "$S1" 2>/dev/null | grep -qaF "$MARKER"; then
        LOS=1
        break
    fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05
done

MS=$(( MINMS + (RANDOM * 32768 + RANDOM) % SPANMS ))
if [ "$LOS" = 1 ]; then
    sleep "$(awk "BEGIN{printf \"%.3f\", $MS/1000}")"
fi
kill -9 "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null

# ------------------------------------------------- 2. wieder hochfahren
timeout 900 qemu-system-x86_64 -accel tcg -kernel "$K" -m 512 \
    -append "osum vfs nokbd $EXTRA script=fsrv${FSCK_STEP};exit" \
    -serial "file:$S2" -display none -no-reboot \
    "${DRIVE_ARGS[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
RC2=$?

val() { tr -d '\000' < "$S2" 2>/dev/null | grep -a "^$1: $2 = " | head -1 | sed 's/.* = //'; }

COUNT=$(val fsrv count)
ROK=$(val fsrv rollok)
ROK2=$(val fsrv rollok2)
SCH=$(val fsrv schaeden)
FSCK=$(val fsck errors)
JOFF=$(val fsck journal_open)
if [ -z "$FSCK_STEP" ]; then FSCK=0; JOFF=0; fi
NACH=$(tr -d '\000' < "$S2" 2>/dev/null | grep -oa 'ofsj: nachgetragen=[0-9]*' | head -1 | sed 's/.*=//')

WS=$(python3 tools/fsrobust/check.py struktur "$LIVE" 2>&1 | grep -c BEFUND)
WI=$(python3 tools/fsrobust/check.py inhalt "$LIVE" 2>&1 | grep -c BEFUND)
WIRT=$(( WS + WI ))

echo "lauf=$NR ms=$MS los=$LOS count=${COUNT:-?} schaeden=${SCH:-?}" \
     "rollok=${ROK:-?},${ROK2:-?} nachgetragen=${NACH:-0} fsck=${FSCK:-?} joffen=${JOFF:-?} wirt=$WIRT rc2=$RC2"
if [ "$WIRT" != 0 ]; then
    python3 tools/fsrobust/check.py struktur "$LIVE" 2>&1 | sed 's/^/    /'
    python3 tools/fsrobust/check.py inhalt "$LIVE" 2>&1 | sed 's/^/    /'
fi
