#!/usr/bin/env bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$HERE/../../.." && pwd)}
cd "$REPO"
GUEST=${GUEST:-tools/linuxapps/guest-fx12-hang.sh}
OUT=${OUT:?output directory}
IMGDIR=${IMGDIR:?directory holding <image>.img and <image>.img.elf}
SPECS=${SPECS:?label:image:kernel-words, space separated}
WDSRC=${WDSRC:-/root/abbilder/ffx2/wd}
N=${N:-12}
MAXID=${MAXID:-1000}
STOP=${STOP:-$OUT/STOP}
RUNS=${RUNS:-6}
HANG_TARGET=${HANG_TARGET:-0}
PORT_BASE=${PORT_BASE:-24000}
PORT_SPAN=${PORT_SPAN:-400}
mkdir -p "$OUT"
RESULTS=$OUT/results.tsv
seq_no=0

pick_port() {
    while :; do
        PICKED=$((PORT_BASE + seq_no % PORT_SPAN))
        seq_no=$((seq_no + 1))
        ss -ltn 2> /dev/null | grep -q ":$PICKED " || return
    done
}

summarize() {
    local label=$1 id=$2 out=$3
    local ok bad faults hang fetch_race data_race
    ok=$(grep -ac '^FX11 run [0-9]* rc=0 ' "$out/ser.txt" 2>/dev/null)
    bad=$(grep -a '^FX11 run [0-9]* rc=' "$out/ser.txt" 2>/dev/null | grep -avc ' rc=0 ')
    faults=$(grep -ac 'user fault' "$out/ser.txt" 2>/dev/null)
    hang=$(grep -ac '^FX-HANG kind=' "$out/ser.txt" 2>/dev/null)
    fetch_race=$(grep -a '^tlb\.30 ' "$out/ser.txt" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r')
    data_race=$(grep -a '^tlb\.31 ' "$out/ser.txt" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$id" "${ok:-0}" "${bad:-0}" "${faults:-0}" "${hang:-0}" "${fetch_race:-0}" "${data_race:-0}" >> "$RESULTS"
    if [ "${hang:-0}" -eq 0 ] && [ "${bad:-0}" -eq 0 ] && [ "${faults:-0}" -eq 0 ] && [ "${fetch_race:-0}" -eq 0 ]; then
        rm -rf "$out" "$out.log"
    fi
}

job() {
    local label=$1 img=$2 args=$3 id=$4 port=$5
    local wd=$IMGDIR/wd_${label}_$id out=$OUT/${label}_$id
    rm -rf "$wd"
    cp -al "$WDSRC" "$wd"
    sed -i "s#$WDSRC#$wd#g" "$wd/fxrun/spec.txt"
    mkdir -p "$out"
    bash "$HERE/watch.sh" "$out" "$port" "$IMGDIR/$img.img.elf" &
    local watcher=$!
    SMP=4 KARGS_EXTRA="$args" NOSAMPLE=1 FXWD=$wd DRIVE_SNAP=1 TMO=${VM_TMO:-3300} DONE=FX-END FXGUEST=$GUEST QEMU_GDB=$port \
        /root/jarvis/bin/heavy bash tools/linuxapps/prof/walltime.sh "$IMGDIR/$img.img" "$out" "$RUNS" ahci > "$out.log" 2>&1
    kill "$watcher" 2> /dev/null
    wait "$watcher" 2> /dev/null
    rm -f "$out/disk.img"
    rm -rf "$wd"
    summarize "$label" "$id" "$out"
}

hangs_found() {
    ls "$OUT"/*/hang-gdb.txt 2> /dev/null | wc -l
}

id=1
while [ ! -e "$STOP" ] && [ "$id" -le "$MAXID" ]; do
    for spec in $SPECS; do
        label=${spec%%:*}
        rest=${spec#*:}
        img=${rest%%:*}
        args=${rest#*:}
        [ "$args" = "$rest" ] && args=""
        args=${args//+/ }
        while [ "$(jobs -rp | wc -l)" -ge "$N" ]; do sleep 2; done
        [ -e "$STOP" ] && break
        if [ "$HANG_TARGET" -gt 0 ] && [ "$(hangs_found)" -ge "$HANG_TARGET" ]; then
            touch "$STOP"
            break
        fi
        pick_port
        job "$label" "$img" "$args" "$id" "$PICKED" &
        sleep 1
    done
    id=$((id + 1))
done
wait
echo SERIES-DONE
