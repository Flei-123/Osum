#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/serline/run.sh -- W-D1: A SERIAL LINE STAYS ONE LINE.
#
#   bash tools/serline/run.sh [<workers>] [<lines>] [<cores>] [<boots>]
#
# Before: `serial.put` wrote octet by octet without a lock; only klog lines
# and one `write` at a time (sys.conout) held the line lock. A line made of
# several writes (`say`, `sayn`, `nl`) or of several `puts` calls was torn by
# a line from another core (~1 boot in 5) and the gates that wait for a
# whole line flaked.
# After: `serial.put` holds the line lock from the first octet to the newline.
#
# Guest `serline` (kernel/user/serline.fi): <workers> children on <cores> cores
# write <lines> lines each, three sections per boot:
#   ONE    one write per line
#   MULTI  six writes per line (the way say/sayu/nl print)
#   OPEN   MULTI, but the parent first leaves "OPEN:" without a newline
#          (an unfinished line must not freeze the others)
# The host counts intact lines (tools/serline/check.py); torn must be 0.
# Counter-proof: kernel word `noserline` (old behaviour): MULTI must tear.
#
# HOLD section (one core): kernel word `serhold` starts a kernel task that holds
# the line with serial.line_at() across two timer ticks while a user task writes
# whole lines on the same core. The held line must stay whole. Counter-proof:
# word `serholdsti` (interrupts back on inside the hold = the behaviour before
# line_at() disabled them) must tear the held line.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
WORKERS=${1:-4}
LINES=${2:-60}
CORES=${3:-4}
BOOTS=${4:-3}
. tools/lib/summary.sh; summary_begin SERLINE
trap 'summary_guard; [ -z "${SERLINE_KEEP:-}" ] && rm -rf "${TMPD:-}"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
HOLD_LINES=${HOLD_LINES:-300}
HOLD_BOOTS=${HOLD_BOOTS:-3}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=${SERLINE_DIR:-$(mktemp -d)}; mkdir -p "$TMPD"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
PROGS="sh echo serline"

echo "== build =="
. tools/lib/firnenv.sh
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "programs build"
else
    sed 's/^/        /' "$TMPD/b.txt" | head -20; bad "programs do not build"
    summary_emit "$pass" "$fail" 0; exit 1
fi
KIMG=${SERLINE_KERNEL:-}
if [ -z "$KIMG" ]; then
    KIMG="$TMPD/k0.img"
    if ./tools/build-kernel.sh "$KIMG" --stufe 0 > "$TMPD/k.txt" 2>&1; then
        ok "kernel builds"
    else
        tail -8 "$TMPD/k.txt" | sed 's/^/        /'; bad "kernel does not build"
        summary_emit "$pass" "$fail" 0; exit 1
    fi
else
    ok "kernel given: $KIMG"
fi

{
    echo "echo ==ONE=="
    echo "serline $WORKERS $LINES one"
    echo "echo ==MULTI=="
    echo "serline $WORKERS $LINES multi"
    echo "echo ==OPEN=="
    echo "serline $WORKERS $LINES multi open"
    echo "echo ==END=="
} > "$TMPD/s.sh"
{
    echo "echo ==HOLD=="
    echo "serline 1 $HOLD_LINES one"
    echo "echo ==END=="
} > "$TMPD/h.sh"
A=(build "$TMPD/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/)
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
A+=("/t/s.sh=$TMPD/s.sh" "/t/h.sh=$TMPD/h.sh")
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { tail -3 "$TMPD/mkfs.txt"; bad "mkfs"; summary_emit "$pass" "$fail" 0; exit 1; }

run() { # <name> <extra kernel words> [cores] [script]
    local nm=$1 extra=$2 cores=${3:-$CORES} script=${4:-/t/s.sh}
    cp -f "$TMPD/d.img" "$TMPD/$nm.img"
    timeout 600 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$cores" \
        -kernel "$KIMG" -m 512 \
        -append "osum vfs nokbd $extra script=sh $script;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$TMPD/$nm.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$TMPD/$nm.img"
}
# value of <key>= in the check.py line
val() { sed -n "s/.*$2=\([0-9]*\).*/\1/p" <<<"$1"; }

# $1 = prefix, $2 = words; sets TORN_ONE / TORN_MULTI / TORN_OPEN / MISS (incomplete sections)
measure() {
    TORN_ONE=0; TORN_MULTI=0; TORN_OPEN=0; MISS=0
    for n in $(seq 1 "$BOOTS"); do
        run "$1$n" "smpfrueh $2"
        local line
        for s in ONE MULTI OPEN; do
            line=$(python3 -I tools/serline/check.py "$TMPD/$1$n.txt" "$s" "$WORKERS" "$LINES")
            echo "        boot $n $s: $line"
            local t d; t=$(val "$line" torn); d=$(val "$line" done)
            [ -z "$t" ] && { MISS=$((MISS+1)); continue; }
            [ "$d" = 1 ] || MISS=$((MISS+1))
            case $s in
                ONE) TORN_ONE=$((TORN_ONE+t));; MULTI) TORN_MULTI=$((TORN_MULTI+t));; OPEN) TORN_OPEN=$((TORN_OPEN+t));;
            esac
        done
    done
}

