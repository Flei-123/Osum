#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
export FIRNLIB=$ROOT/lib
SIZE_MIB=${SIZE_MIB:-320}
MEM=${MEM:-8192}
SMP=${SMP:-4}
HIGH_GIB=${HIGH_GIB:-150}
MODES=${MODES:-"plain chunked"}
FETCH_SRC=${FETCH_SRC:-$ROOT/kernel/app/fetch.fi}
LABEL=${LABEL:-new}
TMO=${TMO:-900}
PORT=$((19000 + $$ % 900))
TMPD=${BIGFETCH_DIR:-$(mktemp -d)}
mkdir -p "$TMPD"
SRVPID=""
cleanup() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    [ -n "${BIGFETCH_KEEP:-}" ] || rm -rf "$TMPD"
}
trap cleanup EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
clean() { tr -d '\000' < "$1" 2>/dev/null; }
for t in qemu-system-x86_64 python3 sgdisk; do
    command -v "$t" >/dev/null 2>&1 || { echo "BIGFETCH: skipped, $t missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "BIGFETCH: skipped, python3-cryptography missing"; exit 0; }
[ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host" || ACCEL="-accel tcg"

echo "== 1. build =="
KERNEL=${KERNEL:-$TMPD/k.mb}
if [ ! -f "$KERNEL" ]; then
    bash tools/build-kernel.sh "$KERNEL" > "$TMPD/kb.txt" 2>&1 || { tail -5 "$TMPD/kb.txt"; echo "BIGFETCH: build failed"; exit 1; }
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s
SPEC="/bin/ /tmp/ /dev/ /proc/ /etc/ /etc/ssl/"
for p in sh ls echo rm df shasum; do
    vendor/firn/bin/firnc kernel/user/$p.fi -o "$TMPD/$p.o" 2> "$TMPD/e$p" || { head "$TMPD/e$p"; echo "BIGFETCH: build failed"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o"
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
mkdir -p "$TMPD/src/kernel/app"
cp "$FETCH_SRC" "$TMPD/src/kernel/app/fetch.fi"
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/fetch.o" "$TMPD/src/kernel/app/fetch.fi" > "$TMPD/fc.txt" 2>&1 \
    && ld -T kernel/user/user.ld -o "$TMPD/fetch.elf" "$TMPD/fetch.o" 2>> "$TMPD/fc.txt"; then
    strip --strip-all "$TMPD/fetch.elf" 2>/dev/null
    ok "fetch ($LABEL) built, $(stat -c%s "$TMPD/fetch.elf") octets"
else
    head -8 "$TMPD/fc.txt"; bad "fetch ($LABEL) does not build"; echo "BIGFETCH: $pass passed, $fail failed"; exit 1
fi
SPEC="$SPEC /bin/fetch=$TMPD/fetch.elf"
python3 -I tools/ota/mkcerts.py "$TMPD/certs" ota.test 10.0.2.2 > "$TMPD/certs.txt" 2>&1 || { cat "$TMPD/certs.txt"; bad "certificates"; exit 1; }
SPEC="$SPEC /etc/ssl/roots.pem=$TMPD/certs/ca.pem"
BLOCKS=$(( (SIZE_MIB + 120) * 2048 ))
START=$((HIGH_GIB * 2048 * 1024))
make_disk() {
    rm -f "$1"
    dd if=/dev/null of="$1" bs=512 seek=$((START + SECT + 6144)) count=0 status=none
    sgdisk -o "$1" > /dev/null 2>&1
    sgdisk -n 1:$START:$((START + SECT - 1)) -t 1:4F53554D-4F46-5301-8E75-6D6F72694F53 -c 1:OSUM "$1" > /dev/null 2>&1 || return 1
    dd if="$TMPD/d.img" of="$1" bs=512 seek=$START conv=notrunc,sparse status=none
}
python3 -I tools/bigfetch/server.py serve "$PORT" "$TMPD/certs/srv.pem" "$TMPD/certs/srv.key" > "$TMPD/srv.txt" 2>&1 &
SRVPID=$!
for i in $(seq 1 50); do grep -q START "$TMPD/srv.txt" 2>/dev/null && break; sleep 0.2; done
grep -q START "$TMPD/srv.txt" && ok "server up on port $PORT" || { bad "server"; exit 1; }
BYTES=$((SIZE_MIB * 1048576))
WANT=$(python3 -I tools/bigfetch/server.py sha "$BYTES")

STALL_MAX=${STALL_MAX:-12}
PROBE_SECS=${PROBE_SECS:-$((SIZE_MIB * 6 + 120))}
PROBE_PER_FILE=200
PROBE_RUNS=$(( (PROBE_SECS + PROBE_PER_FILE - 1) / PROBE_PER_FILE ))
PROBE_CALLS=$(for i in $(seq 1 "$PROBE_RUNS"); do printf 'sh /probe.sh;'; done)
for i in $(seq 1 "$PROBE_PER_FILE"); do printf 'echo PROBE\nsleep 1\n'; done > "$TMPD/probe.sh"
python3 -I tools/osum/mkfs.py build "$TMPD/d.img" "$BLOCKS" --v3 --inodes=256 $SPEC "/probe.sh=$TMPD/probe.sh" > "$TMPD/mk.txt" 2>&1 || { tail -3 "$TMPD/mk.txt"; bad "mkfs"; exit 1; }
SECT=$(( $(stat -c %s "$TMPD/d.img") / 512 ))

guest() { # <serial> <script>
    timeout "$TMO" qemu-system-x86_64 $ACCEL -smp "$SMP" -kernel "$KERNEL" -m "$MEM" \
        -append "osum vfs nokbd nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=$2" \
        -serial "file:$1" -display none -no-reboot \
        -device ahci,id=ahci -drive "file=$TMPD/live.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0 \
        -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}

for mode in $MODES; do
    echo "== 2. $mode: ${SIZE_MIB} MiB over TLS into a file with a probe running next to it, smp $SMP, ${MEM} MiB, $LABEL =="
    make_disk "$TMPD/live.img" || { bad "disk"; continue; }
    : > "$TMPD/g-$mode.txt"
    t0=$(date +%s)
    guest "$TMPD/g-$mode.txt" "fetch -n ota.test -o /big.bin https://10.0.2.2:$PORT/$mode?size=$BYTES &;${PROBE_CALLS}echo PHASE1-DONE;exit" &
    QPID=$!
    sleep 1
    QREAL=$(pgrep -P "$QPID" -f qemu-system | head -1)
    STALL=$(python3 -I tools/bigfetch/stall.py "$TMPD/g-$mode.txt" "${QREAL:-$QPID}" PHASE1-DONE)
    wait "$QPID" 2>/dev/null
    t1=$(date +%s)
    clean "$TMPD/g-$mode.txt" > "$TMPD/c-$mode.txt"
    GAP=${STALL%% *}
    echo "        phase 1 seconds $((t1 - t0)), probe stall (max gap, probes, finished): $STALL"
    grep -a "fetch: \(written\|octets\|code\|the file\)\|EXCEPTION\|PANIC\|panic\|out of mem\|nomem" "$TMPD/c-$mode.txt" | head -8 | sed 's/^/        /'
    grep -aq 'PHASE1-DONE' "$TMPD/c-$mode.txt" && ok "$mode: the probe script ran to the end" || bad "$mode: the guest hung or died before the probe script ended"
    grep -aq 'fetch: written' "$TMPD/c-$mode.txt" && ok "$mode: fetch reported the file written" || bad "$mode: fetch did not finish inside the probe window"
    if awk -v g="$GAP" -v m="$STALL_MAX" 'BEGIN{exit !(g <= m)}'; then ok "$mode: longest probe stall ${GAP}s <= ${STALL_MAX}s"; else bad "$mode: the system stalled ${GAP}s during the download (limit ${STALL_MAX}s)"; fi
    : > "$TMPD/v-$mode.txt"
    guest "$TMPD/v-$mode.txt" "shasum /big.bin;ls -l /;df;echo VERIFY-DONE;exit"
    clean "$TMPD/v-$mode.txt" > "$TMPD/vc-$mode.txt"
    GOT=$(grep -aoE '^[0-9a-f]{64}  /big.bin' "$TMPD/vc-$mode.txt" | tail -1 | cut -c1-64)
    [ "$GOT" = "$WANT" ] && ok "$mode: sha256 of the written file equals the server stream" || bad "$mode: sha256 '$GOT' expected '$WANT'"
    rm -f "$TMPD/live.img"
done
echo "BIGFETCH: $pass passed, $fail failed"
[ "$fail" = 0 ]