echo "== fix: $BOOTS boots x 3 sections x ($WORKERS workers x $LINES lines), $CORES cores =="
measure fix ""
[ "$MISS" -eq 0 ] && ok "every section finished (serline: done)" || bad "$MISS sections did not finish"
[ "$TORN_ONE" -eq 0 ]   && ok "one write per line: no torn line" || bad "one write per line: $TORN_ONE torn"
[ "$TORN_MULTI" -eq 0 ] && ok "six writes per line: no torn line" || bad "six writes per line: $TORN_MULTI torn"
[ "$TORN_OPEN" -eq 0 ]  && ok "open line first: no line lost, nothing frozen" || bad "open line first: $TORN_OPEN lost/torn"

echo "== counter-proof: word noserline (old behaviour), $BOOTS boots =="
measure cnt noserline
CT=$((TORN_MULTI+TORN_OPEN+TORN_ONE))
[ "$CT" -gt 0 ] \
    && ok "without the line lock lines are torn ($CT torn)" \
    || bad "without the line lock nothing tore -- the test measures nothing"

echo "== wire overlap: widened race between UART ready check and octet write =="
overlap() {
    OVL=0
    for n in $(seq 1 "$BOOTS"); do
        run "$1$n" "smpfrueh $2"
        local c
        c=$(tr -cd '\001' < "$TMPD/$1$n.txt" | wc -c)
        echo "        boot $n: overlap markers=$c"
        OVL=$((OVL + c))
    done
}
overlap wir "serwiden"
[ "$OVL" -eq 0 ] && ok "wire lock: writers never overlap in the UART" || bad "wire lock: $OVL overlaps"
overlap wcn "serwiden nowirelock"
[ "$OVL" -gt 0 ] \
    && ok "without the wire lock writers overlap ($OVL markers)" \
    || bad "without the wire lock nothing overlapped -- the gate measures nothing"

hold() {
    HKT=0; HTORN=0; HSL=0; HMISS=0
    for n in $(seq 1 "$HOLD_BOOTS"); do
        run "$1$n" "$2" 1 /t/h.sh
        local line k t s d
        line=$(python3 -I tools/serline/holdcheck.py "$TMPD/$1$n.txt" HOLD)
        echo "        boot $n: $line"
        k=$(val "$line" kt_intact); t=$(val "$line" kt_torn); s=$(val "$line" sl); d=$(val "$line" done)
        HKT=$((HKT+${k:-0})); HTORN=$((HTORN+${t:-0})); HSL=$((HSL+${s:-0}))
        [ "$d" = 1 ] || HMISS=$((HMISS+1))
    done
}

echo "== hold: kernel task keeps a line across timer ticks, user task writes on the same core =="
hold hld "serhold"
[ "$HMISS" -eq 0 ] && ok "hold: the user task finished every boot" || bad "hold: user task unfinished in $HMISS boots"
[ "$HKT" -ge $((HOLD_BOOTS * 3)) ] && ok "hold: kernel task lines were written ($HKT whole)" || bad "hold: only $HKT kernel task lines -- the test measures nothing"
[ "$HTORN" -eq 0 ] && ok "hold: kernel task line stays whole" || bad "hold: $HTORN kernel task lines torn"
[ "$HSL" -eq $((HOLD_BOOTS * HOLD_LINES)) ] && ok "hold: all user lines intact ($HSL)" || bad "hold: $HSL of $((HOLD_BOOTS * HOLD_LINES)) user lines intact"

echo "== hold counter-proof: word serholdsti (interrupts on inside the hold) =="
hold hcn "serholdsti"
[ "$HTORN" -gt 0 ] \
    && ok "with interrupts on inside the hold the line is torn ($HTORN torn)" \
    || bad "interrupts on inside the hold tore nothing -- the test measures nothing"

echo
summary_emit "$pass" "$fail" 14
